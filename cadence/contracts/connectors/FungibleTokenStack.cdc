import "FungibleToken"
import "FungibleTokenMetadataViews"

import "DeFiActionsUtils"
import "DeFiActions"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// FungibleTokenStack
///
/// This contract defines generic StackFi Sink & Source connector implementations for use with underlying Vault
/// Capabilities. These connectors can be used alone or in conjunction with other StackFi connectors to create complex
/// DeFi workflows.
///
access(all) contract FungibleTokenStack {

    access(all) struct VaultSink : DeFiActions.Sink {
        /// The Vault Type accepted by the Sink
        access(all) let depositVaultType: Type
        /// The maximum balance of the linked Vault, checked before executing a deposit
        access(all) let maximumBalance: UFix64
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        /// An unentitled Capability on the Vault to which deposits are distributed
        access(self) let depositVault: Capability<&{FungibleToken.Vault}>

        init(
            max: UFix64?,
            depositVault: Capability<&{FungibleToken.Vault}>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                depositVault.check(): "Provided invalid Capability"
                DeFiActionsUtils.definingContractIsFungibleToken(depositVault.borrow()!.getType()):
                "The contract defining Vault \(depositVault.borrow()!.getType().identifier) does not conform to FungibleToken contract interface"
            }
            self.maximumBalance = max ?? UFix64.max // assume no maximum if none provided
            self.uniqueID = uniqueID
            self.depositVaultType = depositVault.borrow()!.getType()
            self.depositVault = depositVault
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the VaultSink
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
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
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.depositVaultType
        }
        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        access(all) fun minimumCapacity(): UFix64 {
            if let vault = self.depositVault.borrow() {
                return vault.balance < self.maximumBalance ? self.maximumBalance - vault.balance : 0.0
            }
            return 0.0
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            let minimumCapacity = self.minimumCapacity()
            if !self.depositVault.check() || minimumCapacity == 0.0 {
                return
            }
            // deposit the lesser of the originating vault balance and minimum capacity
            let capacity = minimumCapacity <= from.balance ? minimumCapacity : from.balance
            self.depositVault.borrow()!.deposit(from: <-from.withdraw(amount: capacity))
        }
    }

    access(all) struct VaultSource : DeFiActions.Source {
        /// Returns the Vault type provided by this Source
        access(all) let withdrawVaultType: Type
        /// The minimum balance of the linked Vault
        access(all) let minimumBalance: UFix64
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        /// An entitled Capability on the Vault from which withdrawals are sourced
        access(self) let withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>

        init(
            min: UFix64?,
            withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                withdrawVault.check(): "Provided invalid Capability"
                DeFiActionsUtils.definingContractIsFungibleToken(withdrawVault.borrow()!.getType()):
                "The contract defining Vault \(withdrawVault.borrow()!.getType().identifier) does not conform to FungibleToken contract interface"
            }
            self.minimumBalance = min ?? 0.0 // assume no minimum if none provided
            self.withdrawVault = withdrawVault
            self.uniqueID = uniqueID
            self.withdrawVaultType = withdrawVault.borrow()!.getType()
        }
        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the VaultSource
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
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
        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type {
            return self.withdrawVaultType
        }
        /// Returns an estimate of how much of the associated Vault can be provided by this Source
        access(all) fun minimumAvailable(): UFix64 {
            if let vault = self.withdrawVault.borrow() {
                return self.minimumBalance < vault.balance ? vault.balance - self.minimumBalance : 0.0
            }
            return 0.0
        }
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let available = self.minimumAvailable()
            if !self.withdrawVault.check() || available == 0.0 || maxAmount == 0.0 {
                return <- DeFiActionsUtils.getEmptyVault(self.withdrawVaultType)
            }
            // take the lesser between the available and maximum requested amount
            let withdrawalAmount = available <= maxAmount ? available : maxAmount
            return <- self.withdrawVault.borrow()!.withdraw(amount: withdrawalAmount)
        }
    }

    access(all) struct VaultSinkAndSource : DeFiActions.Sink, DeFiActions.Source {
        /// The minimum balance of the linked Vault
        access(all) let minimumBalance: UFix64
        /// The maximum balance of the linked Vault
        access(all) let maximumBalance: UFix64
        /// The type of Vault this connector accepts (as a Sink) and provides (as a Source)
        access(all) let vaultType: Type
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        /// An entitled Capability on the Vault from which withdrawals are sourced & deposit are routed
        access(self) let vault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>

        init(
            min: UFix64?,
            max: UFix64?,
            vault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                vault.check(): "Invalid Vault Capability provided"
                DeFiActionsUtils.definingContractIsFungibleToken(vault.borrow()!.getType()):
                "The contract defining Vault \(vault.borrow()!.getType().identifier) does not conform to FungibleToken contract interface"
                min ?? 0.0 < max ?? UFix64.max:
                "Minimum balance must be less than maximum balance if either is declared"
            }
            self.minimumBalance = min ?? 0.0
            self.maximumBalance = max ?? UFix64.max
            self.vaultType = vault.borrow()!.getType()
            self.uniqueID = uniqueID
            self.vault = vault
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the VaultSinkAndSource
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
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
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.vaultType
        }
        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type {
            return self.vaultType
        }
        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        access(all) fun minimumCapacity(): UFix64 {
            if let vault = self.vault.borrow() {
                return vault.balance < self.maximumBalance ? self.maximumBalance - vault.balance : 0.0
            }
            return 0.0
        }
        /// Returns an estimate of how much of the associated Vault can be provided by this Source
        access(all) fun minimumAvailable(): UFix64 {
            if let vault = self.vault.borrow() {
                return vault.balance < self.minimumBalance ? vault.balance - self.minimumBalance : 0.0
            }
            return 0.0
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if let vault = self.vault.borrow() {
                vault.deposit(from: <-from.withdraw(amount: from.balance))
            }
        }
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            if let vault = self.vault.borrow() {
                let finalAmount = vault.balance < maxAmount ? vault.balance : maxAmount
                return <-vault.withdraw(amount: finalAmount)
            }
            return <- DeFiActionsUtils.getEmptyVault(self.vaultType)
        }
    }
}
