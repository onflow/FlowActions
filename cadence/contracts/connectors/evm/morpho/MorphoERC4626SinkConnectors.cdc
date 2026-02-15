import "Burner"
import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "FlowToken"
import "DeFiActions"
import "DeFiActionsUtils"
import "EVMTokenConnectors"
import "ERC4626Utils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// MorphoERC4626SinkConnectors
///
access(all) contract MorphoERC4626SinkConnectors {

    /// AssetSink
    ///
    /// Deposits assets to a Morpho ERC4626 vault (which accepts the asset as a deposit denomination) to the contained COA's
    /// vault share balance
    ///
    access(all) struct AssetSink : DeFiActions.Sink {
        /// The asset type serving as the price basis in the ERC4626 vault
        access(self) let assetType: Type
        /// The EVM address of the asset ERC20 contract
        access(self) let assetEVMAddress: EVM.EVMAddress
        /// The address of the ERC4626 vault
        access(self) let vaultEVMAddress: EVM.EVMAddress
        /// The COA capability to use for the ERC4626 vault
        access(self) let coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
        /// The token sink to use for the ERC4626 vault
        access(self) let tokenSink: EVMTokenConnectors.Sink
        /// The optional UniqueIdentifier of the ERC4626 vault
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            vaultEVMAddress: EVM.EVMAddress,
            coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                coa.check():
                "Provided COA Capability is invalid - need Capability<&EVM.CadenceOwnedAccount>"

                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
            }
            self.vaultEVMAddress = vaultEVMAddress

            self.assetEVMAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: self.vaultEVMAddress)
                ?? panic("Cannot get an underlying asset EVM address from the vault")
            self.assetType = FlowEVMBridgeConfig.getTypeAssociated(with: self.assetEVMAddress)
                ?? panic("Underlying asset for vault \(self.vaultEVMAddress.toString()) (asset \(self.assetEVMAddress.toString())) is not associated with a Cadence FungibleToken - ensure the type & underlying asset contracts are associated via the VM bridge")
            assert(
                DeFiActionsUtils.definingContractIsFungibleToken(self.assetType),
                message: "Derived asset type \(self.assetType.identifier) not FungibleToken type"
            )

            self.coa = coa
            self.tokenSink = EVMTokenConnectors.Sink(
                max: nil,
                depositVaultType: self.assetType,
                address: coa.borrow()!.address(),
                feeSource: feeSource,
                uniqueID: uniqueID
            )
            self.uniqueID = uniqueID
        }

        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.assetType
        }
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64 {
            // Check the EVMTokenConnectors Sink has capacity to bridge the assets to EVM
            // TODO: Update EVMTokenConnector.Sink to return 0.0 if it doesn't have fees to pay for the bridge call
            let coa = self.coa.borrow()
            if coa == nil {
                return 0.0
            }
            let tokenSinkCapacity = self.tokenSink.minimumCapacity()
            return tokenSinkCapacity
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // check capacity & early return if none
            let capacity = self.minimumCapacity()
            if capacity == 0.0 || from.balance == 0.0 { return; }

            // withdraw the appropriate amount from the referenced vault & deposit to the EVMTokenConnectors Sink
            var amount = capacity <= from.balance ? capacity : from.balance

            // TODO: pass from through and skip the intermediary withdrawal
            // depositCapacity can deposit less than requested (capacity/fees/bridge constraints), and it doesn’t return "actualDeposited". Without the intermediary vault there's no way to safely compute the amount
            let deposit <- from.withdraw(amount: amount)
            self.tokenSink.depositCapacity(from: &deposit as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            if deposit.balance == amount {
                // nothing was deposited to the EVMTokenConnectors Sink
                Burner.burn(<-deposit)
                return
            } else if deposit.balance > 0.0 {
                // update deposit amount & deposit the residual
                amount = amount - deposit.balance
                from.deposit(from: <-deposit)
            } else {
                // nothing left - burn & execute vault's burnCallback()
                Burner.burn(<-deposit)
            }

            // approve the ERC4626 vault to spend the assets on deposit
            let uintAmount = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(amount, erc20Address: self.assetEVMAddress)
            let approveRes = self._call(
                    dry: false,
                    to: self.assetEVMAddress,
                    signature: "approve(address,uint256)",
                    args: [self.vaultEVMAddress, uintAmount],
                    gasLimit: 500_000
                )!
            if approveRes.status != EVM.Status.successful {
                // TODO: consider more graceful handling of this error
                panic(self._approveErrorMessage(ufixAmount: amount, uintAmount: uintAmount, approveRes: approveRes))
            }

            // deposit the assets to the ERC4626 vault
            let depositRes = self._call(
                dry: false,
                to: self.vaultEVMAddress,
                signature: "deposit(uint256,address)",
                args: [uintAmount, self.coa.borrow()!.address()],
                gasLimit: 1_000_000
            )!
            if depositRes.status != EVM.Status.successful {
                panic(self._depositErrorMessage(ufixAmount: amount, uintAmount: uintAmount, depositRes: depositRes))
            }
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.tokenSink.getComponentInfo()
                ]
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// Performs a dry call to the ERC4626 vault
        ///
        /// @param to The address of the ERC4626 vault
        /// @param signature The signature of the function to call
        /// @param args The arguments to pass to the function
        /// @param gasLimit The gas limit to use for the call
        ///
        /// @return The result of the dry call or `nil` if the COA capability is invalid
        access(self)
        fun _call(dry: Bool, to: EVM.EVMAddress, signature: String, args: [AnyStruct], gasLimit: UInt64): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: 0)
            if let coa = self.coa.borrow() {
                return dry
                    ? coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
                    : coa.call(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
            }
            return nil
        }
        /// Returns an error message for a failed approve call
        ///
        /// @param ufixAmount: the amount of assets to approve
        /// @param uintAmount: the amount of assets to approve in uint256 format
        /// @param approveRes: the result of the approve call
        ///
        /// @return an error message for a failed approve call
        ///
        access(self)
        fun _approveErrorMessage(ufixAmount: UFix64, uintAmount: UInt256, approveRes: EVM.Result): String {
            let s1 = "Failed to approve ERC4626 vault \(self.vaultEVMAddress.toString()) to spend \(ufixAmount) assets \(self.assetEVMAddress.toString()). ";
            let s2 = "approvee: \(self.vaultEVMAddress.toString()), amount: \(uintAmount). ";
            let s3 = "Error code: \(approveRes.errorCode) Error message: \(approveRes.errorMessage)";
            return "\(s1)\(s2)\(s3)"
        }
        /// Returns an error message for a failed deposit call
        ///
        /// @param ufixAmount: the amount of assets to deposit
        /// @param uintAmount: the amount of assets to deposit in uint256 format
        /// @param depositRes: the result of the deposit call
        ///
        /// @return an error message for a failed deposit call
        ///
        access(self)
        fun _depositErrorMessage(ufixAmount: UFix64, uintAmount: UInt256, depositRes: EVM.Result): String {
            let coaHex = self.coa.borrow()!.address().toString()
            let s1 = "Failed to deposit \(ufixAmount) assets \(self.assetEVMAddress.toString()) to ERC4626 vault \(self.vaultEVMAddress.toString()). ";
            let s2 = "amount: \(uintAmount), to: \(coaHex). ";
            let s3 = "Error code: \(depositRes.errorCode) Error message: \(depositRes.errorMessage)";
            return "\(s1)\(s2)\(s3)"
        }
    }
    /// ShareSink
    ///
    /// Redeems shares from a Morpho ERC4626 vault to the contained COA's underlying asset balance
    ///
    access(all) struct ShareSink : DeFiActions.Sink {
        /// The share vault type serving as the price basis in the ERC4626 vault
        access(self) let vaultType: Type
        /// The EVM address of the asset ERC20 contract
        access(self) let assetEVMAddress: EVM.EVMAddress
        /// The address of the ERC4626 vault
        access(self) let vaultEVMAddress: EVM.EVMAddress
        /// The COA capability to use for the ERC4626 vault
        access(self) let coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
        /// The token sink to use for the vault shares
        access(self) let shareSink: EVMTokenConnectors.Sink
        /// The optional UniqueIdentifier of the ERC4626 vault
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            vaultEVMAddress: EVM.EVMAddress,
            coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                coa.check():
                "Provided COA Capability is invalid - need Capability<&EVM.CadenceOwnedAccount>"

                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
            }
            self.vaultEVMAddress = vaultEVMAddress
            self.vaultType = FlowEVMBridgeConfig.getTypeAssociated(with: vaultEVMAddress)
                ?? panic("Provided ERC4626 Vault \(vaultEVMAddress.toString()) is not associated with a Cadence FungibleToken - ensure the type & ERC4626 contracts are associated via the VM bridge")
            assert(
                DeFiActionsUtils.definingContractIsFungibleToken(self.vaultType),
                message: "Derived vault type \(self.vaultType.identifier) not FungibleToken type"
            )

            self.assetEVMAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: vaultEVMAddress)
                ?? panic("Cannot get an underlying asset EVM address from the vault")
            let assetType = FlowEVMBridgeConfig.getTypeAssociated(with: self.assetEVMAddress)
                ?? panic("Underlying asset for vault \(self.vaultEVMAddress.toString()) (asset \(self.assetEVMAddress.toString())) is not associated with a Cadence FungibleToken - ensure the type & underlying asset contracts are associated via the VM bridge")
            assert(
                DeFiActionsUtils.definingContractIsFungibleToken(assetType),
                message: "Derived asset type \(assetType.identifier) not FungibleToken type"
            )

            self.coa = coa
            self.shareSink = EVMTokenConnectors.Sink(
                max: nil,
                depositVaultType: self.vaultType,
                address: coa.borrow()!.address(),
                feeSource: feeSource,
                uniqueID: uniqueID
            )
            self.uniqueID = uniqueID
        }

        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.vaultType
        }
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64 {
            // Check the EVMTokenConnectors Sink has capacity to bridge the shares to EVM
            // TODO: Update EVMTokenConnector.Sink to return 0.0 if it doesn't have fees to pay for the bridge call
            let coa = self.coa.borrow()
            if coa == nil {
                return 0.0
            }
            let shareSinkCapacity = self.shareSink.minimumCapacity()
            return shareSinkCapacity
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // check capacity & early return if none
            let capacity = self.minimumCapacity()
            if capacity == 0.0 || from.balance == 0.0 { return; }

            // withdraw the appropriate amount from the referenced vault & deposit to the EVMTokenConnectors Sink
            var amount = capacity <= from.balance ? capacity : from.balance

            // TODO: pass from through and skip the intermediary withdrawal
            let deposit <- from.withdraw(amount: amount)
            self.shareSink.depositCapacity(from: &deposit as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            if deposit.balance == amount {
                // nothing was deposited to the EVMTokenConnectors Sink
                Burner.burn(<-deposit)
                return
            } else if deposit.balance > 0.0 {
                // update deposit amount & deposit the residual
                amount = amount - deposit.balance
                from.deposit(from: <-deposit)
            } else {
                // nothing left - burn & execute vault's burnCallback()
                Burner.burn(<-deposit)
            }

            let uintShares = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(amount, erc20Address: self.vaultEVMAddress)

            let coa = self.coa.borrow() ?? panic("can't borrow COA")

            // redeem the shares from the ERC4626 vault
            let redeemRes = self._call(
                dry: false,
                to: self.vaultEVMAddress,
                signature: "redeem(uint256,address,address)",
                args: [uintShares, coa.address(), coa.address()],
                gasLimit: 1_000_000
            )!
            if redeemRes.status != EVM.Status.successful {
                // TODO: Consider unwinding the redeem & returning to the from vault
                //      - would require {Sink, Source} instead of just Sink
                panic(self._redeemErrorMessage(ufixShares: amount, uintShares: uintShares, redeemRes: redeemRes))
            }
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.shareSink.getComponentInfo()
                ]
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// Performs a dry call to the ERC4626 vault
        ///
        /// @param to The address of the ERC4626 vault
        /// @param signature The signature of the function to call
        /// @param args The arguments to pass to the function
        /// @param gasLimit The gas limit to use for the call
        ///
        /// @return The result of the dry call or `nil` if the COA capability is invalid
        access(self)
        fun _call(dry: Bool, to: EVM.EVMAddress, signature: String, args: [AnyStruct], gasLimit: UInt64): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: 0)
            if let coa = self.coa.borrow() {
                return dry
                    ? coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
                    : coa.call(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
            }
            return nil
        }
        /// Returns an error message for a failed redeem call
        ///
        /// @param ufixShares: the amount of shares to redeem
        /// @param uintShares: the amount of shares to redeem in uint256 format
        /// @param depositRes: the result of the redeem call
        ///
        /// @return an error message for a failed redeem call
        ///
        access(self)
        fun _redeemErrorMessage(ufixShares: UFix64, uintShares: UInt256, redeemRes: EVM.Result): String {
            let coaHex = self.coa.borrow()!.address().toString()
            let s1 = "Failed to redeem \(ufixShares) shares \(self.vaultEVMAddress.toString()) from ERC4626 vault for \(self.assetEVMAddress.toString()). ";
            let s2 = "amount: \(uintShares), to: \(coaHex). ";
            let s3 = "Error code: \(redeemRes.errorCode) Error message: \(redeemRes.errorMessage)";
            return "\(s1)\(s2)\(s3)"
        }
    }
}
