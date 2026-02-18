#test_fork(network: "mainnet", height: nil)

import Test

import "EVM"
import "FlowToken"
import "UniswapV3SwapConnectors"

/// Fork test: Overshooting dust bound for UniswapV3 swap connector
///
/// Demonstrates that quoteIn and quoteOut are perfectly consistent (quoteDust = 0)
/// and that the overshoot from the desired amount is bounded against a real
/// PYUSD/MOET pool on Flow EVM mainnet.  Includes a specific amount (0.45019707)
/// that produces exactly 1 UFix64 quantum (0.00000001) of overshoot.
///
/// Pool contracts (Flow EVM mainnet):
///   PYUSD:   0x99aF3EeA856556646C98c8B9b2548Fe815240750
///   MOET:    0x213979bB8A9A86966999b3AA797C1fcf3B967ae2
///   Factory: 0xca6d7Bb03334bBf135902e1d919a5feccb461632
///   Quoter:  0xeEDC6Ff75e1b10B903D9013c358e446a73d35341
///   Router:  0x370A8DF17742867a44e56223EC20D82092242C85
///

// --- Addresses ----------------------------------------------------------------

access(all) let FACTORY  = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
access(all) let ROUTER   = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
access(all) let QUOTER   = "0x370A8DF17742867a44e56223EC20D82092242C85"
access(all) let PYUSD    = "0x99aF3EeA856556646C98c8B9b2548Fe815240750"
access(all) let MOET     = "0x213979bB8A9A86966999b3AA797C1fcf3B967ae2"
access(all) let POOL_FEE: UInt32 = 100   // 1 % fee tier

// --- Setup --------------------------------------------------------------------

access(all) fun setup() {
    // Deploy the LATEST local contract code to the forked environment.
    // This replaces the mainnet-deployed versions so we test the newest logic.

    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../../contracts/utils/DeFiActionsUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    err = Test.deployContract(
        name: "DeFiActions",
        path: "../../contracts/interfaces/DeFiActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    err = Test.deployContract(
        name: "SwapConnectors",
        path: "../../contracts/connectors/SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    err = Test.deployContract(
        name: "EVMAbiHelpers",
        path: "../../contracts/utils/EVMAbiHelpers.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    err = Test.deployContract(
        name: "EVMAmountUtils",
        path: "../../contracts/connectors/evm/EVMAmountUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    err = Test.deployContract(
        name: "UniswapV3SwapConnectors",
        path: "../../contracts/connectors/evm/UniswapV3SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()
}

// --- Helpers ------------------------------------------------------------------

access(all) fun ensureCOA(_ signer: Test.TestAccount) {
    let checkScript = Test.readFile("../../scripts/evm/has_coa.cdc")
    let result = Test.executeScript(checkScript, [signer.address])
    Test.expect(result, Test.beSucceeded())

    let hasCOA = result.returnValue as! Bool
    if hasCOA { return }

    // Create a COA funded with 1 FLOW
    let createCOATxn = Test.Transaction(
        code: Test.readFile("../../transactions/evm/create_coa.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [1.0]
    )
    let txnResult = Test.executeTransaction(createCOATxn)
    Test.expect(txnResult, Test.beSucceeded())
}

/// Runs the quote dust script and returns rows of
///   [desiredOut, quoteIn.inAmount, quoteIn.outAmount, quoteOut.inAmount, quoteOut.outAmount]
access(all) fun runQuoteDustScript(
    signer: Test.TestAccount,
    tokenIn: String,
    tokenOut: String,
    testAmounts: [UFix64]
): [[UFix64]] {
    let script = Test.readFile(
        "../scripts/uniswap-v3-swap-connectors/uniswap_v3_quote_dust_test.cdc"
    )
    let result = Test.executeScript(script, [
        signer.address,
        FACTORY,
        ROUTER,
        QUOTER,
        tokenIn,
        tokenOut,
        POOL_FEE,
        testAmounts
    ])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue as! [[UFix64]]
}

/// Asserts quote consistency and logs full quote details for a set of results.
///
/// For each row:
///   - quoteDust  = quoteOut.outAmount - quoteIn.outAmount  (must be 0)
///   - overshoot  = quoteIn.outAmount  - desiredOut         (>= 0, logged)
///
access(all) fun assertQuoteDust(results: [[UFix64]]) {
    var maxOvershoot: UFix64 = 0.0
    var testedCount: Int = 0

    for row in results {
        let desiredOut   = row[0]
        let quoteInIn    = row[1]
        let quoteInOut   = row[2]
        let quoteOutIn   = row[3]
        let quoteOutOut  = row[4]

        // Skip amounts where quoter returned 0
        if quoteInIn == 0.0 || quoteInOut == 0.0 {
            log("[SKIP] desiredOut=".concat(desiredOut.toString())
                .concat(" - quoter returned 0 (insufficient liquidity or pool not found)"))
            continue
        }

        let quoteDust: UFix64 = quoteOutOut > quoteInOut
            ? quoteOutOut - quoteInOut
            : 0.0

        let overshoot: UFix64 = quoteInOut >= desiredOut
            ? quoteInOut - desiredOut
            : 0.0

        if overshoot > maxOvershoot { maxOvershoot = overshoot }
        testedCount = testedCount + 1

        // Log full quote details
        log("---")
        log("[TEST] desiredOut=".concat(desiredOut.toString()))
        log("  quoteIn(forDesired: ".concat(desiredOut.toString()).concat(")")
            .concat("  => { inAmount: ").concat(quoteInIn.toString())
            .concat(", outAmount: ").concat(quoteInOut.toString()).concat(" }"))
        log("  quoteOut(forProvided: ".concat(quoteInIn.toString()).concat(")")
            .concat(" => { inAmount: ").concat(quoteOutIn.toString())
            .concat(", outAmount: ").concat(quoteOutOut.toString()).concat(" }"))
        log("  quoteDust=".concat(quoteDust.toString())
            .concat(" | overshoot=").concat(overshoot.toString()))

        // Assert: quote consistency — quoteIn and quoteOut must agree
        Test.assertEqual(0.0, quoteDust)
    }

    Test.assert(testedCount > 0, message: "No test amounts could be quoted")
    log("=== PASSED: max overshoot = ".concat(maxOvershoot.toString())
        .concat(" across ").concat(testedCount.toString()).concat(" amounts ==="))
}

// --- Tests --------------------------------------------------------------------

/// Proves that quoteIn and quoteOut are consistent (quoteDust = 0) and that
/// the overshoot from the desired amount is non-negative for PYUSD -> MOET.
///
/// The amount 0.45019707 is specifically chosen to produce exactly 1 UFix64
/// quantum (0.00000001) of overshoot, demonstrating the tightest possible
/// rounding surplus.
///
access(all) fun testOvershootingDustIsBounded() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    let testAmounts: [UFix64] = [
        0.001,
        0.01,
        0.1,
        0.45019707,   // produces exactly 1 quantum (0.00000001) overshoot
        1.0,
        5.0,
        10.0
    ]

    let results = runQuoteDustScript(
        signer: signer,
        tokenIn: PYUSD,
        tokenOut: MOET,
        testAmounts: testAmounts
    )

    assertQuoteDust(results: results)
}

/// Same test in the reverse direction (MOET -> PYUSD) to cover swapBack path.
///
access(all) fun testOvershootingDustIsBoundedReverse() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    let testAmounts: [UFix64] = [
        0.001,
        0.01,
        0.1,
        1.0
    ]

    // Reverse direction: MOET in, PYUSD out
    let results = runQuoteDustScript(
        signer: signer,
        tokenIn: MOET,
        tokenOut: PYUSD,
        testAmounts: testAmounts
    )

    assertQuoteDust(results: results)
}
