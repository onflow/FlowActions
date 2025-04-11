import "FungibleToken"
import "FungibleTokenMetadataViews"

import "StackFiInterfaces"

/// FungibleTokenStack
///
/// This contract defines generic StackFi Sink & Source connector implementations for use with underlying Vault
/// Capabilities. These connectors can be used alone or in conjunction with other StackFi connectors to create complex
/// DeFi workflows.
///
access(all) contract FungibleTokenStack {

    access(all) struct VaultSink : StackFiInterfaces.Sink {
        /// The Vault Type accepted by the Sink
        access(all) let depositVaultType: Type
        /// The maximum balance of the linked Vault, checked before executing a deposit
        access(all) let maximumBalance: UFix64
        /// An unentitled Capability on the Vault to which deposits are distributed
        access(self) let depositVault: Capability<&{FungibleToken.Vault}>
        
        init(
            maximumBalance: UFix64,
            depositVault: Capability<&{FungibleToken.Vault}>
        ) {
            pre {
                depositVault.check(): "Provided invalid Capability"
            }
            self.maximumBalance = maximumBalance
            self.depositVault = depositVault
            self.depositVaultType = depositVault.borrow()!.getType()
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
            if !self.depositVault.check() {
                return
            }
            let minimumCapacity = self.minimumCapacity()
            // deposit the lesser of the originating vault balance and minimum capacity
            let capacity = minimumCapacity <= from.balance ? minimumCapacity : from.balance
            self.depositVault.borrow()!.deposit(from: <-from.withdraw(amount: capacity))
        }
    }

    access(all) struct VaultSource : StackFiInterfaces.Source {
        /// Returns the Vault type provided by this Source
        access(all) let withdrawVaultType: Type
        /// The minimum balance of the linked Vault
        access(all) let minimumBalance: UFix64
        /// An entitled Capability on the Vault from which withdrawals are sourced
        access(self) let withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        
        init(
            minimumBalance: UFix64,
            withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        ) {
            pre {
                withdrawVault.check(): "Provided invalid Capability"
            }
            self.minimumBalance = minimumBalance
            self.withdrawVault = withdrawVault
            self.withdrawVaultType = withdrawVault.borrow()!.getType()
        }

        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type {
            return self.withdrawVaultType
        }

        /// Returns an estimate of how much of the associated Vault can be provided by this Source
        access(all) fun minimumAvailable(): UFix64 {
            if let vault = self.withdrawVault.borrow() {
                return vault.balance < self.minimumBalance ? vault.balance - self.minimumBalance : 0.0
            }
            return 0.0
        }

        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be 
        /// returned
        access(all) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            if !self.withdrawVault.check() {
                return <- FungibleTokenStack.getEmptyVault(forType: self.withdrawVaultType)
            }
            let available = self.minimumAvailable()
            // take the lesser between the available and maximum requested amount
            let withdrawalAmount = available < maxAmount ? available : maxAmount
            return <- self.withdrawVault.borrow()!.withdraw(amount: withdrawalAmount)
        }
    }

    /// Internal helper returning an empty Vault of the given Type
    access(self)
    fun getEmptyVault(forType: Type): @{FungibleToken.Vault} {
        return <- getAccount(forType.address!).contracts.borrow<&{FungibleToken}>(
                name: forType.contractName!
            )!.createEmptyVault(vaultType: forType)
    }
}