import "EVM"
import "Burner"
import "FlowToken"
import "FungibleToken"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "FlowEVMBridge"
import "DeFiActions"
import "DeFiActionsUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// EVMTokenConnectors
///
/// A collection of DeFiActions connectors that deposit/withdraw tokens to/from EVM addresses.
/// NOTE: These connectors move FLOW to/from the COA's WFLOW balance, not it's native FLOW balance. See
///       EVMNativeFlowConnectors for connectors that move FLOW to/from the COA's native FLOW balance.
///
access(all) contract EVMTokenConnectors {

    /// Sink
    ///
    /// A DeFiActions connector that deposits tokens to an EVM address's balance of ERC20 tokens
    /// NOTE: If FLOW is deposited, it affects the COA's WFLOW balance not it's native FLOW balance.
    ///
    access(all) struct Sink : DeFiActions.Sink {
        /// The maximum balance of the COA, checked before executing a deposit
        access(self) let maximumBalance: UFix64
        /// The type of the Vault to deposit
        access(self) let depositVaultType: Type
        /// The EVM address of the linked COA
        access(self) let address: EVM.EVMAddress
        /// The source of the VM bridge fees, providing FLOW
        access(self) let feeSource: {DeFiActions.Sink, DeFiActions.Source}
        /// The unique identifier of the sink
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            max: UFix64?,
            depositVaultType: Type,
            address: EVM.EVMAddress,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                FlowEVMBridgeConfig.getEVMAddressAssociated(with: depositVaultType) != nil:
                "Provided type \(depositVaultType.identifier) has not been onboarded to the VM bridge - "
                    .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
                feeSource.getSinkType() == Type<@FlowToken.Vault>() && feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Provided feeSource must provide FlowToken.Vault but provides \(feeSource.getSourceType().identifier)"
            }
            self.maximumBalance = max ?? UFix64.max // assume no maximum if none provided
            self.depositVaultType = depositVaultType
            self.address = address
            self.feeSource = feeSource
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this Sink and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.feeSource.getComponentInfo()
                ]
            )
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Returns the type of the Vault this Sink accepts
        ///
        /// @return the type of the Vault this Sink accepts
        ///
        access(all) view fun getSinkType(): Type {
            return self.depositVaultType
        }
        /// Returns the minimum capacity of this Sink
        ///
        /// @return the minimum capacity of this Sink
        ///
        access(all) fun minimumCapacity(): UFix64 {
            let erc20Address = FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.depositVaultType)!
            let balance = FlowEVMBridgeUtils.balanceOf(owner: self.address, evmContractAddress: erc20Address)
            let balanceInCadence = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                balance,
                erc20Address: erc20Address
            )
            return balanceInCadence < self.maximumBalance ? self.maximumBalance - balanceInCadence : 0.0
        }
        /// Deposits the given Vault into the EVM address's balance
        ///
        /// @param from: an authorized reference to the Vault from which to deposit funds
        ///
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if from.getType() != self.depositVaultType {
                return // unrelated vault type
            }

            // assess amount to deposit
            let capacity = self.minimumCapacity()
            let amount = from.balance > capacity ? capacity : from.balance
            if amount == 0.0 {
                return // can't deposit without sufficient capacity
            }

            // collect VM bridge fees
            let feeAmount = FlowEVMBridgeConfig.baseFee * 2.0
            if self.feeSource.minimumAvailable() < feeAmount {
                return // early return here instead of reverting in bridge scope on insufficient fees
            }
            let fees <- self.feeSource.withdrawAvailable(maxAmount: feeAmount)

            // deposit tokens and handle remaining fees
            FlowEVMBridge.bridgeTokensToEVM(
                vault: <-from.withdraw(amount: amount),
                to: self.address,
                feeProvider: &fees as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
            )
            self._handleRemainingFees(<-fees)
        }
        /// Handles the remaining fees after a withdrawal
        ///
        /// @param feeVault: the Vault containing the remaining fees
        ///
        access(self) fun _handleRemainingFees(_ feeVault: @{FungibleToken.Vault}) {
            if feeVault.balance > 0.0 {
                self.feeSource.depositCapacity(from: &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            }
            Burner.burn(<-feeVault)
        }
    }

    /// Source
    ///
    /// A DeFiActions connector that withdraws tokens from a CadenceOwnedAccount's balance of ERC20 tokens
    /// NOTE: If FLOW is withdrawn, it affects the COA's WFLOW balance not it's native FLOW balance.
    ///
    access(all) struct Source : DeFiActions.Source {
        /// The minimum balance of the COA, checked before executing a withdrawal
        access(self) let minimumBalance: UFix64
        /// The type of the Vault to withdraw
        access(self) let withdrawVaultType: Type
        /// The COA to withdraw tokens from
        access(self) let coa: Capability<auth(EVM.Bridge) &EVM.CadenceOwnedAccount>
        /// The EVM address of the linked COA
        access(self) let address: EVM.EVMAddress
        /// The source of the VM bridge fees, providing FLOW
        access(self) let feeSource: {DeFiActions.Sink, DeFiActions.Source}
        /// The unique identifier of the source
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            min: UFix64?,
            withdrawVaultType: Type,
            coa: Capability<auth(EVM.Bridge) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                FlowEVMBridgeConfig.getEVMAddressAssociated(with: withdrawVaultType) != nil:
                "Provided type \(withdrawVaultType.identifier) has not been onboarded to the VM bridge - "
                    .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
                DeFiActionsUtils.definingContractIsFungibleToken(withdrawVaultType):
                "The contract defining Vault \(withdrawVaultType.identifier) does not conform to FungibleToken contract interface"
                coa.check():
                "Provided COA Capability is invalid - provided an invalid Capability<auth(EVM.Bridge) &EVM.CadenceOwnedAccount>"
                feeSource.getSinkType() == Type<@FlowToken.Vault>() && feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Provided feeSource must provide FlowToken.Vault but provides \(feeSource.getSourceType().identifier)"
            }
            self.minimumBalance = min ?? 0.0
            self.withdrawVaultType = withdrawVaultType
            self.coa = coa
            self.feeSource = feeSource
            self.address = coa.borrow()!.address()
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this Source and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Returns the type of the Vault this Source accepts
        ///
        /// @return the type of the Vault this Source accepts
        ///
        access(all) view fun getSourceType(): Type {
            return self.withdrawVaultType
        }
        /// Returns the minimum available balance of this Source
        ///
        /// @return the minimum available balance of this Source
        ///
        access(all) fun minimumAvailable(): UFix64 {
            if let coa = self.coa.borrow() {
                let erc20Address = FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.withdrawVaultType)!
                let balance = FlowEVMBridgeUtils.balanceOf(owner: coa.address(), evmContractAddress: erc20Address)
                let balanceInCadence = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    balance,
                    erc20Address: erc20Address
                )
                return self.minimumBalance < balanceInCadence ? balanceInCadence - self.minimumBalance : 0.0
            }
            return 0.0
        }
        /// Withdraws the given amount of tokens from the CadenceOwnedAccount's balance of ERC20 tokens
        ///
        /// @param maxAmount: the maximum amount of tokens to withdraw
        ///
        /// @return a Vault containing the withdrawn tokens
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let available = self.minimumAvailable()
            let coa = self.coa.borrow()

            // collect VM bridge fees
            let feeAmount = FlowEVMBridgeConfig.baseFee
            if available > 0.0 && coa != nil && self.feeSource.minimumAvailable() >= feeAmount {
                // convert final cadence amount to erc20 amount
                let ufixAmount = available > maxAmount ? maxAmount : available
                let erc20Address = FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.withdrawVaultType)!
                let uintAmount = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(ufixAmount, erc20Address: erc20Address)

                // withdraw tokens & handle fees
                let fees <- self.feeSource.withdrawAvailable(maxAmount: feeAmount)
                let tokens <- coa!.withdrawTokens(
                    type: self.getSourceType(),
                    amount: uintAmount,
                    feeProvider: &fees as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
                )
                self._handleRemainingFees(<-fees)

                return <- tokens
            }

            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }
        /// Handles the remaining fees after a withdrawal
        ///
        /// @param feeVault: the Vault containing the remaining fees
        ///
        access(self) fun _handleRemainingFees(_ feeVault: @{FungibleToken.Vault}) {
            if feeVault.balance > 0.0 {
                self.feeSource.depositCapacity(from: &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            }
            Burner.burn(<-feeVault)
        }
    }
}
