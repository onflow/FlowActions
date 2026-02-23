import "Burner"
import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "FlowToken"
import "DeFiActions"
import "EVMTokenConnectors"
import "ERC4626Utils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// ERC4626SinkConnectors
///
access(all) contract ERC4626SinkConnectors {

    /// AssetSink
    ///
    /// Deposits assets to an ERC4626 vault (which accepts the asset as a deposit denomination) to the contained COA's
    /// vault share balance
    ///
    access(all) struct AssetSink : DeFiActions.Sink {
        /// The asset type serving as the price basis in the ERC4626 vault
        access(self) let asset: Type
        /// The EVM address of the asset ERC20 contract
        access(self) let assetEVMAddress: EVM.EVMAddress
        /// The address of the ERC4626 vault
        access(self) let vault: EVM.EVMAddress
        /// The COA capability to use for the ERC4626 vault
        access(self) let coa: Capability<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>
        /// The token sink to use for bridging assets to EVM
        access(self) let tokenSink: EVMTokenConnectors.Sink
        /// The token source to use for bridging assets back from EVM on failure recovery
        access(self) let tokenSource: EVMTokenConnectors.Source
        /// The optional UniqueIdentifier of the ERC4626 vault
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            asset: Type,
            vault: EVM.EVMAddress,
            coa: Capability<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                asset.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Provided asset \(asset.identifier) is not a Vault type"
                coa.check():
                "Provided COA Capability is invalid - need Capability<&EVM.CadenceOwnedAccount>"

                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
            }
            self.asset = asset
            self.assetEVMAddress = FlowEVMBridgeConfig.getEVMAddressAssociated(with: asset)
                ?? panic("Provided asset \(asset.identifier) is not associated with ERC20 - ensure the type & ERC20 contracts are associated via the VM bridge")
            
            let actualUnderlyingAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: vault)
            assert(
                actualUnderlyingAddress?.equals(self.assetEVMAddress) ?? false,
                message: "Provided asset \(asset.identifier) does not underly ERC4626 vault \(vault.toString()) - found \(actualUnderlyingAddress?.toString() ?? "nil") but expected \(self.assetEVMAddress.toString())"
            )
            
            self.vault = vault
            self.coa = coa
            self.tokenSink = EVMTokenConnectors.Sink(
                max: nil,
                depositVaultType: asset,
                address: coa.borrow()!.address(),
                feeSource: feeSource,
                uniqueID: uniqueID
            )
            self.tokenSource = EVMTokenConnectors.Source(
                min: nil,
                withdrawVaultType: asset,
                coa: coa,
                feeSource: feeSource,
                uniqueID: uniqueID
            )
            self.uniqueID = uniqueID
        }

        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.asset
        }
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64 {
            // Check the EVMTokenConnectors Sink has capacity to bridge the assets to EVM
            let coa = self.coa.borrow()
            if coa == nil {
                return 0.0
            }
            let tokenSinkCapacity = self.tokenSink.minimumCapacity()
            if tokenSinkCapacity == 0.0 {
                return 0.0
            }
            // Check the ERC4626 vault has capacity to deposit the assets
            let max = ERC4626Utils.maxDeposit(vault: self.vault, receiver: coa!.address())
            let vaultCapacity = max != nil
                ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(max!, erc20Address: self.assetEVMAddress)
                : 0.0
            if vaultCapacity == 0.0 {
                return 0.0
            }
            return tokenSinkCapacity <= vaultCapacity ? tokenSinkCapacity : vaultCapacity
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // check capacity & early return if none
            let capacity = self.minimumCapacity()
            if capacity == 0.0 || from.balance == 0.0 { return; }

            // withdraw the appropriate amount from the referenced vault & deposit to the EVMTokenConnectors Sink
            var amount = capacity <= from.balance ? capacity : from.balance

            // Intermediary withdrawal is needed to cap the amount at the ERC4626 vault capacity, since
            // tokenSink.depositCapacity only limits by its own capacity and not the ERC4626 vault's
            let deposit <- from.withdraw(amount: amount)
            self.tokenSink.depositCapacity(from: &deposit as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            let remainder = deposit.balance

            if remainder == amount {
                // 0 deposited -> return everything, stop
                from.deposit(from: <-deposit)
                return
            }

            if remainder > 0.0 {
                // partial deposited -> return remainder
                amount = amount - remainder
                from.deposit(from: <-deposit)
            } else {
                // fully deposited -> clean up empty vault
                Burner.burn(<-deposit)
            }

            // approve the ERC4626 vault to spend the assets on deposit
            let uintAmount = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(amount, erc20Address: self.assetEVMAddress)
            let approveRes = self._call(
                    dry: false,
                    to: self.assetEVMAddress,
                    signature: "approve(address,uint256)",
                    args: [self.vault, uintAmount],
                    gasLimit: 500_000
                )!
            if approveRes.status != EVM.Status.successful {
                // Approve failed — attempt to bridge tokens back from EVM to Cadence
                if self._bridgeTokenBackOnRevert(amount: amount, receiver: from) {
                    return
                }
                panic(self._approveErrorMessage(ufixAmount: amount, uintAmount: uintAmount, approveRes: approveRes))
            }

            // deposit the assets to the ERC4626 vault
            let depositRes = self._call(
                dry: false,
                to: self.vault,
                signature: "deposit(uint256,address)",
                args: [uintAmount, self.coa.borrow()!.address()],
                gasLimit: 1_000_000
            )!
            if depositRes.status != EVM.Status.successful {
                // Deposit failed — revoke the approval and attempt to bridge tokens back
                let revokeRes = self._call(
                    dry: false,
                    to: self.assetEVMAddress,
                    signature: "approve(address,uint256)",
                    args: [self.vault, 0 as UInt256],
                    gasLimit: 500_000
                )!
                if revokeRes.status != EVM.Status.successful {
                    panic("Failed to revoke approval after deposit failure. Vault: \(self.vault.toString()), Asset: \(self.assetEVMAddress.toString()). Error code: \(revokeRes.errorCode) Error message: \(revokeRes.errorMessage)")
                }
                if self._bridgeTokenBackOnRevert(amount: amount, receiver: from) {
                    return
                }
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
        /// Attempts to bridge tokens back from EVM to Cadence when an operation fails.
        /// If successful, deposits the recovered tokens to the receiver vault and returns true.
        /// If unsuccessful (no tokens recovered), destroys the empty vault and returns false.
        ///
        /// @param amount: the maximum amount of assets to recover
        /// @param receiver: the vault to deposit recovered tokens into
        ///
        /// @return true if tokens were recovered and deposited, false otherwise
        ///
        access(self)
        fun _bridgeTokenBackOnRevert(amount: UFix64, receiver: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}): Bool {
            let recovered <- self.tokenSource.withdrawAvailable(maxAmount: amount)
            // withdraws up to `maxAmount: amount`, but recovered.balance may be slightly less than `amount`
            // due to UFix64/UInt256 rounding
            let tolerance = 0.00000001
            if recovered.balance >= amount - tolerance {
                receiver.deposit(from: <-recovered)
                return true
            }
            Burner.burn(<-recovered)
            return false
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
            return "Failed to approve ERC4626 vault \(self.vault.toString()) to spend \(ufixAmount) assets \(self.assetEVMAddress.toString()). "
                .concat("approvee: \(self.vault.toString()), amount: \(uintAmount). ")
                .concat("Error code: \(approveRes.errorCode) Error message: \(approveRes.errorMessage)")
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
            return "Failed to deposit \(ufixAmount) assets \(self.assetEVMAddress.toString()) to ERC4626 vault \(self.vault.toString()). "
                .concat("amount: \(uintAmount), to: \(coaHex). ")
                .concat("Error code: \(depositRes.errorCode) Error message: \(depositRes.errorMessage)")
        }
    }
}
