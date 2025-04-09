import "FungibleToken"
import "StackFiInterfaces"

access(all) contract FungibleTokenStack {

    access(all) struct interface CapacityCheck {
        access(all) view fun getCapacity(currentBalance: UFix64): UFix64
    }

    access(all) struct MinimumCapacityCheck : CapacityCheck {
        access(all) let min: UFix64

        view init(min: UFix64) {
            self.min = min
        }

        access(all) view fun getCapacity(currentBalance: UFix64): UFix64 {
            return currentBalance < self.min ? self.min - currentBalance : 0.0
        }
    }

    access(all) struct MaximumCapacityCheck : CapacityCheck {
        access(all) let max: UFix64

        view init(max: UFix64) {
            self.max = max
        }

        access(all) view fun getCapacity(currentBalance: UFix64): UFix64 {
            return currentBalance < self.max ? self.max - currentBalance : 0.0
        }
    }

    access(all) struct VaultSink : StackFiInterfaces.Sink {
        access(all) let depositVaultType: Type
        access(all) let capacityCheck: {CapacityCheck}
        access(self) let depositVault: Capability<&{FungibleToken.Vault}>
        
        view init(
            capacityCheck: {CapacityCheck}?,
            depositVault: Capability<&{FungibleToken.Vault}>
        ) {
            pre {
                depositVault.check(): "Provided invalid Capability"
            }
            self.capacityCheck = capacityCheck != nil ? capacityCheck! : MaximumCapacityCheck(max: UFix64.max)
            self.depositVault = depositVault
            self.depositVaultType = depositVault.borrow()!.getType()
        }

        access(all) view fun getSinkType(): Type {
            return self.depositVaultType
        }

        access(all) fun minimumCapacity(): UFix64 {
            if let vault = self.borrowVault() {
                return self.capacityCheck.getCapacity(currentBalance: vault.balance)
            }
            return 0.0
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            pre {
                self.checkVault(): "Contained FungibleToken Vault Capability is no longer valid"
            }
            let minimumCapacity = self.minimumCapacity()
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
        access(all) let capacityCheck: {CapacityCheck}
        access(self) let withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        
        view init(
            capacityCheck: {CapacityCheck}?,
            withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        ) {
            pre {
                withdrawVault.check(): "Provided invalid Capability"
            }
            self.capacityCheck = capacityCheck != nil ? capacityCheck! : MaximumCapacityCheck(max: UFix64.max)
            self.withdrawVault = withdrawVault
            self.withdrawVaultType = withdrawVault.borrow()!.getType()
        }

        access(all) view fun getSourceType(): Type {
            return self.withdrawVaultType
        }

        access(all) fun minimumAvailable(): UFix64 {
            if let vault = self.borrowVault() {
                let capacity = self.capacityCheck.getCapacity(currentBalance: vault.balance)
                return capacity <= vault.balance ? capacity : vault.balance
            }
            return 0.0
        }

        access(all) fun withdrawAvailable(): @{FungibleToken.Vault} {
            pre {
                self.checkVault(): "Contained FungibleToken Vault Capability is no longer valid"
            }
            return <- self.borrowVault()!.withdraw(amount: self.minimumAvailable())
        }

        access(all) view fun checkVault(): Bool {
            return self.withdrawVault.check()
        }

        access(self) view fun borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault}? {
            return self.withdrawVault.borrow()
        }
    }
}