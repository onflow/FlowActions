import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "SwapStack"
import "DeFiActions"

transaction(pid: UInt64, vaultType: Type) {
    let lpTokenPoolRewardsSource: {DeFiActions.Source}
    let poolSink: {DeFiActions.Sink}

    prepare(acct: auth(Storage, Capabilities) &Account) {
        var userCertificateCap: Capability<&Staking.UserCertificate>? = nil
        if let userCertificate = acct.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }
        
        // Create the PoolRewardsSource
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: userCertificateCap!,
            poolID: pid,
            vaultType: vaultType,
            uniqueID: nil
        )

        // TODO: We need to insert the swapper here to convert rewards to LP tokens
        let swapper = nil as AnyStruct as! {DeFiActions.Swapper}
        self.lpTokenPoolRewardsSource = SwapStack.SwapSource(
            swapper: swapper,
            source: poolRewardsSource,
            uniqueID: nil
        )

        // Create the PoolSink
        self.poolSink = IncrementFiStakingConnectors.PoolSink(
            userCertificate: userCertificateCap!,
            poolID: pid,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.lpTokenPoolRewardsSource.withdrawAvailable(maxAmount: self.poolSink.minimumCapacity())
        self.poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        assert(vault.balance == 0.0, message: "TokenA Vault should be empty after withdrawal")
        destroy vault
    }
}