import "EVM"
import "Burner"
import "FlowToken"
import "FungibleToken"
import "DeFiActions"
import "DeFiActionsUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// EVMNativeFlowConnectors
///
/// A collection of DeFiActions connectors that target EVM addresses and deposit/withdraw FLOW as EVM-native FLOW
///
access(all) contract EVMNativeFLOWConnectors {

    /// Sink
    ///
    /// A DeFiActions connector that deposits FLOW to an EVM address as EVM-native FLOW
    ///
    access(all) struct Sink : DeFiActions.Sink {
        /// The maximum balance of the EVM address, checked before executing a deposit
        access(self) let maximumBalance: UFix64
        /// The EVM address of the linked EVM address
        access(self) let address: EVM.EVMAddress
        /// The unique identifier of the sink
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            max: UFix64?,
            address: EVM.EVMAddress,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            self.maximumBalance = max ?? UFix64.max
            self.address = address
            self.uniqueID = uniqueID
        }

        /// Returns the EVM address this Sink targets
        ///
        /// @return the EVM address this Sink targets
        ///
        access(all) view fun evmAddress(): EVM.EVMAddress {
            return self.address
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
        /// Returns the type of the Vault this Sink accepts
        ///
        /// @return the type of the Vault this Sink accepts
        ///
        access(all) view fun getSinkType(): Type {
            return Type<@FlowToken.Vault>()
        }
        /// Returns the minimum capacity of this Sink
        ///
        /// @return the minimum capacity of this Sink
        ///
        access(all) fun minimumCapacity(): UFix64 {
            let balance = self.address.balance().inFLOW()
            return balance < self.maximumBalance ? self.maximumBalance - balance : 0.0
        }
        /// Deposits the given FLOW vault into the EVM address's balance
        ///
        /// @param from: an authorized reference to the Vault from which to deposit funds
        ///
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if from.getType() != self.getSinkType() {
                return // unrelated vault type
            }

            // assess amount to deposit and assign COA reference
            let capacity = self.minimumCapacity()
            let amount = from.balance > capacity ? capacity : from.balance
            if amount == 0.0 {
                return // can't deposit without sufficient capacity
            }

            // deposit tokens
            self.address.deposit(from: <-from.withdraw(amount: amount) as! @FlowToken.Vault)
        }
    }

    /// Source
    ///
    /// A DeFiActions connector that withdraws FLOW from a COA as EVM-native FLOW
    ///
    access(all) struct Source : DeFiActions.Source {
        /// The minimum balance of the COA, checked before executing a withdrawal
        access(self) let minimumBalance: UFix64
        /// The COA to withdraw tokens from
        access(self) let coa: Capability<auth(EVM.Withdraw) &EVM.CadenceOwnedAccount>
        /// The EVM address of the linked COA
        access(self) let address: EVM.EVMAddress
        /// The unique identifier of the source
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            min: UFix64?,
            coa: Capability<auth(EVM.Withdraw) &EVM.CadenceOwnedAccount>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                coa.check():
                "Provided COA Capability is invalid - provided an invalid Capability<auth(EVM.Withdraw) &EVM.CadenceOwnedAccount>"
            }
            self.minimumBalance = min ?? 0.0
            self.coa = coa
            self.address = coa.borrow()!.address()
            self.uniqueID = uniqueID
        }

        /// Returns the EVM address this Source targets
        ///
        /// @return the EVM address this Source targets
        ///
        access(all) view fun evmAddress(): EVM.EVMAddress {
            return self.address
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
            return Type<@FlowToken.Vault>()
        }
        /// Returns the minimum available balance of this Source
        ///
        /// @return the minimum available balance of this Source
        ///
        access(all) fun minimumAvailable(): UFix64 {
            if let balance = self.coa.borrow()?.balance()?.inFLOW() {
                return self.minimumBalance < balance ? balance - self.minimumBalance : 0.0
            }
            return 0.0
        }
        /// Withdraws the given amount of FLOW from the COA's EVM-native FLOW balance
        ///
        /// @param maxAmount: the maximum amount of FLOW to withdraw
        ///
        /// @return a Vault containing the withdrawn FLOW
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            if let coa = self.coa.borrow() {
                let available = self.minimumAvailable()
                if available > 0.0 {
                    let amount = available > maxAmount ? maxAmount : available
                    let balance = EVM.Balance(attoflow: 0)
                    balance.setFLOW(flow: amount)
                    return <- coa.withdraw(balance: balance)
                }
            }
            return <- FlowToken.createEmptyVault(vaultType: self.getSourceType())
        }
    }
}
