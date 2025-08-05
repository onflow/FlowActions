import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "SwapStack"
import "DeFiActions"
import "SwapConfig"

transaction(
    pid: UInt64,
    vaultType: Type,
    expectedAmount: UFix64,
    slippageTolerance: UFix64,
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let pool: &{Staking.PoolPublic}
    let startingStake: UFix64

    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        self.pool = getAccount(Type<Staking>().address!).capabilities.borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)?.getPool(pid: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")
        self.startingStake = self.pool.getUserInfo(address: acct.address)?.stakingAmount ?? panic("No user info found for address \(acct.address)")
        self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
    }

    execute {
        // Create the PoolRewardsSource
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: vaultType,
            overflowSinks: {},
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

    post {
        // Verify that the user's staked amount has increased within the allowed slippage tolerance
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount >= self.startingStake * (1.0 - slippageTolerance)
    }
}