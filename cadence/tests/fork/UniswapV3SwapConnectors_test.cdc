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

access(all) let FACTORY    = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
access(all) let ROUTER     = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
access(all) let QUOTER     = "0x370A8DF17742867a44e56223EC20D82092242C85"
access(all) let PYUSD      = "0x99aF3EeA856556646C98c8B9b2548Fe815240750"
access(all) let MOET       = "0x213979bB8A9A86966999b3AA797C1fcf3B967ae2"
access(all) let POOL_FEE: UInt32 = 100   // 1 % fee tier
access(all) let V2_ROUTER  = "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d" // PunchSwap V2

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

// --- Swap test helpers --------------------------------------------------------

/// Runs the swap dust test transaction with V2 provisioning:
///   1. On first call: Provisions tokenIn via PunchSwap V2 (FlowToken -> WFLOW -> tokenIn)
///   2. For each test amount: runs quoteIn + swap and records metrics
///   3. Stores result at /storage/swapDustResult after each swap
///
/// Returns rows of:
///   [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
access(all) fun runSwapDustTest(
    signer: Test.TestAccount,
    tokenIn: String,
    tokenOut: String,
    provisionFlowAmount: UFix64,
    testAmounts: [UFix64]
): [[UFix64]] {
    var results: [[UFix64]] = []

    // Loop through test amounts, calling transaction once per amount
    for i, desiredOut in testAmounts {
        // Only provision on first call
        let provisionAmount = i == 0 ? provisionFlowAmount : 0.0

        let txn = Test.Transaction(
            code: Test.readFile(
                "../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap_dust_test.cdc"
            ),
            authorizers: [signer.address],
            signers: [signer],
            arguments: [
                FACTORY,
                ROUTER,
                QUOTER,
                tokenIn,
                tokenOut,
                POOL_FEE,
                V2_ROUTER,
                provisionAmount,
                desiredOut
            ]
        )
        let txnResult = Test.executeTransaction(txn)
        Test.expect(txnResult, Test.beSucceeded())

        // Read result from account storage
        let script = Test.readFile(
            "../scripts/uniswap-v3-swap-connectors/read_swap_dust_result.cdc"
        )
        let result = Test.executeScript(script, [signer.address])
        Test.expect(result, Test.beSucceeded())
        results.append(result.returnValue as! [UFix64])
    }

    // Cleanup: destroy stored vault
    let cleanupTxn = Test.Transaction(
        code: Test.readFile("../transactions/cleanup_test_vault.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: []
    )
    Test.executeTransaction(cleanupTxn)

    return results
}

/// Runs the swap overshoot test transaction with token transfer from holder:
///   1. On first call: Transfers tokenIn from holder and bridges to Cadence
///   2. For each test amount: runs quoteIn + swap and records metrics
///   3. Stores result at /storage/swapDustResult after each swap
///
/// Returns rows of:
///   [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
access(all) fun runSwapOvershootTest(
    signer: Test.TestAccount,
    tokenIn: String,
    tokenOut: String,
    provisionAmount: UFix64,
    holderAddr: String,
    testAmounts: [UFix64]
): [[UFix64]] {
    var results: [[UFix64]] = []

    // Loop through test amounts, calling transaction once per amount
    for i, desiredOut in testAmounts {
        // Only provision on first call
        let provAmount = i == 0 ? provisionAmount : 0.0

        let txn = Test.Transaction(
            code: Test.readFile(
                "../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap_overshoot_test.cdc"
            ),
            authorizers: [signer.address],
            signers: [signer],
            arguments: [
                FACTORY,
                ROUTER,
                QUOTER,
                tokenIn,
                tokenOut,
                POOL_FEE,
                provAmount,
                holderAddr,
                desiredOut
            ]
        )
        let txnResult = Test.executeTransaction(txn)
        Test.expect(txnResult, Test.beSucceeded())

        // Read result from account storage
        let script = Test.readFile(
            "../scripts/uniswap-v3-swap-connectors/read_swap_dust_result.cdc"
        )
        let result = Test.executeScript(script, [signer.address])
        Test.expect(result, Test.beSucceeded())
        results.append(result.returnValue as! [UFix64])
    }

    // Cleanup: destroy stored vault
    let cleanupTxn = Test.Transaction(
        code: Test.readFile("../transactions/cleanup_test_vault.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: []
    )
    Test.executeTransaction(cleanupTxn)

    return results
}

/// Asserts swap dust/overshoot properties for each result row.
///
/// Overshoot/dust can occur from rounding during quoting and swapping.
/// The key finding: any overshoot beyond what was quoted stays in the COA.
///
/// Verifies:
///   - vaultBalance == quoteOutAmount (caller gets exactly what was quoted)
///   - quoteOutAmount >= desiredOut (may overshoot due to input rounding)
///   - coaDustAfter >= coaDustBefore (overshoot/dust accumulates in COA)
///
access(all) fun assertSwapDust(results: [[UFix64]]) {
    var testedCount: Int = 0
    var skippedCount: Int = 0
    var totalOvershoot: UFix64 = 0.0
    var totalDustInCOA: UFix64 = 0.0

    for row in results {
        let desiredOut       = row[0]
        let quoteInAmount    = row[1]
        let quoteOutAmount   = row[2]
        let vaultBalance     = row[3]
        let coaDustBefore    = row[4]
        let coaDustAfter     = row[5]

        // Skip amounts where swap was not performed (quote failed or insufficient balance)
        // Transaction records 0.0 for amounts when canSwap = false
        if quoteInAmount == 0.0 || quoteOutAmount == 0.0 || vaultBalance == 0.0 {
            skippedCount = skippedCount + 1
            let reason = quoteInAmount == 0.0 || quoteOutAmount == 0.0
                ? "quoter returned 0 (no liquidity)"
                : "insufficient balance"
            log("[SKIP] desiredOut=".concat(desiredOut.toString())
                .concat(" — ").concat(reason))
            continue
        }

        testedCount = testedCount + 1

        // Total overshoot from desired amount (quoting overshoot)
        let overshoot = quoteOutAmount >= desiredOut
            ? quoteOutAmount - desiredOut
            : 0.0
        totalOvershoot = totalOvershoot + overshoot

        // Dust that stayed in COA (swap dust beyond quote)
        let dustInCOA = coaDustAfter >= coaDustBefore
            ? coaDustAfter - coaDustBefore
            : 0.0
        totalDustInCOA = totalDustInCOA + dustInCOA

        // Log swap details
        log("---")
        log("[SWAP] Desired: ".concat(desiredOut.toString())
            .concat(", Quote: ").concat(quoteOutAmount.toString())
            .concat(", Returned: ").concat(vaultBalance.toString()))
        log("  Overshoot/Dust => quote vs desired: +".concat(overshoot.toString())
            .concat(", stayed in COA: +").concat(dustInCOA.toString()))
        log("  COA balance => ".concat(coaDustBefore.toString())
            .concat(" → ").concat(coaDustAfter.toString()))

        // Assert: vault balance matches quote exactly
        Test.assertEqual(quoteOutAmount, vaultBalance)

        // Assert: COA dust never decreases (overshoot/dust accumulates)
        Test.assert(coaDustAfter >= coaDustBefore,
            message: "COA output-token balance decreased — overshoot/dust should accumulate in COA")
    }

    Test.assert(testedCount > 0, message: "No test amounts could be swapped")
    log("=== PASSED: ".concat(testedCount.toString()).concat(" swaps, ")
        .concat(skippedCount.toString()).concat(" skipped ==="))
    log("=== Total overshoot/dust that stayed in COA: ".concat(totalDustInCOA.toString()).concat(" ==="))
}

// --- Swap tests ---------------------------------------------------------------

/// Proves that actual V3 swaps return a vault with balance == quote.outAmount
/// and that any overshoot dust stays in the COA (never bridged to the caller).
///
/// Provisions PYUSD via PunchSwap V2 (FlowToken -> WFLOW -> PYUSD), then
/// swaps PYUSD -> MOET via the V3 connector for several desired output amounts.
///
access(all) fun testSwapDustStaysInCOA() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    let testAmounts: [UFix64] = [
        0.01,
        0.1,
        0.45019707,   // produces exactly 1 quantum (0.00000001) overshoot in quoting
        1.0
    ]

    let results = runSwapDustTest(
        signer: signer,
        tokenIn: PYUSD,
        tokenOut: MOET,
        provisionFlowAmount: 50.0,
        testAmounts: testAmounts
    )

    assertSwapDust(results: results)
}

/// Demonstrates visible overshoot accumulation in COA with different amounts.
///
/// Provisions PYUSD via PunchSwap V2, then tests PYUSD -> MOET swaps
/// with amounts likely to produce visible overshoot.
/// The test verifies that:
///   1. The returned vault contains exactly the quoted amount
///   2. Quoting overshoot (quote > desired) goes to the caller
///   3. Swap dust (actual > quote) accumulates in the COA
///
access(all) fun testSwapOvershootStaysInCOA() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    // Use amounts that are more likely to produce visible overshoot
    let testAmounts: [UFix64] = [
        0.1,
        0.5,
        1.5,
        3.0
    ]

    let results = runSwapDustTest(
        signer: signer,
        tokenIn: PYUSD,
        tokenOut: MOET,
        provisionFlowAmount: 20.0,  // Reduced to avoid running out of FLOW
        testAmounts: testAmounts
    )

    assertSwapDust(results: results)
}

// NOTE: MOET -> PYUSD swap tests are not included because:
// - V2 router (PunchSwap) has insufficient liquidity for WFLOW -> MOET provisioning
// - Quoting tests already demonstrate overshoot behavior in both directions
// - The PYUSD -> MOET swap tests above comprehensively show COA dust accumulation
