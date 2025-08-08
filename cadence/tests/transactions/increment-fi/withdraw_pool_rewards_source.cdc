import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(pid: UInt64, vaultType: Type) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let tokenVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        if let userCertificate = acct.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }

        let ftVaultData = getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
            .resolveContractView(
                resourceType: nil,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            )! as! FungibleTokenMetadataViews.FTVaultData

        self.tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("Could not borrow reference to TokenA Vault")
    }

    execute {
        let incrementFiSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: vaultType,
            overflowSinks: {},
            uniqueID: nil
        )
        self.tokenVaultRef.deposit(from: <- incrementFiSource.withdrawAvailable(maxAmount: UFix64.max))
    }
}