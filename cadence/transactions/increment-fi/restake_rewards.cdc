import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "SwapStack"
import "DeFiActions"

transaction(pid: UInt64, vaultType: Type) {
    let userCertificateCap: Capability<&Staking.UserCertificate>

    prepare(acct: auth(Storage, Capabilities) &Account) {
        var userCertificateCap: Capability<&Staking.UserCertificate>? = nil
        if acct.storage.check<@Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }
    }
    
    execute {
        // Create the PoolRewardsSource
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: vaultType,
            uniqueID: nil
        )

        // Create the zapper to swap rewards to LP tokens
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: Type<@{FungibleToken.Vault}>(),
            token1Type: Type<@{FungibleToken.Vault}>(),
            stableMode: false,
            uniqueID: nil
        )

        // Create the SwapSource that uses the zapper to convert rewards to LP tokens
        let lpTokenPoolRewardsSource = SwapStack.SwapSource(
            swapper: zapper,
            source: poolRewardsSource,
            uniqueID: nil
        )

        // Create the sink where the rewards will be deposited 
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            staker: self.userCertificateCap.address,
            poolID: pid,
            uniqueID: nil
        )

        // Deposit the LP tokens into the pool sink
        let vault <- lpTokenPoolRewardsSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        assert(vault.balance == 0.0, message: "TokenA Vault should be empty after withdrawal")
        destroy vault
    }
}