# Workflow Patterns

## Pattern 1: Restaking Workflow
**Purpose**: Claim staking rewards, convert to LP tokens, re-stake automatically  
**Components**: [`PoolRewardsSource`](./connectors.md#poolrewardssource) → [`SwapSource`](./connectors.md#swapsource) → [`PoolSink`](./connectors.md#poolsink)  
**Complexity**: Medium  
**File**: [`restaking-workflow.md`](./workflows/restaking-workflow.md)

### Steps:
1. **Claim Rewards**: Use `PoolRewardsSource` to extract staking rewards
2. **Convert to LP**: Use `Zapper` inside `SwapSource` to convert single token to LP pair
3. **Re-stake**: Use `PoolSink` to stake LP tokens back into pool

### Component Chain:
```
PoolRewardsSource -> SwapSource(Zapper) -> PoolSink
```

### Expected Inputs:
- `pid: UInt64` – Pool identifier
- `poolCollectionAddress: Address` – Pool collection address
- `rewardTokenType: Type` – Type of reward tokens to claim
- `token0Type: Type` – First token in LP pair
- `token1Type: Type` – Second token in LP pair
- `slippageTolerance: UFix64` – Acceptable slippage (e.g., 0.01 = 1%)

## Pattern 2: AutoBalancer Setup
**Purpose**: Create automated token rebalancing system  
**Components**: [`PriceOracle`] → [`AutoBalancer`](./core-framework.md#autobalancer) → Storage + PublicCapability  
**Complexity**: Low  
**File**: [`autobalancer-workflow.md`](./workflows/autobalancer-workflow.md)

### Steps:
1. **Create Oracle**: Initialize price oracle component
2. **Create AutoBalancer**: Configure thresholds and token type
3. **Save Resource**: Store in account storage with public capability

### Component Chain:
```
PriceOracle -> AutoBalancer -> Storage + PublicCapability
```

### Expected Inputs:
- `vaultType: String` – Token type identifier
- `lowerThreshold: UFix64` – Lower rebalance threshold (e.g., 0.9)
- `upperThreshold: UFix64` – Upper rebalance threshold (e.g., 1.1)
- `storagePath: StoragePath` – Storage location
- `publicPath: PublicPath` – Public capability path

## Pattern 3: Multi-Protocol Chain
**Purpose**: Chain operations across multiple DeFi protocols  
**Components**: [`VaultSource`](./connectors.md#vaultsource) → [`SwapSource`](./connectors.md#swapsource) → [`PoolSink`](./connectors.md#poolsink)  
**Complexity**: High

### Steps:
1. **Source Tokens**: Withdraw from user vault with minimum balance protection
2. **Protocol Swap**: Convert tokens via external protocol swapper
3. **Stake Result**: Deposit converted tokens to different protocol

### Component Chain:
```
VaultSource -> SwapSource(ProtocolSwapper) -> ProtocolSink
```

### Expected Inputs:
- `userAddress: Address` – User's address
- `poolId: UInt64` – Target staking pool
- `minBalance: UFix64` – Minimum vault balance to maintain
- `sourceStoragePath: StoragePath` – Source vault storage path

## Pattern 4: Vault Transfer
**Purpose**: Move tokens between vaults with capacity limits  
**Components**: [`VaultSource`](./connectors.md#vaultsource) → [`VaultSink`](./connectors.md#vaultsink)  
**Complexity**: Low

### Steps:
1. **Create Source**: Configure source vault with minimum balance
2. **Create Sink**: Configure target vault with capacity limit
3. **Execute Transfer**: Move tokens respecting limits

### Component Chain:
```
VaultSource -> VaultSink
```

### Expected Inputs:
- `sourceStoragePath: StoragePath` – Source vault location
- `targetVaultCap: Capability<&{FungibleToken.Vault}>` – Target vault capability
- `amount: UFix64` – Transfer amount
- `maxCapacity: UFix64` – Target capacity limit

## Pattern 5: Overflow Reward Handling
**Purpose**: Claim multiple reward types with overflow management  
**Components**: [`PoolRewardsSource`](./connectors.md#poolrewardssource) with overflow sinks  
**Complexity**: Medium

### Steps:
1. **Configure Overflow Sinks**: Map additional reward types to destinations
2. **Create Reward Source**: Configure with primary + overflow handling
3. **Claim Rewards**: Extract all reward types simultaneously

### Component Chain:
```
PoolRewardsSource(overflowSinks: {Type: VaultSink}) -> Multiple Destinations
```

### Expected Inputs:
- `pid: UInt64` – Pool identifier
- `poolCollectionAddress: Address` – Pool collection address
- `primaryRewardType: Type` – Primary reward token type
- `overflowVaultCaps: {Type: Capability<&{FungibleToken.Vault}>}` – Additional reward handlers
