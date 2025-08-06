# Type System

## Capability Types

### FungibleToken Capabilities
```cadence
Capability<&{FungibleToken.Vault}>                              // Read-only vault access
Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}> // Withdraw-enabled vault access
```

### Protocol-Specific Capabilities
```cadence
Capability<&Staking.UserCertificate>                           // IncrementFi staking certificate
Capability<&DeFiActions.AutoBalancer>                          // AutoBalancer resource access
Capability<&Staking.StakingPoolCollection>                     // Pool collection access
```

## Vault Types

### Token Type Definitions
```cadence
Type<@FlowToken.Vault>()                                       // FLOW token type
Type<@USDC.Vault>()                                           // USDC token type  
Type<@IncrementFiLP.Vault>()                                  // LP token type
```

### Vault Resource Types
```cadence
@{FungibleToken.Vault}                                        // Generic vault resource
@FlowToken.Vault                                              // Specific FLOW vault
@USDC.Vault                                                   // Specific USDC vault
```

## Function Signatures

### Source Interface Methods
```cadence
getSourceType(): Type
minimumAvailable(): UFix64
withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}
```

### Sink Interface Methods
```cadence
getSinkType(): Type
minimumCapacity(): UFix64
depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

### Swapper Interface Methods
```cadence
getFromType(): Type
getToType(): Type
swap(from: @{FungibleToken.Vault}): @{FungibleToken.Vault}
```

## Account Entitlements

### Required Entitlements
```cadence
auth(BorrowValue) &Account                                     // Read storage, borrow capabilities
auth(SaveValue) &Account                                       // Save resources to storage  
auth(IssueStorageCapabilityController) &Account               // Create storage capabilities
auth(PublishCapability) &Account                              // Publish public capabilities
```

### Combined Entitlements
```cadence
auth(BorrowValue, SaveValue) &Account                         // Most common combination
auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account  // Full permissions
```

## Storage Paths

### Standard Storage Paths
```cadence
/storage/flowTokenVault                                        // FlowToken vault storage
/storage/usdcVault                                            // USDC vault storage
/storage/stakingCertificate                                   // Staking certificate storage
/storage/autoBalancer                                         // AutoBalancer storage
```

### Public Paths
```cadence
/public/flowTokenReceiver                                     // FlowToken receiver capability
/public/flowTokenBalance                                      // FlowToken balance capability
/public/stakingInfo                                          // Staking information capability
```

## Parameter Types

### Transaction Parameter Types
```cadence
Address                                                       // Account addresses
UInt64                                                        // Pool IDs, amounts
UFix64                                                        // Token amounts, percentages
Type                                                          // Token types
String                                                        // Type identifiers
Bool                                                          // Flags, options
```

### Complex Parameter Types
```cadence
{Type: Capability<&{FungibleToken.Vault}>}                   // Vault capability mapping
{Type: {DeFiActions.Sink}}                                   // Sink mapping for overflow handling
[Address]                                                     // Address arrays
StoragePath                                                   // Storage location
PublicPath                                                    // Public capability location
```

## Resource Handling Rules

### Resource Creation
```cadence
let vault <- source.withdrawAvailable(maxAmount: amount)       // Create vault resource
let emptyVault <- DeFiActionsUtils.getEmptyVault(tokenType)   // Create empty vault
```

### Resource Transfer
```cadence
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

### Resource Validation
```cadence
assert(vault.balance == 0.0, message: "Transfer incomplete")   // Verify complete transfer
destroy vault                                                  // Destroy empty vault
```

### Resource Safety Pattern
```cadence
let vault <- source.withdrawAvailable(maxAmount: amount)
defer destroy vault  // Automatic cleanup on panic
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(vault.balance == 0.0, message: "Transfer incomplete")
```
