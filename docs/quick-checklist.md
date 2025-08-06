# Quick Checklist

## Essential Pre-Implementation Checks

### ✅ Import Requirements
- [ ] Use `import "ContractName"` format
- [ ] Never use `import ContractName from 0x123...` format
- [ ] Include all required contract imports

### ✅ Pre/Post-Condition Requirements  
- [ ] Pre/post-conditions are single boolean expressions only
- [ ] No variable declarations in pre/post blocks
- [ ] Use `assert()` in execute block for complex validation

### ✅ Address Parameter Requirements
- [ ] Pass addresses as transaction parameters
- [ ] Never use `Type<Contract>().address` in transactions
- [ ] Validate capabilities before using them

### ✅ Resource Safety Requirements
- [ ] Check `vault.balance == 0.0` before destroying
- [ ] Handle all withdrawn resources completely  
- [ ] Use proper capability authentication

## Implementation Steps

### Step 1: Component Selection
1. **Identify Source**: Where tokens come from
   - [`VaultSource`](./connectors.md#vaultsource) - User's vault
   - [`PoolRewardsSource`](./connectors.md#poolrewardssource) - Staking rewards
   - [`AutoBalancerSource`](./connectors.md#autobalancersource) - Rebalancer excess

2. **Identify Swapper** (optional): Token conversion
   - [`Zapper`](./connectors.md#zapper) - Single token to LP
   - [`MultiSwapper`](./connectors.md#multiswapper) - DEX routing

3. **Identify Sink**: Where tokens go  
   - [`VaultSink`](./connectors.md#vaultsink) - Target vault
   - [`PoolSink`](./connectors.md#poolsink) - Staking pool
   - [`AutoBalancerSink`](./connectors.md#autobalancersink) - Rebalancer deposit

### Step 2: Component Chain Design
```
Basic: Source -> Sink
Enhanced: Source -> SwapSource(Swapper) -> Sink
Complex: VaultSource -> SwapSource(Zapper) -> PoolSink
```

### Step 3: Transaction Implementation
```cadence
transaction(requiredAddresses: Address, amounts: UFix64) {
    let capabilities: Capability<&Resource>
    let initialState: UFix64

    prepare(acct: auth(RequiredEntitlements) &Account) {
        // Get capabilities and save initial state
    }

    execute {
        // 1. Create components
        // 2. Execute transfer  
        // 3. Validate completion
    }

    pre {
        // Single expression only
    }

    post {
        // Single expression only
    }
}
```

## Validation Checklist

### During Implementation
- [ ] String import syntax used
- [ ] Addresses passed as parameters
- [ ] Capabilities validated before use
- [ ] Components created in correct order
- [ ] Transfer executed properly
- [ ] Resource balance verified
- [ ] Vault destroyed after validation

### Testing Requirements
- [ ] Test with zero amounts
- [ ] Test with maximum amounts (`UFix64.max`)
- [ ] Test with invalid capabilities
- [ ] Test when pools/protocols are inactive
- [ ] Test slippage protection
- [ ] Verify events are emitted
- [ ] Check error messages are informative

## Common Error Patterns

### ❌ Import Errors
```cadence
import FungibleToken from 0x123456  // WRONG: Use import "FungibleToken"
```

### ❌ Pre/Post-Condition Errors  
```cadence
post {
    let newBalance = vault.balance  // WRONG: Multiple statements
    newBalance >= minimum: "Below minimum"
}
```

### ❌ Address Usage Errors
```cadence
let pool = getAccount(Type<Staking>().address)  // WRONG: Use parameter
```

### ❌ Resource Handling Errors
```cadence
sink.deposit(from: <-vault)  // WRONG: Could lose tokens
destroy vault               // WRONG: Destroys without verification
```

## Quick Reference Links

### Core Documentation
- [`index.md`](./index.md) - Documentation index
- [`core-framework.md`](./core-framework.md) - Interface definitions
- [`connectors.md`](./connectors.md) - Available components
- [`patterns.md`](./patterns.md) - Workflow patterns

### Implementation Help
- [`safety-rules.md`](./safety-rules.md) - Critical safety rules
- [`type-system.md`](./type-system.md) - Type definitions and patterns
- [`testing.md`](./testing.md) - Testing patterns and examples

### Workflow Examples
- [`workflows/restaking-workflow.md`](./workflows/restaking-workflow.md) - Complete restaking example
- [`workflows/autobalancer-workflow.md`](./workflows/autobalancer-workflow.md) - AutoBalancer setup

## Emergency Debugging

### Transaction Fails to Compile
1. Check import syntax (must use string format)
2. Verify pre/post-conditions are single expressions
3. Ensure all required contracts are imported

### Transaction Fails at Runtime
1. Verify capabilities are valid
2. Check addresses are passed as parameters
3. Validate resource balances before operations
4. Ensure pools/protocols are active

### Unexpected Resource Loss
1. Check vault.balance == 0.0 before destroy
2. Verify depositCapacity vs deposit usage
3. Ensure complete transfer validation
4. Review overflow sink configurations
