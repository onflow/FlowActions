# Restaking Workflow

**Purpose**: Claim staking rewards, convert to LP tokens, re-stake automatically  
**Components**: PoolRewardsSource → SwapSource(Zapper) → PoolSink  
**Related**: [Pattern 1](../patterns.md#pattern-1-restaking-workflow)

## Required Imports
```cadence
import "FungibleToken"
import "DeFiActions"
import "SwapStack"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "Staking"
```

## Component Flow
```
1. PoolRewardsSource    → Claims staking rewards
2. Zapper               → Converts single token to LP tokens
3. SwapSource           → Combines PoolRewardsSource + Zapper
4. PoolSink             → Stakes LP tokens back into pool
```

## Transaction Implementation
```cadence
transaction(
    pid: UInt64,                    // Pool identifier
    poolCollectionAddress: Address, // Pool collection address parameter
    rewardTokenType: Type,         // Reward token type (e.g., Type<@FlowToken.Vault>())
    token0Type: Type,              // LP token 0 type
    token1Type: Type,              // LP token 1 type
    slippageTolerance: UFix64      // Acceptable slippage (e.g., 0.01 = 1%)
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let startingStake: UFix64
    
    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        // Get user certificate capability
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        
        // Save starting stake for post-condition validation
        let pool = getAccount(poolCollectionAddress).capabilities
            .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)!
            .getPool(pid: pid)
        
        self.startingStake = pool.getUserInfo(address: acct.address)!.stakingAmount
    }
    
    execute {
        // Step 1: Create reward source
        let rewardSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: rewardTokenType,
            overflowSinks: {},
            uniqueID: nil
        )
        
        // Step 2: Create LP zapper
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: token0Type,
            token1Type: token1Type,
            stableMode: false,
            uniqueID: nil
        )
        
        // Step 3: Combine reward source + zapper
        let lpSource = SwapStack.SwapSource(
            swapper: zapper,
            source: rewardSource,
            uniqueID: nil
        )
        
        // Step 4: Create staking sink
        let stakingSink = IncrementFiStakingConnectors.PoolSink(
            staker: self.userCertificateCap.address,
            poolID: pid,
            uniqueID: nil
        )
        
        // Step 5: Execute transfer
        let vault <- lpSource.withdrawAvailable(maxAmount: UFix64.max)
        stakingSink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        
        // Step 6: Validate complete transfer
        assert(vault.balance == 0.0, message: "Transfer incomplete")
        destroy vault
    }
    
    pre {
        pid > 0: "Pool ID must be positive"
    }
    
    post {
        getAccount(poolCollectionAddress).capabilities
            .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)!
            .getPool(pid: pid)
            .getUserInfo(address: self.userCertificateCap.address)!
            .stakingAmount >= self.startingStake * (1.0 - slippageTolerance):
            "Restake amount below expected"
    }
}
```

## Component Details

### PoolRewardsSource
- **Purpose**: Claims pending staking rewards from specified pool
- **Input**: User certificate, pool ID, reward token type
- **Output**: Vault containing claimed rewards
- **Side Effects**: Updates user's reward balance in pool

### Zapper
- **Purpose**: Converts single reward token into LP token pair
- **Input**: Single token vault (from rewards)
- **Output**: LP token vault
- **Side Effects**: Executes optimal swap + liquidity provision

### PoolSink
- **Purpose**: Stakes LP tokens back into the same or different pool
- **Input**: LP token vault
- **Output**: Updated staking position
- **Side Effects**: Increases user's staking balance

## Usage Examples

### Basic Restaking
```cadence
// Restake FLOW rewards as FLOW/USDC LP tokens
// Pool 42, 1% slippage tolerance
restakeRewards(
    pid: 42,
    poolCollectionAddress: 0x1234567890abcdef,
    rewardTokenType: Type<@FlowToken.Vault>(),
    token0Type: Type<@FlowToken.Vault>(),
    token1Type: Type<@USDC.Vault>(),
    slippageTolerance: 0.01
)
```

### Cross-Pool Restaking
```cadence
// Claim rewards from pool 42, stake LP tokens in pool 24
// (Modify PoolSink poolID parameter)
```

## Error Handling

### Common Failures
- **No rewards available**: PoolRewardsSource.minimumAvailable() returns 0
- **Insufficient liquidity**: Zapper cannot create LP tokens due to pool constraints
- **Pool inactive**: Target staking pool is not accepting new stakes
- **Slippage exceeded**: Final stake amount below tolerance threshold

### Validation Checks
```cadence
// Pre-flight validation
let availableRewards = rewardSource.minimumAvailable()
assert(availableRewards > 0.0, message: "No rewards available to claim")

let stakingCapacity = stakingSink.minimumCapacity()
assert(stakingCapacity > 0.0, message: "Pool not accepting new stakes")
```
