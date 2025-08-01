import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"

transaction(pid: UInt64, vaultType: Type) {
    let lpTokenStakingPoolRewardsSource: IncrementFiStakingConnectors.StakingPoolRewardsSource
    let stakingPoolSink: IncrementFiStakingConnectors.StakingPoolSink

    prepare(acct: auth(Storage, Capabilities) &Account) {
        var userCertificateCap: Capability<&Staking.UserCertificate>? = nil
        if let userCertificate = acct.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }

        let stakingPoolCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)

        // Create the StakingPoolRewardsSource
        let stakingPoolRewardsSource = IncrementFiStakingConnectors.StakingPoolRewardsSource(
            userCertificate: userCertificateCap!,
            stakingPool: stakingPoolCap,
            poolID: pid,
            vaultType: vaultType,
            uniqueID: nil
        )

        // TODO: We need to insert the swapper here to convert rewards to LP tokens
        self.lpTokenStakingPoolRewardsSource = stakingPoolRewardsSource

        // Create the StakingPoolSink
        self.stakingPoolSink = IncrementFiStakingConnectors.StakingPoolSink(
            userCertificate: userCertificateCap!,
            stakingPool: stakingPoolCap,
            poolID: pid,
            uniqueID: nil
        )
    }

    execute {
        let tokenAVault <- self.lpTokenStakingPoolRewardsSource.withdrawAvailable(maxAmount: self.stakingPoolSink.minimumCapacity())
        self.stakingPoolSink.depositCapacity(from: &tokenAVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        assert(tokenAVault.balance == 0.0, message: "TokenA Vault should be empty after withdrawal")
        destroy tokenAVault
    }
}