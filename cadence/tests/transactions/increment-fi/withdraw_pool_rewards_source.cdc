import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(pid: UInt64) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let tokenVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        if let userCertificate = acct.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }

        let pool = IncrementFiStakingConnectors.borrowPool(poolID: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")

        let rewardTokenType = CompositeType(pool.getPoolInfo().rewardsInfo.keys[0].concat(".Vault"))!
        let ftVaultData = getAccount(rewardTokenType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: rewardTokenType.contractName!)!
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
            uniqueID: nil
        )
        self.tokenVaultRef.deposit(from: <- incrementFiSource.withdrawAvailable(maxAmount: UFix64.max))
    }
}