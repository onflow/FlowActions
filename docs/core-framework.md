# Core Framework

## Interfaces

### Source
**Purpose**: Provides tokens from various sources.  
**Type**: `struct interface Source : IdentifiableStruct`  
**Methods**:
- `getSourceType(): Type` – Returns vault type this source provides
- `minimumAvailable(): UFix64` – Estimates available token amount  
- `withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}` – Withdraws tokens up to maxAmount

### Sink  
**Purpose**: Accepts tokens for deposit into various destinations.  
**Type**: `struct interface Sink : IdentifiableStruct`  
**Methods**:
- `getSinkType(): Type` – Returns vault type this sink accepts
- `minimumCapacity(): UFix64` – Estimates available deposit capacity
- `depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})` – Deposits tokens from vault

### Swapper
**Purpose**: Converts tokens from one type to another.
**Type**: `struct interface Swapper : IdentifiableStruct`
**Methods**:
- `inType(): Type` – Returns input vault type
- `outType(): Type` – Returns output vault type
- `quoteIn(forDesired: UFix64, reverse: Bool): {Quote}` – Estimates input amount needed
- `quoteOut(forProvided: UFix64, reverse: Bool): {Quote}` – Estimates output amount returned
- `swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault}` – Executes swap from inType to outType
- `swapBack(quote: {Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault}` – Executes swap from outType back to inType

### Quote
**Purpose**: Provides swap estimation data.
**Type**: `struct interface Quote`
**Properties**:
- `inType: Type` – Pre-swap vault type
- `outType: Type` – Post-swap vault type
- `inAmount: UFix64` – Amount of inType
- `outAmount: UFix64` – Amount of outType

### PriceOracle
**Purpose**: Provides price data for assets.
**Type**: `struct interface PriceOracle : IdentifiableStruct`
**Methods**:
- `unitOfAccount(): Type` – Returns the price basis asset type
- `price(ofToken: Type): UFix64?` – Returns latest price or `nil` if unavailable

### Flasher
**Purpose**: Issues flash loans with atomic repayment.
**Type**: `struct interface Flasher : IdentifiableStruct`
**Methods**:
- `borrowType(): Type` – Returns asset type issued in loan
- `calculateFee(loanAmount: UFix64): UFix64` – Returns fee amount for loan
- `flashLoan(amount: UFix64, data: AnyStruct?, callback: fun(UFix64, @{FungibleToken.Vault}, AnyStruct?): @{FungibleToken.Vault})` – Executes flash loan

### SwapSource
**Purpose**: Combines Source + Swapper for automatic token conversion.  
**Type**: `struct SwapSource : Source, IdentifiableStruct`  
**Properties**:
- `swapper: {Swapper}` – Token conversion component
- `source: {Source}` – Token provider component
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**:
- `getSourceType(): Type` – Returns swapper's output token type
- `minimumAvailable(): UFix64` – Estimates available tokens after swap
- `withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}` – Withdraws from source, swaps, returns result

### SwapSink
**Purpose**: Combines Swapper + Sink for automatic token conversion.  
**Type**: `struct SwapSink : Sink, IdentifiableStruct`  
**Properties**:
- `swapper: {Swapper}` – Token conversion component
- `sink: {Sink}` – Token acceptor component  
- `uniqueID: DeFiActions.UniqueIdentifier?` – Operation tracking ID

**Methods**:
- `getSinkType(): Type` – Returns swapper's input token type
- `minimumCapacity(): UFix64` – Estimates capacity for input tokens
- `depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})` – Swaps tokens then deposits to sink

### AutoBalancer
**Purpose**: Maintains a wrapped vault resource within specified balance thresholds and performs automated rebalancing.
**Type**: `resource AutoBalancer : IdentifiableResource, FungibleToken.Receiver, FungibleToken.Provider, ViewResolver.Resolver, Burner.Burnable`
**Constructor**:
```cadence
init(
    lower: UFix64,                // Lower rebalance threshold (relative ratio)
    upper: UFix64,                // Upper rebalance threshold (relative ratio)
    oracle: {PriceOracle},        // Price oracle component
    vaultType: Type,              // Token vault type managed
    outSink: {Sink}?,             // Optional sink for excess value
    inSource: {Source}?,          // Optional source for value shortfall
    uniqueID: UniqueIdentifier?
)
```
**Properties**:
- `rebalanceThresholds(): [UFix64; 2]` – [lower, upper]
- `valueOfDeposits(): UFix64` – Historical value of deposits/withdrawals
- `vaultBalance(): UFix64` – Current wrapped vault balance
- `vaultType(): Type` – Type of the wrapped vault
- `unitOfAccount(): Type` – Price basis asset type from oracle
- `currentValue(): UFix64?` – Current vault value denominated in unitOfAccount

**Methods**:
- `getComponentInfo(): ComponentInfo`
- `createBalancerSink(): {Sink}?`
- `createBalancerSource(): {Source}?`
- `setSink(sink: {Sink}?, updateSinkID: Bool)`
- `setSource(source: {Source}?, updateSourceID: Bool)`

**Events**:
- `CreatedAutoBalancer(lowerThreshold: UFix64, upperThreshold: UFix64, vaultType: String, vaultUUID: UInt64, uuid: UInt64, uniqueID: UInt64?)`
- `Rebalanced(amount: UFix64, value: UFix64, unitOfAccount: String, isSurplus: Bool, vaultType: String, vaultUUID: UInt64, balancerUUID: UInt64, address: Address?, uuid: UInt64, uniqueID: UInt64?)`
- `ResourceDestroyed(uuid: UInt64, vaultType: String, balance: UFix64?, uniqueID: UInt64?)`

## Base Types

### UniqueIdentifier
**Purpose**: Identifies component operation stacks across connectors via interface events.
**Type**: `struct UniqueIdentifier`
**Constructor**: Created via `DeFiActions.createUniqueIdentifier()` in code; includes `id: UInt64` and `authCap`.

### IdentifiableStruct
**Purpose**: Base interface for all struct-based connectors providing a `uniqueID` and introspection.
**Type**: `struct interface IdentifiableStruct`
**Methods**:
- `id(): UInt64?` – Returns numeric ID
- `getComponentInfo(): ComponentInfo` – Returns this component’s info
- `copyID(): UniqueIdentifier?` – Copies the `uniqueID`
- `setID(_ id: UniqueIdentifier?)` – Sets the `uniqueID`

### IdentifiableResource
**Purpose**: Base interface for all resource-based connectors providing a `uniqueID` and introspection.
**Type**: `resource interface IdentifiableResource`
**Methods**:
- `id(): UInt64?`
- `getComponentInfo(): ComponentInfo`
- `copyID(): UniqueIdentifier?`
- `setID(_ id: UniqueIdentifier?)`

### ComponentInfo
**Purpose**: Struct containing information about a component and its inner components.
**Type**: `struct ComponentInfo`
**Fields**:
- `type: Type`
- `id: UInt64?`
- `innerComponents: [ComponentInfo]`

## Composition Rules

### Basic Chain
```
Source -> Sink
```

### Swap-Enhanced Chain  
```
SwapSource(swapper, source) -> Sink
Source -> SwapSink(swapper, sink)
```

### Multi-Level Composition
```
SwapSource(swapper2, SwapSource(swapper1, source)) -> Sink
```

### AutoBalancer Integration
```
AutoBalancerSource -> Sink
Source -> AutoBalancerSink
```

## Additional Primitives
