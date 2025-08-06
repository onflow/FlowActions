# Connectors

## Vault Connectors

### VaultSource

## FungibleTokenStack Connectors

## VaultSource
**Purpose**: Withdraws tokens from FungibleToken vault with minimum balance protection.  
**Type**: `struct VaultSource : DeFiActions.Source`  
**Constructor**:
```cadence
FungibleTokenStack.VaultSource(
    min: UFix64?,                           // nil = no minimum (defaults to 0.0)
    withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `min: UFix64?` – Minimum balance to maintain in vault (nil = 0.0)
- `withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>` – Source vault capability
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**: Implements all [Source](./core-framework.md#source) interface methods

### VaultSink
**Purpose**: Deposits tokens into FungibleToken vault with capacity limits.  
**Type**: `struct VaultSink : DeFiActions.Sink`  
**Constructor**:
```cadence
FungibleTokenStack.VaultSink(
    max: UFix64?,
    depositVault: Capability<&{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `max: UFix64?` – Maximum deposit capacity (nil = unlimited)
- `depositVault: Capability<&{FungibleToken.Vault}>` – Target vault capability
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**: Implements all [Sink](./core-framework.md#sink) interface methods

### VaultSinkAndSource
**Purpose**: Combined deposit/withdraw operations on same vault.  
**Type**: `struct VaultSinkAndSource : DeFiActions.Sink, DeFiActions.Source`  
**Constructor**:
```cadence
FungibleTokenStack.VaultSinkAndSource(
    min: UFix64,
    max: UFix64?,
    vault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

## SwapStack Connectors

### SwapSource
**Purpose**: Combines Source + Swapper for automatic token conversion.  
**Type**: `struct SwapSource : DeFiActions.Source`  
**Constructor**:
```cadence
SwapStack.SwapSource(
    swapper: {DeFiActions.Swapper},
    source: {DeFiActions.Source},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `swapper: {DeFiActions.Swapper}` – Token conversion logic
- `source: {DeFiActions.Source}` – Token provider
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**: Implements all [Source](./core-framework.md#source) interface methods

### SwapSink
**Purpose**: Combines Swapper + Sink for automatic token conversion.  
**Type**: `struct SwapSink : DeFiActions.Sink`  
**Constructor**:
```cadence
SwapStack.SwapSink(
    swapper: {DeFiActions.Swapper},
    sink: {DeFiActions.Sink},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `swapper: {DeFiActions.Swapper}` – Token conversion logic
- `sink: {DeFiActions.Sink}` – Token acceptor
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**: Implements all [Sink](./core-framework.md#sink) interface methods

### MultiSwapper
**Purpose**: Routes token swaps through multiple DEXes for optimal pricing.  
**Type**: `struct MultiSwapper : DeFiActions.Swapper`  
**Constructor**:
```cadence
SwapStack.MultiSwapper(
    inVault: Type,                          // Input vault type
    outVault: Type,                         // Output vault type
    swappers: [{DeFiActions.Swapper}],      // Contained swapper components
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `inVault: Type` – Vault type accepted by all inner Swappers
- `outVault: Type` – Vault type returned by all inner Swappers
- `swappers: [{DeFiActions.Swapper}]` – List of Swapper components to route through
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

## IncrementFi Connectors

### PoolSink
**Purpose**: Stakes tokens in IncrementFi staking pools.  
**Type**: `struct PoolSink : Sink, IdentifiableStruct`  
**Constructor**:
```cadence
IncrementFiStakingConnectors.PoolSink(
    staker: Address,
    poolID: UInt64,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `staker: Address` – Address of account staking tokens
- `poolID: UInt64` – Staking pool identifier
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Side Effects**:
- Stakes tokens in specified pool
- Updates user's staking balance
- May trigger reward calculations

### PoolRewardsSource
**Purpose**: Claims staking rewards from IncrementFi pools.  
**Type**: `struct PoolRewardsSource : Source, IdentifiableStruct`  
**Constructor**:
```cadence
IncrementFiStakingConnectors.PoolRewardsSource(
    userCertificate: Capability<&Staking.UserCertificate>,
    poolID: UInt64,
    vaultType: Type,
    overflowSinks: {Type: {DeFiActions.Sink}},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `userCertificate: Capability<&Staking.UserCertificate>` – User's staking certificate
- `poolID: UInt64` – Staking pool identifier
- `vaultType: Type` – Primary reward token type
- `overflowSinks: {Type: {DeFiActions.Sink}}` – Handlers for additional reward types
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Side Effects**:
- Claims pending rewards from pool
- Routes additional rewards to overflow sinks
- Updates user's reward balances

### PoolSource
**Purpose**: Unstakes tokens from IncrementFi staking pools.  
**Type**: `struct PoolSource : Source, IdentifiableStruct`  
**Constructor**:
```cadence
IncrementFiStakingConnectors.PoolSource(
    userCertificate: Capability<&Staking.UserCertificate>,
    poolID: UInt64,
    vaultType: Type,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

## IncrementFi Pool Liquidity Connectors

### Zapper
**Purpose**: Converts single token to LP tokens via IncrementFi pools.  
**Type**: `struct Zapper : Swapper, IdentifiableStruct`  
**Constructor**:
```cadence
IncrementFiPoolLiquidityConnectors.Zapper(
    token0Type: Type,
    token1Type: Type,
    stableMode: Bool,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `token0Type: Type` – First token type in LP pair
- `token1Type: Type` – Second token type in LP pair
- `stableMode: Bool` – Pool type (true = stable, false = volatile)
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Side Effects**:
- Executes optimal swap to balance tokens
- Adds liquidity to pool
- Returns LP tokens

### UnZapper
**Purpose**: Converts LP tokens back to single token.  
**Type**: `struct UnZapper : Swapper, IdentifiableStruct`  
**Constructor**:
```cadence
IncrementFiPoolLiquidityConnectors.UnZapper(
    token0Type: Type,
    token1Type: Type,
    outputTokenType: Type,
    stableMode: Bool,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

## PriceOracle Connectors

### BandOracle PriceOracle
**Purpose**: Provides price data for tokens using BandOracle protocol.
**Type**: `struct PriceOracle : DeFiActions.PriceOracle`
**Constructor**:
```cadence
BandOracleConnectors.PriceOracle(
    unitOfAccount: Type,
    staleThreshold: UInt64?,
    feeSource: {DeFiActions.Source},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Parameters**:
- `unitOfAccount: Type` – Token type used as quote basis (e.g., Type<@FlowToken.Vault>())
- `staleThreshold: UInt64?` – Seconds before price data is stale
- `feeSource: {DeFiActions.Source}` – Source for paying oracle fee
- `uniqueID: DeFiActions.UniqueIdentifier?` – Optional operation ID

**Methods**: Implements `unitOfAccount(): Type` and `price(ofToken: Type): UFix64?`

## AutoBalancer Connectors

### AutoBalancerSource
**Purpose**: Withdraws tokens from a configured AutoBalancer.
**Type**: `struct AutoBalancerSource : Source`
**Constructor**:
```cadence
AutoBalancerSource(
    autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Methods**:
- `getSourceType(): Type` – Returns vault type of AutoBalancer
- `minimumAvailable(): UFix64` – Estimates withdrawable amount
- `withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}` – Withdraws tokens

### AutoBalancerSink
**Purpose**: Deposits tokens into a configured AutoBalancer.
**Type**: `struct AutoBalancerSink : Sink`
**Constructor**:
```cadence
AutoBalancerSink(
    autoBalancer: Capability<&AutoBalancer>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Methods**:
- `getSinkType(): Type` – Returns accepted vault type of AutoBalancer
- `minimumCapacity(): UFix64` – Estimates deposit capacity
- `depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})` – Deposits tokens

## EVM Connectors

### UniswapV2EVMSwapper
**Purpose**: Swaps tokens on UniswapV2 via Flow EVM.
**Type**: `struct UniswapV2EVMSwapper : DeFiActions.Swapper`
**Constructor**:
```cadence
UniswapV2EVMSwapper(
    routerAddress: EVM.EVMAddress,
    path: [EVM.EVMAddress],
    inVault: Type,
    outVault: Type,
    coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
**Methods**: Implements `inType()`, `outType()`, `quoteIn()`, `quoteOut()`, `swap()`, `swapBack()`
