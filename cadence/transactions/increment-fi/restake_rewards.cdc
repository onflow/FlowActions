import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "SwapConnectors"
import "DeFiActions"
import "SwapInterfaces"
import "SwapConfig"

/// Restakes earned staking rewards by converting them to LP tokens and staking them back into the same pool.
/// This transaction automates the compound staking process by:
/// 1. Harvesting reward tokens from a staking pool
/// 2. Converting the reward tokens to LP tokens via a zapper (using the reward token + pair token)
/// 3. Restaking the LP tokens back into the original pool
///
/// @param pid: The pool ID of the staking pool to harvest rewards from and restake into
///
transaction(
    pid: UInt64,
) {
    // Address of the user
    let staker: Address
    // Unique ID for the restaking operation
    let uniqueID: DeFiActions.UniqueIdentifier
    // Reference to the staking pool's public interface
    let pool: &{Staking.PoolPublic}
    // The user's initial staked amount before the restaking operation
    let startingStake: UFix64
    // The source that converts reward tokens to LP tokens
    let tokenSource: SwapConnectors.SwapSource
    // Expected amount of LP tokens to be restaked
    let expectedStakeIncrease: UFix64

    prepare(acct: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        self.staker = acct.address
        self.uniqueID = DeFiActions.createUniqueIdentifier()
        self.pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")
        self.startingStake = self.pool.getUserInfo(address: acct.address)?.stakingAmount ?? panic("No user info found for address \(acct.address)")
        
        // Issue a capability to the user's staking certificate
        let userCertificateCap = acct
            .capabilities
            .storage
            .issue<&Staking.UserCertificate>(
                Staking.UserCertificateStoragePath
            )
        
        let pair = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
        if pair == nil {
            panic("Pair with ID \(pid) not found or not accessible")
        }

        // Create the PoolRewardsSource to harvest rewards from the staking pool
        // This source will withdraw available rewards from the specified pool using the user's certificate
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: userCertificateCap,
            pid: pid,
            uniqueID: self.uniqueID
        )

        // Create the zapper to convert reward tokens to LP tokens
        // The zapper takes the reward token and the pair token to create LP tokens
        // that can be staked back into the pool for compound returns
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair!.getPairInfoStruct().token0Key),
            token1Type: IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair!.getPairInfoStruct().token1Key),
            stableMode: pair!.getPairInfoStruct().isStableswap,
            uniqueID: self.uniqueID
        )

        // Create the SwapSource that uses the zapper to convert reward tokens to LP tokens
        // This combines the reward harvesting with the LP token conversion process
        self.tokenSource = SwapConnectors.SwapSource(
            swapper: zapper,
            source: poolRewardsSource,
            uniqueID: self.uniqueID
        )
        
        // Get the expected amount of LP tokens to be restaked
        self.expectedStakeIncrease = zapper.quoteOut(
            forProvided: poolRewardsSource.minimumAvailable(),
            reverse: false
        ).outAmount
    }

    post {
        // Verify that the restaked tokens is at least the expected amount
        self.pool.getUserInfo(address: self.staker)!.stakingAmount >= self.startingStake + self.expectedStakeIncrease:
            "Restaking failed: restaked amount of \(self.pool.getUserInfo(address: self.staker)!.stakingAmount - self.startingStake) is below the expected restaked amount of \(self.expectedStakeIncrease)"
    }

    execute {
        // Create the sink where the converted LP tokens will be deposited back into the staking pool
        // This completes the restaking loop by depositing the new LP tokens for the same user
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: self.staker,
            uniqueID: self.uniqueID
        )

        // Execute the restaking process:
        // 1. Withdraw available LP tokens from the rewards source (up to the pool sink's capacity)
        // 2. Deposit the LP tokens into the pool sink to complete the restaking
        let vault <- self.tokenSource.withdrawAvailable(maxAmount: UFix64.max)
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        // Ensure all tokens were properly deposited (vault should be empty)
        assert(vault.balance == 0.0, message: "Vault should be empty after withdrawal - restaking may have failed")
        destroy vault
    }
}