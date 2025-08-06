# Safety Rules

## Critical Import Rules

### Import Syntax (BLOCKING)
**Enforcement**: Compile-time  
**Criticality**: BLOCKING

#### Correct Format
```cadence
import "FungibleToken"
import "DeFiActions" 
import "FungibleTokenStack"
import "SwapStack"
import "IncrementFiStakingConnectors"
```

#### Incorrect Format (WILL FAIL)
```cadence
import FungibleToken from 0x123456789abcdef0    // COMPILE ERROR
import DeFiActions from 0x123456789abcdef0      // COMPILE ERROR
```

## Critical Pre/Post-Condition Rules

### Single Expression Rule (BLOCKING)
**Enforcement**: Compile-time  
**Criticality**: BLOCKING

Pre and post-conditions MUST be single boolean expressions.

#### Correct Format
```cadence
pre {
    amount > 0.0: "Amount must be positive"
}

post {
    vault.balance >= expectedMinimum: "Result below minimum"
}
```

#### Incorrect Format (WILL FAIL)
```cadence
pre {
    let isValid = amount > 0.0  // MULTIPLE STATEMENTS NOT ALLOWED
    isValid: "Amount must be positive"
}

post {
    let newBalance = vault.balance  // VARIABLE DECLARATION NOT ALLOWED
    newBalance >= expectedMinimum: "Below minimum"
}
```

#### Complex Expression (CORRECT)
```cadence
post {
    getAccount(self.poolAddress).capabilities
        .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)!
        .getPool(pid: self.poolId)
        .getUserInfo(address: self.userAddress)!
        .stakingAmount >= self.startingStake * (1.0 - self.slippageTolerance):
        "Restake amount below expected"
}
```

## High Priority Safety Rules

### Address Parameter Passing (HIGH)
**Enforcement**: Runtime Safety  
**Criticality**: HIGH

#### Correct Pattern
```cadence
transaction(poolCollectionAddress: Address) {
    let pool = getAccount(poolCollectionAddress).capabilities
        .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
}
```

#### Incorrect Pattern (SECURITY RISK)
```cadence
transaction() {
    let pool = getAccount(Type<Staking>().address).capabilities  // HARDCODED ADDRESS
        .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
}
```

### Resource Handling (HIGH)
**Enforcement**: Runtime Safety  
**Criticality**: HIGH

#### Complete Transfer Validation
```cadence
// ✅ Correct: Verify complete transfer
let vault <- source.withdrawAvailable(maxAmount: amount)
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(vault.balance == 0.0, message: "Transfer incomplete: ".concat(vault.balance.toString()))
destroy vault
```

#### Incomplete Transfer (RESOURCE LOSS)
```cadence
// ❌ Wrong: Don't verify complete transfer
let vault <- source.withdrawAvailable(maxAmount: amount)
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
destroy vault  // MAY DESTROY UNDEPOSITED TOKENS
```

### Capability Validation (HIGH)
**Enforcement**: Runtime Safety  
**Criticality**: HIGH

#### Defensive Capability Access
```cadence
// ✅ Correct: Validate before use
let pool = poolCap.borrow() ?? panic("Could not access pool \(poolId)")
assert(pool.isActive(), message: "Pool \(poolId) is not currently active")
```

#### Unsafe Capability Access
```cadence
// ❌ Wrong: Force unwrap without validation
let pool = poolCap.borrow()!  // MAY PANIC UNEXPECTEDLY
```

## Medium Priority Rules

### Capacity Checking (MEDIUM)
**Enforcement**: Runtime Safety  
**Criticality**: MEDIUM

#### Pre-operation Validation
```cadence
let available = source.minimumAvailable()
let capacity = sink.minimumCapacity()

assert(available > 0.0, message: "No tokens available from source")
assert(capacity > 0.0, message: "No capacity available in sink")
assert(available <= capacity, message: "Insufficient sink capacity")
```

### Type Parameter Validation (MEDIUM)
**Enforcement**: Runtime Safety  
**Criticality**: MEDIUM

#### Type Validation Pattern
```cadence
transaction(vaultTypeString: String) {
    prepare(acct: auth(BorrowValue) &Account) {
        let vaultType = CompositeType(vaultTypeString) 
            ?? panic("Invalid vault type: ".concat(vaultTypeString))
    }
}
```

### Empty Vault Creation (MEDIUM)
**Enforcement**: Best Practice  
**Criticality**: MEDIUM

#### Correct Pattern
```cadence
// ✅ Use utility function
let emptyVault <- DeFiActionsUtils.getEmptyVault(tokenType)
```

#### Manual Pattern (ERROR-PRONE)
```cadence
// ❌ Manual creation (inconsistent)
let emptyVault <- TokenContract.createEmptyVault()
```

## Low Priority Guidelines

### Error Message Standards (LOW)
**Enforcement**: Best Practice  
**Criticality**: LOW

#### Informative Error Messages
```cadence
// ✅ Include context
assert(vault.balance == 0.0, message: "Transfer incomplete - remaining: ".concat(vault.balance.toString()))
panic("Could not access pool \(poolId) at address \(poolAddress)")
```

#### Generic Error Messages
```cadence
// ❌ Not helpful for debugging
assert(vault.balance == 0.0, message: "Transfer failed")
panic("Error occurred")
```

### UniqueID Usage (LOW)
**Enforcement**: Best Practice  
**Criticality**: LOW

#### Consistent UniqueID Usage
```cadence
// ✅ Use same ID for related operations
let operationID = DeFiActions.createUniqueIdentifier()
let source = PoolRewardsSource(..., uniqueID: operationID)
let swapper = Zapper(..., uniqueID: operationID)
let sink = PoolSink(..., uniqueID: operationID)
```

## Required Account Entitlements

### Standard Entitlements
```cadence
auth(BorrowValue) &Account                                     // Read storage, borrow capabilities
auth(SaveValue) &Account                                       // Save resources to storage  
auth(IssueStorageCapabilityController) &Account               // Create storage capabilities
auth(PublishCapability) &Account                              // Publish public capabilities
```

### Common Combinations
```cadence
auth(BorrowValue, SaveValue) &Account                         // Most transactions
auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account  // Setup transactions
```

## Testing Requirements

### Required Test Matrix
| Component Type | Zero Amount | Max Amount | Invalid Cap | Inactive Pool |
|---------------|-------------|------------|-------------|---------------|
| VaultSource   | ✓           | ✓          | ✓           | N/A           |
| VaultSink     | ✓           | ✓          | ✓           | N/A           |
| PoolSink      | ✓           | ✓          | ✓           | ✓             |
| SwapSource    | ✓           | ✓          | ✓           | ✓             |

### Event Validation
```cadence
let events = Test.eventsOfType(Type<DeFiActions.EventType>())
Test.expect(events.length, Test.equal(expectedCount))
```
