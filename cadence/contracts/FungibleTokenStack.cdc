import "FungibleToken"

import "StackFiInterfaces"

access(all) contract FungibleTokenStack {

    access(all) struct VaultSink : StackFiInterfaces.Sink {
        access(all) let depositVaultType: Type
        access(all) let maximumBalance: UFix64
        access(self) let depositVault: Capability<&{FungibleToken.Vault}>
        
        view init(
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

        access(all) view fun getSinkType(): Type {
            return self.depositVaultType
        }

        access(all) fun minimumCapacity(): UFix64 {
            if let vault = self.borrowVault() {
                return vault.balance < self.maximumBalance ? self.maximumBalance - vault.balance : 0.0
            }
            return 0.0
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            pre {
                self.checkVault(): "Contained FungibleToken Vault Capability is no longer valid"
            }
            let minimumCapacity = self.minimumCapacity()
            // deposit the lesser of the originating vault balance and minimum capacity
            let capacity = minimumCapacity <= from.balance ? minimumCapacity : from.balance
            self.borrowVault()!.deposit(from: <-from.withdraw(amount: capacity))
        }

        access(all) view fun checkVault(): Bool {
            return self.depositVault.check()
        }

        access(all) view fun getVaultBalance(): UFix64 {
            return self.borrowVault()?.balance ?? 0.0
        }

        access(self) view fun borrowVault(): &{FungibleToken.Vault}? {
            return self.depositVault.borrow()
        }
    }

    access(all) struct VaultSource : StackFiInterfaces.Source {
        access(all) let withdrawVaultType: Type
        access(all) let minimumBalance: UFix64
        access(self) let withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        
        view init(
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

        access(all) view fun getSourceType(): Type {
            return self.withdrawVaultType
        }

        access(all) fun minimumAvailable(): UFix64 {
            if let vault = self.borrowVault() {
                return vault.balance < self.minimumBalance ? vault.balance - self.minimumBalance : 0.0
            }
            return 0.0
        }

        access(all) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            pre {
                self.checkVault(): "Contained FungibleToken Vault Capability is no longer valid"
            }
            let available = self.minimumAvailable()
            // take the lesser between the available and maximum requested amount
            let withdrawalAmount = available < maxAmount ? available : maxAmount
            return <- self.borrowVault()!.withdraw(amount: withdrawalAmount)
        }

        access(all) view fun checkVault(): Bool {
            return self.withdrawVault.check()
        }

        access(self) view fun borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault}? {
            return self.withdrawVault.borrow()
        }
    }
}