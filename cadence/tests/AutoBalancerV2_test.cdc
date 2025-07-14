import Test
import BlockchainHelpers

import "FungibleToken"
import "FlowToken"
import "DFB"
import "DFBv2"
import "DFBMathUtils"

access(all) let admin = Test.getAccount(0x0000000000000007)

access(all)
fun setup() {
    // Deploy contracts
    var err = Test.deployContract(
        name: "DFBMathUtils",
        path: "../contracts/utils/DFBMathUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "DFBv2",
        path: "../contracts/interfaces/DFBv2.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// Mock Oracle for testing
access(all) struct MockOracle : DFB.PriceOracle {
    access(self) let prices: {Type: UFix64}
    
    init() {
        self.prices = {}
        // Set initial price for FlowToken
        self.prices[Type<@FlowToken.Vault>()] = 1.50
    }
    
    access(all) view fun unitOfAccount(): Type {
        return Type<@FlowToken.Vault>()  // USD represented as Flow for simplicity
    }
    
    access(all) fun price(ofToken: Type): UFix64? {
        return self.prices[ofToken]
    }
    
    access(all) fun setPrice(token: Type, price: UFix64) {
        self.prices[token] = price
    }
}

access(all)
fun testPrecisionComparisonSmallAmounts() {
    let oracle = MockOracle()
    
    // Test with small amounts that could lose precision
    let smallAmount = 0.00000123
    let price = 1234.56789012
    
    // Original calculation (UFix64)
    let ufixResult = smallAmount * price
    
    // High-precision calculation (UInt256)
    let uintAmount = DFBMathUtils.toUInt256(smallAmount)
    let uintPrice = DFBMathUtils.toUInt256(price)
    let uintResult = DFBMathUtils.mul(uintAmount, uintPrice)
    let preciseResult = DFBMathUtils.toUFix64(uintResult)
    
    Test.assertEqual(0.00151851, ufixResult)  // UFix64 result (8 decimals)
    Test.assertEqual(0.00151851, preciseResult)  // Should maintain precision
    
    // The difference might be small but accumulates over many operations
    log("UFix64 result: \(ufixResult)")
    log("UInt256 result: \(preciseResult)")
}

access(all)
fun testPrecisionComparisonLargeAmounts() {
    // Test with large amounts
    let largeAmount = 999999.99999999
    let price = 9999.99999999
    
    // Original calculation (UFix64)
    let ufixResult = largeAmount * price
    
    // High-precision calculation (UInt256)
    let uintAmount = DFBMathUtils.toUInt256(largeAmount)
    let uintPrice = DFBMathUtils.toUInt256(price)
    let uintResult = DFBMathUtils.mul(uintAmount, uintPrice)
    let preciseResult = DFBMathUtils.toUFix64(uintResult)
    
    log("Large amount UFix64 result: \(ufixResult)")
    log("Large amount UInt256 result: \(preciseResult)")
    
    // Both should handle large numbers, but UInt256 maintains more precision internally
}

access(all)
fun testAutoBalancerV2ValueTracking() {
    let oracle = MockOracle()
    oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 1.0)
    
    // Create AutoBalancerV2 with initial deposit
    let initialVault <- Test.mintFlowTokens(100.0)
    let balancer <- DFBv2.createAutoBalancerV2(
        oracle: oracle,
        vault: <-initialVault,
        rebalanceRange: [0.95, 1.05],
        rebalanceSink: nil,
        rebalanceSource: nil,
        uniqueID: nil
    )
    
    // Check initial state
    Test.assertEqual(100.0, balancer.vaultBalance())
    Test.assertEqual(100.0, balancer.valueOfDeposits())
    
    // Simulate multiple small deposits that could accumulate precision errors
    var i = 0
    while i < 100 {
        let smallDeposit <- Test.mintFlowTokens(0.00000001)
        balancer.deposit(from: <-smallDeposit)
        i = i + 1
    }
    
    // Check accumulated value
    let finalBalance = balancer.vaultBalance()
    let finalValue = balancer.valueOfDeposits()
    
    log("Final balance: \(finalBalance)")
    log("Final value: \(finalValue)")
    
    // With UInt256, we should maintain precision even with many small deposits
    Test.assertEqual(100.000001, finalBalance)
    Test.assertEqual(100.000001, finalValue)
    
    destroy balancer
}

access(all)
fun testRebalanceCalculationPrecision() {
    let oracle = MockOracle()
    oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 1.0)
    
    // Create AutoBalancerV2
    let initialVault <- Test.mintFlowTokens(1000.0)
    let balancer <- DFBv2.createAutoBalancerV2(
        oracle: oracle,
        vault: <-initialVault,
        rebalanceRange: [0.95, 1.05],
        rebalanceSink: nil,
        rebalanceSource: nil,
        uniqueID: nil
    )
    
    // Change price to create a small imbalance
    oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 1.0001)
    
    // Current value should reflect the price change with high precision
    let currentValue = balancer.currentValue()!
    Test.assertEqual(1000.1, currentValue)
    
    // The value difference is small but should be calculated precisely
    let valueOfDeposits = balancer.valueOfDeposits()
    let valueDiff = currentValue - valueOfDeposits
    
    log("Value of deposits: \(valueOfDeposits)")
    log("Current value: \(currentValue)")
    log("Value difference: \(valueDiff)")
    
    // Even small differences should be captured accurately
    Test.assertEqual(0.1, valueDiff)
    
    destroy balancer
}

access(all)
fun testProportionalWithdrawalPrecision() {
    let oracle = MockOracle()
    oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 2.5)
    
    // Create AutoBalancerV2 with initial deposit
    let initialVault <- Test.mintFlowTokens(100.0)
    let balancer <- DFBv2.createAutoBalancerV2(
        oracle: oracle,
        vault: <-initialVault,
        rebalanceRange: [0.95, 1.05],
        rebalanceSink: nil,
        rebalanceSource: nil,
        uniqueID: nil
    )
    
    // Initial value should be 100 * 2.5 = 250
    Test.assertEqual(250.0, balancer.valueOfDeposits())
    
    // Withdraw 33.33333333% (1/3)
    let withdrawAmount = 33.33333333
    let withdrawn <- balancer.withdraw(amount: withdrawAmount)
    
    // Remaining balance should be precisely 2/3
    let remainingBalance = balancer.vaultBalance()
    let remainingValue = balancer.valueOfDeposits()
    
    log("Remaining balance: \(remainingBalance)")
    log("Remaining value: \(remainingValue)")
    
    // Should maintain proportional value with high precision
    Test.assertEqual(66.66666667, remainingBalance)
    // Value should be reduced proportionally: 250 * (2/3) ≈ 166.66666667
    let expectedValue = 166.66666667
    Test.assert(remainingValue > expectedValue - 0.00000001 && remainingValue < expectedValue + 0.00000001)
    
    destroy balancer
    destroy withdrawn
}

access(all)
fun testMathUtilsFixedPointOperations() {
    // Test multiplication precision
    let x = DFBMathUtils.toUInt256(1.23456789)
    let y = DFBMathUtils.toUInt256(9.87654321)
    let product = DFBMathUtils.mul(x, y)
    let result = DFBMathUtils.toUFix64(product)
    
    // Expected: 1.23456789 * 9.87654321 = 12.19326309
    Test.assertEqual(12.19326309, result)
    
    // Test division precision
    let dividend = DFBMathUtils.toUInt256(10.0)
    let divisor = DFBMathUtils.toUInt256(3.0)
    let quotient = DFBMathUtils.div(dividend, divisor)
    let divResult = DFBMathUtils.toUFix64(quotient)
    
    // Expected: 10.0 / 3.0 = 3.33333333...
    Test.assertEqual(3.33333333, divResult)
    
    // Test very small number operations
    let tiny1 = DFBMathUtils.toUInt256(0.00000001)
    let tiny2 = DFBMathUtils.toUInt256(0.00000002)
    let tinyProduct = DFBMathUtils.mul(tiny1, tiny2)
    let tinyResult = DFBMathUtils.toUFix64(tinyProduct)
    
    log("Tiny multiplication result: \(tinyResult)")
    // This would be 0 with UFix64 but maintains precision with UInt256
} 