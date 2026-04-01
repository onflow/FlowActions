import Test
import BlockchainHelpers

import "TokenA"
import "TokenB"

import "DeFiActions"
import "SwapConnectors"
import "MockSwapper"

access(all) let testTokenAccount = Test.getAccount(0x0000000000000010)
access(all) let serviceAccount = Test.serviceAccount()

access(all)
fun transferFlow(signer: Test.TestAccount, recipient: Address, amount: UFix64) {
    let code = Test.readFile("../transactions/flow-token/transfer_flow.cdc")
    let txn = Test.Transaction(code: code, authorizers: [signer.address], signers: [signer], arguments: [recipient, amount])
    Test.expect(Test.executeTransaction(txn), Test.beSucceeded())
}

access(all)
fun runTransaction(path: String, signer: Test.TestAccount, arguments: [AnyStruct]): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: arguments
    )
    return Test.executeTransaction(txn)
}

// inVault: TokenA, outVault: TokenB — shared across all multi-swapper tests
access(all) let inVaultType  = Type<@TokenA.Vault>()
access(all) let outVaultType = Type<@TokenB.Vault>()

/// Returns a CapLimitedSwapper config using TokenA → TokenB vaults.
access(all) fun makeConfig(priceRatio: UFix64, maxOut: UFix64): {String: AnyStruct} {
    return {
        "inVault":     inVaultType,
        "outVault":    outVaultType,
        "inVaultPath": TokenA.VaultStoragePath,
        "outVaultPath": TokenB.VaultStoragePath,
        "priceRatio":  priceRatio,
        "maxOut":      maxOut
    }
}

access(all)
fun setup() {
    log("================== Setting up SwapConnectorsMultiSwapper test ==================")
    var err = Test.deployContract(name: "TestTokenMinter", path: "./contracts/TestTokenMinter.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "TokenA", path: "./contracts/TokenA.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "TokenB", path: "./contracts/TokenB.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "DeFiActionsUtils", path: "../contracts/utils/DeFiActionsUtils.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "DeFiActions", path: "../contracts/interfaces/DeFiActions.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "FungibleTokenConnectors", path: "../contracts/connectors/FungibleTokenConnectors.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "SwapConnectors", path: "../contracts/connectors/SwapConnectors.cdc", arguments: [])
    Test.expect(err, Test.beNil())
    err = Test.deployContract(name: "MockSwapper", path: "./contracts/MockSwapper.cdc", arguments: [])
    Test.expect(err, Test.beNil())

    transferFlow(signer: serviceAccount, recipient: testTokenAccount.address, amount: 10.0)
}

/// quoteIn — among two full-coverage routes, the one with the lower inAmount wins.
///
/// Swapper 0: priceRatio=0.5 → inAmount = 10.0/0.5 = 20.0  (expensive, full coverage)
/// Swapper 1: priceRatio=0.8 → inAmount = 10.0/0.8 = 12.5  (cheaper, full coverage)
/// Expected: index 1, inAmount=12.5, outAmount=10.0
///
access(all)
fun testQuoteInPreferMinInAmongFullCoverage() {
    let forDesired = 10.0
    let configs = [
        makeConfig(priceRatio: 0.5, maxOut: 100.0),
        makeConfig(priceRatio: 0.8, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_in.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forDesired, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(10.0 / 0.8, quote.inAmount)
    Test.assertEqual(forDesired, quote.outAmount)
    Test.assertEqual(inVaultType,  quote.inType)
    Test.assertEqual(outVaultType, quote.outType)
}

/// quoteIn — a full-coverage route wins over a partial-coverage route even when the partial
/// route has a lower inAmount.
///
/// Swapper 0: priceRatio=1.0, maxOut=5.0  → partial (outAmount=5.0 < 10.0), inAmount=5.0
/// Swapper 1: priceRatio=0.5, maxOut=100.0 → full   (outAmount=10.0),        inAmount=20.0
/// Expected: index 1 (full coverage wins despite higher inAmount)
///
access(all)
fun testQuoteInFullWinsOverPartial() {
    let forDesired = 10.0
    let configs = [
        makeConfig(priceRatio: 1.0, maxOut: 5.0),
        makeConfig(priceRatio: 0.5, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_in.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forDesired, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(forDesired, quote.outAmount)
}

/// quoteIn — when no full-coverage route exists, the partial route with the highest outAmount wins.
///
/// Swapper 0: priceRatio=0.8, maxOut=3.0 → partial (outAmount=3.0)
/// Swapper 1: priceRatio=0.7, maxOut=7.0 → partial (outAmount=7.0)
/// Expected: index 1 (higher outAmount among partials)
///
access(all)
fun testQuoteInPartialFallbackMaxOut() {
    let forDesired = 10.0
    let configs = [
        makeConfig(priceRatio: 0.8, maxOut: 3.0),
        makeConfig(priceRatio: 0.7, maxOut: 7.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_in.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forDesired, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(7.0, quote.outAmount)
    Test.assertEqual(10.0, quote.inAmount) // 7.0 / priceRatio=0.7
}

/// quoteOut — the route with the highest outAmount wins.
///
/// Swapper 0: priceRatio=0.5, maxOut=100.0 → outAmount=5.0
/// Swapper 1: priceRatio=0.8, maxOut=100.0 → outAmount=8.0
/// Expected: index 1 (higher outAmount)
///
access(all)
fun testQuoteOutPreferMaxOut() {
    let forProvided = 10.0
    let configs = [
        makeConfig(priceRatio: 0.5, maxOut: 100.0),
        makeConfig(priceRatio: 0.8, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(forProvided, quote.inAmount)
    Test.assertEqual(10.0 * 0.8, quote.outAmount)
    Test.assertEqual(inVaultType,  quote.inType)
    Test.assertEqual(outVaultType, quote.outType)
}

access(all)
fun testQuoteInReversePreferMinInAmongFullCoverage() {
    let forDesired = 10.0
    let configs = [
        makeConfig(priceRatio: 0.8, maxOut: 100.0),
        makeConfig(priceRatio: 0.5, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_in.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forDesired, true]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(5.0, quote.inAmount)
    Test.assertEqual(forDesired, quote.outAmount)
    Test.assertEqual(outVaultType, quote.inType)
    Test.assertEqual(inVaultType, quote.outType)
}

access(all)
fun testQuoteOutReversePreferMaxOut() {
    let forProvided = 10.0
    let configs = [
        makeConfig(priceRatio: 0.8, maxOut: 100.0),
        makeConfig(priceRatio: 0.5, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, true]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(forProvided, quote.inAmount)
    Test.assertEqual(20.0, quote.outAmount)
    Test.assertEqual(outVaultType, quote.inType)
    Test.assertEqual(inVaultType, quote.outType)
}

/// quoteOut — a cap constraint causes a higher-ratio route to deliver less output than a
/// lower-ratio uncapped route, so the uncapped route wins.
///
/// Swapper 0: priceRatio=0.5, maxOut=100.0 → outAmount=5.0  (uncapped)
/// Swapper 1: priceRatio=0.9, maxOut=4.0   → rawOut=9.0, capped to 4.0
/// Expected: index 0 (outAmount=5.0 > 4.0 after cap)
///
access(all)
fun testQuoteOutCapLimitsRoute() {
    let forProvided = 10.0
    let configs = [
        makeConfig(priceRatio: 0.5, maxOut: 100.0),
        makeConfig(priceRatio: 0.9, maxOut: 4.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(0, quote.swapperIndex)
    Test.assertEqual(5.0, quote.outAmount) // 10.0 * 0.5
}

access(all)
fun testQuoteInPartialTieBreaksOnLowerInAmount() {
    let forDesired = 10.0
    let configs = [
        makeConfig(priceRatio: 0.5, maxOut: 5.0),
        makeConfig(priceRatio: 1.0, maxOut: 5.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_in.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forDesired, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)
    Test.assertEqual(5.0, quote.inAmount)
    Test.assertEqual(5.0, quote.outAmount)
}

access(all)
fun testQuoteOutPreservesProvidedInputOnCappedRoute() {
    let forProvided = 10.0
    let configs = [
        makeConfig(priceRatio: 1.0, maxOut: 4.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(0, quote.swapperIndex)
    Test.assertEqual(forProvided, quote.inAmount)
    Test.assertEqual(4.0, quote.outAmount)
}

access(all)
fun testSwapWithQuoteOutFallbackSucceedsAgainstStrictInnerSwapper() {
    // args = [amountIn, priceRatio, maxOut]
    // swap 10 TokenA at a 1:1 rate through a route that can output at most 4 TokenB
    let result = runTransaction(
        path: "./transactions/multi-swapper/mock_strict_swap_quote_out.cdc",
        signer: testTokenAccount,
        arguments: [10.0, 1.0, 4.0]
    )
    Test.expect(result, Test.beSucceeded())
}

access(all)
fun testSwapSourceWithdrawAvailableDoesNotExceedMaxAmount() {
    // args = [maxAmount, quoteInOvershoot]
    // ask for at most 10 TokenB while the mock quoteIn reports 1 extra TokenB
    let result = runTransaction(
        path: "./transactions/multi-swapper/mock_swap_source_quote_in_overshoot.cdc",
        signer: testTokenAccount,
        arguments: [10.0, 1.0]
    )
    Test.expect(result, Test.beSucceeded())
}

/// quoteOut — four swappers: maximize outAmount first, then minimize inAmount as tiebreaker.
///
/// S0 (suboptimal):  priceRatio=1.0,  maxOut=100.0 → outAmount=100.0, inAmount=100.0
/// S1 (optimal):     priceRatio=1.25, maxOut=110.0 → rawOut=125 → capped outAmount=110.0, inAmount=88.0
/// S2:               priceRatio=1.1,  maxOut=110.0 → rawOut=110 → capped outAmount=110.0, inAmount=100.0
/// S3 (worst):       priceRatio=2.0,  maxOut=40.0  → rawOut=200 → capped outAmount=40.0,  inAmount=20.0
///
/// S1 and S2 tie on outAmount (110.0); S1 wins the tiebreaker (inAmount 88.0 < 100.0).
/// S0 is eliminated by lower outAmount; S3 by lowest outAmount despite cheapest inAmount.
/// Expected: index 1 (S1), outAmount=110.0, inAmount=100.0
/// The selected route still uses S1's lower inner inAmount as the tiebreaker,
/// but the outward MultiSwapper quote preserves the caller-provided input amount.
///
access(all)
fun testQuoteOutMaxOutThenMinIn() {
    let forProvided = 100.0
    let configs = [
        makeConfig(priceRatio: 1.0,  maxOut: 100.0),  // S0
        makeConfig(priceRatio: 1.25, maxOut: 110.0),  // S1 — optimal
        makeConfig(priceRatio: 1.1,  maxOut: 110.0),  // S2
        makeConfig(priceRatio: 2.0,  maxOut: 40.0)    // S3
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(1, quote.swapperIndex)           // S1 wins
    Test.assertEqual(110.0, quote.outAmount)          // max outAmount
    Test.assertEqual(forProvided, quote.inAmount)     // outward quote preserves provided input
}

/// quoteOut — a capacity-capped swapper that consumes less than forProvided (inAmount < forProvided)
/// must still be preferred when it delivers more output than a swapper that consumes the full input.
///
/// This validates that filtering `inAmount < forProvided` (as suggested in review) is wrong:
/// that filter would discard swapper 0 and return swapper 1's inferior quote.
///
/// Swapper 0: priceRatio=0.8, maxOut=4.0
///   → rawOut = 10.0 * 0.8 = 8.0, capped → outAmount=4.0, inAmount=4.0/0.8=5.0
///   → inAmount=5.0 < forProvided=10.0, but outAmount=4.0 is the best available
/// Swapper 1: priceRatio=0.2, maxOut=100.0
///   → rawOut = 10.0 * 0.2 = 2.0, uncapped → outAmount=2.0, inAmount=10.0
/// Expected: index 0 (outAmount=4.0 > 2.0), while outward quote preserves inAmount=10.0
///
access(all)
fun testQuoteOutPartialConsumerWinsIfMoreOutput() {
    let forProvided = 10.0
    let configs = [
        makeConfig(priceRatio: 0.8, maxOut: 4.0),
        makeConfig(priceRatio: 0.2, maxOut: 100.0)
    ]

    let result = executeScript(
        "./scripts/multi-swapper/mock_quote_out.cdc",
        [testTokenAccount.address, configs, inVaultType, outVaultType, forProvided, false]
    )
    Test.expect(result, Test.beSucceeded())
    let quote = result.returnValue! as! SwapConnectors.MultiSwapperQuote

    Test.assertEqual(0, quote.swapperIndex)
    Test.assertEqual(4.0, quote.outAmount)
    Test.assertEqual(forProvided, quote.inAmount)
}
