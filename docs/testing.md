# Testing Patterns

## Unit Testing Patterns

### Test Component in Isolation
```cadence
access(all) fun testVaultSourceBasic() {
    // Setup
    let testAccount = Test.createAccount()
    let testVault <- FlowToken.createEmptyVault()
    testVault.deposit(from: <-FlowToken.createEmptyVault(amount: 100.0))
    
    let vaultCap = testAccount.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(/storage/flowTokenVault)
    
    // Create component
    let source = FungibleTokenStack.VaultSource(
        min: 10.0,
        withdrawVault: vaultCap,
        uniqueID: nil
    )
    
    // Test
    let available = source.minimumAvailable()
    Test.expect(available, Test.equal(90.0))  // 100 - 10 minimum
    
    let vault <- source.withdrawAvailable(maxAmount: 50.0)
    Test.expect(vault.balance, Test.equal(50.0))
    
    destroy vault
}
```

### Test Edge Cases
```cadence
access(all) fun testVaultSourceEdgeCases() {
    // Test zero withdrawal
    let vault1 <- source.withdrawAvailable(maxAmount: 0.0)
    Test.expect(vault1.balance, Test.equal(0.0))
    destroy vault1
    
    // Test excessive withdrawal (should cap at available)
    let vault2 <- source.withdrawAvailable(maxAmount: UFix64.max)
    Test.expect(vault2.balance, Test.beLessThanOrEqual(source.minimumAvailable()))
    destroy vault2
    
    // Test minimum balance protection
    let initialBalance = 100.0
    let minimumBalance = 10.0
    let vault3 <- source.withdrawAvailable(maxAmount: 95.0)
    Test.expect(vault3.balance, Test.equal(90.0))  // Should stop at minimum
    destroy vault3
}
```

### Test Error Conditions
```cadence
access(all) fun testVaultSourceErrors() {
    // Test invalid capability
    let invalidCap: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}> = nil
    Test.expectFailure(fun() {
        let source = FungibleTokenStack.VaultSource(
            min: 0.0,
            withdrawVault: invalidCap,
            uniqueID: nil
        )
        let vault <- source.withdrawAvailable(maxAmount: 10.0)
        destroy vault
    }, errorMessage: "Could not borrow vault capability")
}
```

## Integration Testing Patterns

### Test Complete Workflow
```cadence
access(all) fun testRestakingWorkflow() {
    // Setup accounts and contracts
    let user = Test.createAccount()
    let poolOperator = Test.createAccount()
    
    // Deploy and setup contracts
    deployContracts()
    setupStakingPool(operator: poolOperator)
    setupUserStake(user: user, amount: 100.0)
    
    // Generate rewards
    advanceTime(seconds: 86400)  // 1 day
    
    // Execute restaking workflow
    let txResult = executeTransaction(
        "restaking_workflow.cdc",
        [
            42 as UInt64,                      // poolId
            poolOperator.address,              // poolCollectionAddress
            Type<@FlowToken.Vault>(),          // rewardTokenType
            Type<@FlowToken.Vault>(),          // token0Type
            Type<@USDC.Vault>(),              // token1Type
            0.01 as UFix64                     // slippageTolerance
        ],
        user
    )
    
    Test.expect(txResult.status, Test.equal(Test.ResultStatus.succeeded))
    
    // Verify results
    let finalStake = getStakeAmount(user: user.address, poolId: 42)
    Test.expect(finalStake, Test.beGreaterThan(100.0))  // Should have increased
}
```

### Test Component Composition
```cadence
access(all) fun testSwapSourceComposition() {
    // Setup components
    let source = createTestVaultSource(balance: 100.0)
    let swapper = createTestSwapper(
        fromType: Type<@FlowToken.Vault>(),
        toType: Type<@USDC.Vault>(),
        rate: 2.0  // 1 FLOW = 2 USDC
    )
    
    // Create composite
    let swapSource = SwapStack.SwapSource(
        swapper: swapper,
        source: source,
        uniqueID: nil
    )
    
    // Test type compatibility
    Test.expect(swapSource.getSourceType(), Test.equal(Type<@USDC.Vault>()))
    
    // Test execution
    let vault <- swapSource.withdrawAvailable(maxAmount: 200.0)  // Request 200 USDC
    Test.expect(vault.balance, Test.equal(200.0))  // Should get 200 USDC from 100 FLOW
    Test.expect(vault.getType(), Test.equal(Type<@USDC.Vault>()))
    
    destroy vault
}
```

## Event Testing

### Verify Event Emission
```cadence
access(all) fun testEventEmission() {
    // Execute transaction that should emit events
    executeTransaction("vault_transfer.cdc", [...], user)
    
    // Check DeFiActions events
    let depositEvents = Test.eventsOfType(Type<DeFiActions.Deposited>())
    Test.expect(depositEvents.length, Test.equal(1))
    
    let withdrawEvents = Test.eventsOfType(Type<DeFiActions.Withdrawn>())
    Test.expect(withdrawEvents.length, Test.equal(1))
    
    // Verify event data
    let depositEvent = depositEvents[0] as! DeFiActions.Deposited
    Test.expect(depositEvent.amount, Test.equal(100.0))
    Test.expect(depositEvent.tokenType, Test.equal(Type<@FlowToken.Vault>()))
}
```

### Test Event Ordering
```cadence
access(all) fun testEventOrdering() {
    executeComplexTransaction()
    
    let allEvents = Test.events()
    let defiEvents = allEvents.filter(fun(event: AnyStruct): Bool {
        return event.type.identifier.hasPrefix("A.DeFiActions")
    })
    
    // Verify events are in correct order
    Test.expect(defiEvents[0].type, Test.equal(Type<DeFiActions.Withdrawn>()))
    Test.expect(defiEvents[1].type, Test.equal(Type<DeFiActions.Swapped>()))
    Test.expect(defiEvents[2].type, Test.equal(Type<DeFiActions.Deposited>()))
}
```

## Performance Testing

### Gas Cost Testing
```cadence
access(all) fun testGasCosts() {
    let gasStart = Test.getGasUsed()
    
    executeTransaction("restaking_workflow.cdc", [...], user)
    
    let gasEnd = Test.getGasUsed()
    let gasUsed = gasEnd - gasStart
    
    Test.expect(gasUsed, Test.beLessThan(1000))  // Should use less than 1000 gas units
}
```

### Capacity Testing
```cadence
access(all) fun testHighVolumeOperations() {
    // Test with maximum values
    let maxAmount = UFix64.max / 2  // Avoid overflow
    
    let source = createTestVaultSource(balance: maxAmount)
    let vault <- source.withdrawAvailable(maxAmount: maxAmount)
    
    Test.expect(vault.balance, Test.equal(maxAmount))
    destroy vault
}
```

## Mock Helpers

### Mock VaultSource
```cadence
access(all) struct MockVaultSource: DeFiActions.Source {
    access(all) let balance: UFix64
    access(all) let tokenType: Type
    access(all) let uniqueID: DeFiActions.UniqueIdentifier?
    
    init(balance: UFix64, tokenType: Type) {
        self.balance = balance
        self.tokenType = tokenType
        self.uniqueID = nil
    }
    
    access(all) view fun getSourceType(): Type {
        return self.tokenType
    }
    
    access(all) fun minimumAvailable(): UFix64 {
        return self.balance
    }
    
    access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
        let withdrawAmount = maxAmount < self.balance ? maxAmount : self.balance
        return <-FlowToken.createEmptyVault(amount: withdrawAmount)
    }
}
```

### Mock Swapper
```cadence
access(all) struct MockSwapper: DeFiActions.Swapper {
    access(all) let fromType: Type
    access(all) let toType: Type
    access(all) let rate: UFix64
    access(all) let uniqueID: DeFiActions.UniqueIdentifier?
    
    init(fromType: Type, toType: Type, rate: UFix64) {
        self.fromType = fromType
        self.toType = toType
        self.rate = rate
        self.uniqueID = nil
    }
    
    access(all) view fun getFromType(): Type {
        return self.fromType
    }
    
    access(all) view fun getToType(): Type {
        return self.toType
    }
    
    access(all) fun swap(from: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
        let inputAmount = from.balance
        destroy from
        
        let outputAmount = inputAmount * self.rate
        return <-USDC.createEmptyVault(amount: outputAmount)
    }
}
```

## Test Organization

### Test Suite Structure
```cadence
// tests/unit/
//   - VaultSource_test.cdc
//   - VaultSink_test.cdc
//   - PoolSink_test.cdc
//   - Zapper_test.cdc

// tests/integration/
//   - RestakingWorkflow_test.cdc
//   - AutoBalancerSetup_test.cdc
//   - MultiProtocolChain_test.cdc

// tests/performance/
//   - GasCost_test.cdc
//   - HighVolume_test.cdc

// tests/helpers/
//   - MockComponents.cdc
//   - TestSetup.cdc
//   - Assertions.cdc
```

### Test Naming Convention
```cadence
// Format: test[Component][Scenario]
access(all) fun testVaultSourceBasicWithdrawal() { ... }
access(all) fun testVaultSourceMinimumBalanceProtection() { ... }
access(all) fun testVaultSourceInvalidCapability() { ... }
access(all) fun testZapperFlowToUSDCLP() { ... }
access(all) fun testRestakingWorkflowWithSlippage() { ... }
```
