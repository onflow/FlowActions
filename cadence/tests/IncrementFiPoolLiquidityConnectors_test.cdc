import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "TokenA"
import "TokenB"

import "DeFiActions"
import "IncrementFiPoolLiquidityConnectors"

access(all) let testTokenAccount = Test.getAccount(0x0000000000000010)
access(all) let pairCreatorAccount = Test.createAccount()
access(all) let serviceAccount = Test.serviceAccount()

access(all) let tokenAIdentifier = Type<@TokenA.Vault>().identifier // "A.<ADDRESS>.TokenA.Vault"
access(all) let tokenBIdentifier = Type<@TokenB.Vault>().identifier // "A.<ADDRESS>.TokenB.Vault"
// IncrementFi identifies tokens by their contract identifier - e.g. A.<ADDRESS>.TokenA for A.<ADDRESS>.TokenA.Vault
access(all) let tokenAKey = String.join(tokenAIdentifier.split(separator: ".").slice(from: 0, upTo: 3), separator: ".")
access(all) let tokenBKey = String.join(tokenBIdentifier.split(separator: ".").slice(from: 0, upTo: 3), separator: ".")

access(all)
fun setup() {
    setupIncrementFiDependencies()

    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActionsMathUtils",
        path: "../contracts/utils/DeFiActionsMathUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "SwapConnectors",
        path: "../contracts/connectors/SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "IncrementFiSwapConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiSwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "IncrementFiPoolLiquidityConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiPoolLiquidityConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    transferFlow(signer: serviceAccount, recipient: pairCreatorAccount.address, amount: 10.0)

    createSwapPair(
        signer: pairCreatorAccount,
        token0Identifier: tokenAIdentifier,
        token1Identifier: tokenBIdentifier,
        stableMode: true,
    )

    createSwapPair(
        signer: pairCreatorAccount,
        token0Identifier: tokenAIdentifier,
        token1Identifier: tokenBIdentifier,
        stableMode: false,
    )

    setupGenericVault(signer: pairCreatorAccount, vaultIdentifier: tokenAIdentifier)
    setupGenericVault(signer: pairCreatorAccount, vaultIdentifier: tokenBIdentifier)
    mintTestTokens(
        signer: testTokenAccount,
        recipient: pairCreatorAccount.address,
        amount: 10000.0,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )
    mintTestTokens(
        signer: testTokenAccount,
        recipient: pairCreatorAccount.address,
        amount: 10000.0,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.ReceiverPublicPath
    )

    // Stable mode pool
    addLiquidity(
        signer: pairCreatorAccount,
        token0Key: tokenAKey,
        token1Key: tokenBKey,
        token0InDesired: 123.0,
        token1InDesired: 345.0,
        token0InMin: 0.0,
        token1InMin: 0.0,
        deadline: getCurrentBlockTimestamp() + 1000.0,
        token0VaultPath: TokenA.VaultStoragePath,
        token1VaultPath: TokenB.VaultStoragePath,
        stableMode: true,
    )

    // Volatile mode pool
    addLiquidity(
        signer: pairCreatorAccount,
        token0Key: tokenAKey,
        token1Key: tokenBKey,
        token0InDesired: 901.0,
        token1InDesired: 678.0,
        token0InMin: 0.0,
        token1InMin: 0.0,
        deadline: getCurrentBlockTimestamp() + 10.0,
        token0VaultPath: TokenA.VaultStoragePath,
        token1VaultPath: TokenB.VaultStoragePath,
        stableMode: false,
    )
}

access(all)
fun testEstimateAndSwapStable() {
    let inAmount = 4.2

    // Estimate swap amount
    let expectedOutAmount = quoteOut(
        inAmount: inAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
        reverse: false
    )

    // Execute swap
    let outAmount = swap(
        inAmount: inAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
    )
    Test.expect(outAmount, Test.equal(expectedOutAmount))
}

access(all)
fun testEstimateAndSwapBackStable() {
    let lpTokenInAmount = 0.2

    // Estimate swapBack amount
    let expectedOutAmount = quoteOut(
        inAmount: lpTokenInAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
        reverse: true // LP -> TokenA
    )

    // Execute swapBack
    let outAmount = swapBack(
        inAmount: lpTokenInAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
    )
    Test.expect(outAmount, Test.equal(expectedOutAmount))
}

access(all)
fun testEstimateAndSwapVolatile() {
    let inAmount = 3.14159

    // Estimate swap amount
    let expectedOutAmount = quoteOut(
        inAmount: inAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
        reverse: false
    )

    // Execute swap
    let outAmount = swap(
        inAmount: inAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
    )
    Test.expect(outAmount, Test.equal(expectedOutAmount))
}

access(all)
fun testEstimateAndSwapBackVolatile() {
    let lpTokenInAmount = 69.069

    // Estimate swapBack amount
    let expectedOutAmount = quoteOut(
        inAmount: lpTokenInAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
        reverse: true // LP -> TokenA
    )

    // Execute swapBack
    let outAmount = swapBack(
        inAmount: lpTokenInAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
    )
    Test.expect(outAmount, Test.equal(expectedOutAmount))
}

access(all)
fun testZeroQuoteOutDoesNotPanic() {
    // Test that instantiating a zapper and calling quoteOut with 0 doesn't panic
    let zeroAmount = 0.0

    // Test stable mode with zero quote - forward direction (TokenA -> LP)
    let stableQuoteForward = quoteOut(
        inAmount: zeroAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
        reverse: false
    )
    Test.expect(stableQuoteForward, Test.equal(0.0))

    // Test stable mode with zero quote - reverse direction (LP -> TokenA)
    let stableQuoteReverse = quoteOut(
        inAmount: zeroAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: true,
        reverse: true
    )
    Test.expect(stableQuoteReverse, Test.equal(0.0))

    // Test volatile mode with zero quote - forward direction (TokenA -> LP)
    let volatileQuoteForward = quoteOut(
        inAmount: zeroAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
        reverse: false
    )
    Test.expect(volatileQuoteForward, Test.equal(0.0))

    // Test volatile mode with zero quote - reverse direction (LP -> TokenA)
    let volatileQuoteReverse = quoteOut(
        inAmount: zeroAmount,
        tokenAIdentifier: tokenAIdentifier,
        tokenBIdentifier: tokenBIdentifier,
        stableMode: false,
        reverse: true
    )
    Test.expect(volatileQuoteReverse, Test.equal(0.0))
}

access(self) fun quoteOut(
    inAmount: UFix64,
    tokenAIdentifier: String,
    tokenBIdentifier: String,
    stableMode: Bool,
    reverse: Bool,
): UFix64 {
    let amountsOutRes = executeScript(
            "../scripts/increment-fi-adapters/zapper/get_amounts_out.cdc",
            [inAmount, tokenAIdentifier, tokenBIdentifier, stableMode, reverse]
        )
    Test.expect(amountsOutRes, Test.beSucceeded())
    let quote = amountsOutRes.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(inAmount, quote.inAmount)
    return quote.outAmount
}

access(self) fun swap(
    inAmount: UFix64,
    tokenAIdentifier: String,
    tokenBIdentifier: String,
    stableMode: Bool,
): UFix64 {
    let numEvents = Test.eventsOfType(Type<DeFiActions.Swapped>()).length
    let result = executeTransaction(
        "./transactions/increment-fi/zapper/swap.cdc",
        [inAmount, tokenAIdentifier, tokenBIdentifier, stableMode],
        pairCreatorAccount
    )
    Test.expect(result.error, Test.beNil())
    let swappedEvents = Test.eventsOfType(Type<DeFiActions.Swapped>())
    Test.expect(swappedEvents.length - numEvents, Test.equal(1))
    let swappedEvent: DeFiActions.Swapped = swappedEvents[swappedEvents.length - 1] as! DeFiActions.Swapped
    Test.expect(swappedEvent.inAmount, Test.equal(inAmount))
    return swappedEvent.outAmount
}

access(self) fun swapBack(
    inAmount: UFix64,
    tokenAIdentifier: String,
    tokenBIdentifier: String,
    stableMode: Bool,
): UFix64 {
    let numEvents = Test.eventsOfType(Type<DeFiActions.Swapped>()).length
    let result = executeTransaction(
        "./transactions/increment-fi/zapper/swapBack.cdc",
        [inAmount, tokenAIdentifier, tokenBIdentifier, stableMode],
        pairCreatorAccount
    )
    Test.expect(result.error, Test.beNil())
    let swappedEvents = Test.eventsOfType(Type<DeFiActions.Swapped>())
    Test.expect(swappedEvents.length - numEvents, Test.equal(1))
    let swappedEvent: DeFiActions.Swapped = swappedEvents[swappedEvents.length - 1] as! DeFiActions.Swapped
    Test.expect(swappedEvent.inAmount, Test.equal(inAmount))
    return swappedEvent.outAmount
}