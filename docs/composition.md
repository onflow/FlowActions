# Component Composition

## Basic Composition Rules

### Source → Sink (Direct)
```cadence
let source = ComponentSource(...)
let sink = ComponentSink(...)

let vault <- source.withdrawAvailable(maxAmount: amount)
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(vault.balance == 0.0, message: "Transfer incomplete")
destroy vault
```

### Source → Swapper → Sink (Manual)
```cadence
let source = ComponentSource(...)
let swapper = ComponentSwapper(...)
let sink = ComponentSink(...)

let inputVault <- source.withdrawAvailable(maxAmount: amount)
let outputVault <- swapper.swap(from: <-inputVault)
sink.depositCapacity(from: &outputVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(outputVault.balance == 0.0, message: "Transfer incomplete")
destroy outputVault
```

## Composite Components

### SwapSource (Source + Swapper)
```cadence
let swapSource = SwapStack.SwapSource(
    swapper: tokenSwapper,    // {Swapper}
    source: basicSource,      // {Source}
    uniqueID: operationID     // DeFiActions.UniqueIdentifier?
)

// Usage: Acts as enhanced Source
let vault <- swapSource.withdrawAvailable(maxAmount: amount)
```

### SwapSink (Swapper + Sink)
```cadence
let swapSink = SwapStack.SwapSink(
    swapper: tokenSwapper,    // {Swapper}
    sink: basicSink,          // {Sink}
    uniqueID: operationID     // DeFiActions.UniqueIdentifier?
)

// Usage: Acts as enhanced Sink
swapSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## Multi-Level Composition

### Nested SwapSource
```cadence
let complexSource = SwapStack.SwapSource(
    swapper: secondSwapper,                    // Final conversion
    source: SwapStack.SwapSource(              // Nested SwapSource
        swapper: firstSwapper,                 // Initial conversion
        source: FungibleTokenStack.VaultSource(...),  // Base source
        uniqueID: operationID
    ),
    uniqueID: operationID
)
```

### Chain: Vault → Swap → Swap → Stake
```cadence
// Step 1: Base vault source
let vaultSource = FungibleTokenStack.VaultSource(
    min: 10.0,
    withdrawVault: userVaultCap,
    uniqueID: operationID
)

// Step 2: First swap (Token A → Token B)
let firstSwapSource = SwapStack.SwapSource(
    swapper: tokenAToTokenBSwapper,
    source: vaultSource,
    uniqueID: operationID
)

// Step 3: Second swap (Token B → LP Tokens)
let lpSwapSource = SwapStack.SwapSource(
    swapper: tokenBToLPSwapper,
    source: firstSwapSource,
    uniqueID: operationID
)

// Step 4: Staking sink
let stakingSink = IncrementFiStakingConnectors.PoolSink(
    staker: userAddress,
    poolID: poolId,
    uniqueID: operationID
)

// Execute complete chain
let vault <- lpSwapSource.withdrawAvailable(maxAmount: amount)
stakingSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## AutoBalancer Integration

### AutoBalancer as Source
```cadence
let autoBalancerSource = DeFiActions.AutoBalancerSource(
    autoBalancer: autoBalancerCap,  // Capability<&DeFiActions.AutoBalancer>
    uniqueID: operationID
)

// Can be used in any Source position
let vault <- autoBalancerSource.withdrawAvailable(maxAmount: amount)
```

### AutoBalancer as Sink
```cadence
let autoBalancerSink = DeFiActions.AutoBalancerSink(
    autoBalancer: autoBalancerCap,  // Capability<&DeFiActions.AutoBalancer>
    uniqueID: operationID
)

// Can be used in any Sink position
autoBalancerSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

### AutoBalancer in Chain
```cadence
// Complex chain with AutoBalancer
let rewardSource = PoolRewardsSource(...)
let swapSource = SwapStack.SwapSource(swapper: zapper, source: rewardSource, uniqueID: nil)
let autoBalancerSink = DeFiActions.AutoBalancerSink(autoBalancer: balancerCap, uniqueID: nil)

let vault <- swapSource.withdrawAvailable(maxAmount: UFix64.max)
autoBalancerSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## Composition Best Practices

### Keep Chains Simple
```cadence
// ✅ Good: Clear, debuggable chain
VaultSource -> SwapSource(Zapper) -> PoolSink

// ❌ Too complex: Hard to debug
VaultSource -> SwapSource(SwapSink(SwapSource(...))) -> ComplexSink
```

### Use Consistent UniqueIDs
```cadence
let operationID = DeFiActions.createUniqueIdentifier()

// All components in same operation should use same ID
let source = ComponentSource(..., uniqueID: operationID)
let swapper = ComponentSwapper(..., uniqueID: operationID)
let sink = ComponentSink(..., uniqueID: operationID)
```

### Validate Component Compatibility
```cadence
// Ensure type compatibility
assert(source.getSourceType() == swapper.getFromType(), message: "Source/Swapper type mismatch")
assert(swapper.getToType() == sink.getSinkType(), message: "Swapper/Sink type mismatch")
```

### Check Capacity Before Execution
```cadence
let available = source.minimumAvailable()
let capacity = sink.minimumCapacity()

assert(available > 0.0, message: "No tokens available")
assert(capacity >= available, message: "Insufficient sink capacity")
```
