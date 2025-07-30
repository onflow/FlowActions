import "IncrementFiStack"
import "Staking"
import "FungibleToken"
import "TokenA"

transaction(pid: UInt64) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let stakingPoolCap: Capability<&{Staking.PoolCollectionPublic}>
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        if let userCertificate = acct.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }

        self.stakingPoolCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)

        let incrementFiSink = IncrementFiStack.StakingPoolSink(
            userCertificate: self.userCertificateCap,
            stakingPool: self.stakingPoolCap,
            poolID: pid,
            uniqueID: nil
        )

        let tokenAVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &TokenA.Vault>(from: TokenA.VaultStoragePath)
            ?? panic("Could not borrow reference to TokenA Vault")
        incrementFiSink.depositCapacity(
            from: tokenAVaultRef,
        )
    }
}