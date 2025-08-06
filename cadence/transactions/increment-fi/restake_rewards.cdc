import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "SwapStack"
import "DeFiActions"
import "SwapConfig"

/// Restakes earned staking rewards by converting them to LP tokens and staking them back into the same pool.
/// This transaction automates the compound staking process by:
/// 1. Harvesting reward tokens from a staking pool
/// 2. Converting the reward tokens to LP tokens via a zapper (using the reward token + pair token)
/// 3. Restaking the LP tokens back into the original pool
///
/// @param pid: The pool ID of the staking pool to harvest rewards from and restake into
/// @param rewardTokenType: The type of the reward token that will be harvested from the staking pool
/// @param pairTokenType: The type of the other token component needed to form the LP pair with the reward token
/// @param stakingCollectionAddress: The address of the account holding the staking pool collection
/// @param minimumRestakedAmount: The minimum increase in staked amount expected (protects against excessive slippage)
///
transaction(
    pid: UInt64,
    rewardTokenType: Type,
    pairTokenType: Type,
    stakingCollectionAddress: Address,
    minimumRestakedAmount: UFix64,
) {
    // Capability to the user's staking identity certificate
    let userCertificateCap: Capability<&Staking.UserCertificate>
    // Reference to the staking pool's public interface
    let pool: &{Staking.PoolPublic}
    // The user's initial staked amount before the restaking operation
    let startingStake: UFix64

    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        // Get a reference to the staking pool collection and retrieve the specific pool
        self.pool = getAccount(stakingCollectionAddress).capabilities.borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)?.getPool(pid: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")
        
        // Record the user's current staked amount for validation purposes
        self.startingStake = self.pool.getUserInfo(address: acct.address)?.stakingAmount ?? panic("No user info found for address \(acct.address)")
        
        // Issue a capability to the user's staking certificate
        self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
    }

    execute {
        // Create the PoolRewardsSource to harvest rewards from the staking pool
        // This source will withdraw available rewards from the specified pool using the user's certificate
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: rewardTokenType,
            overflowSinks: {},
            uniqueID: nil
        )

        // Create the zapper to convert reward tokens to LP tokens
        // The zapper takes the reward token and the pair token to create LP tokens
        // that can be staked back into the pool for compound returns
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: rewardTokenType,
            token1Type: pairTokenType,
            stableMode: false,
            uniqueID: nil
        )

        // Create the SwapSource that uses the zapper to convert reward tokens to LP tokens
        // This combines the reward harvesting with the LP token conversion process
        let lpTokenPoolRewardsSource = SwapStack.SwapSource(
            swapper: zapper,
            source: poolRewardsSource,
            uniqueID: nil
        )

        // Create the sink where the converted LP tokens will be deposited back into the staking pool
        // This completes the restaking loop by depositing the new LP tokens for the same user
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            staker: self.userCertificateCap.address,
            poolID: pid,
            uniqueID: nil
        )

        // Execute the restaking process:
        // 1. Withdraw available LP tokens from the rewards source (up to the pool sink's capacity)
        // 2. Deposit the LP tokens into the pool sink to complete the restaking
        let vault <- lpTokenPoolRewardsSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        // Ensure all tokens were properly deposited (vault should be empty)
        assert(vault.balance == 0.0, message: "Vault should be empty after withdrawal - restaking may have failed")
        destroy vault
    }

    post {
        // Verify that the increase in staked amount meets the user-specified minimum to guard against excessive slippage
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount >= self.startingStake + minimumRestakedAmount:
            "Restaking failed: restaked amount of \(self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount - self.startingStake) is below the minimum restaked amount of \(minimumRestakedAmount)"
    }
}