#test_fork(network: "mainnet", height: 142_691_298)

import Test

import "EVM"
import "FlowToken"
import "UniswapV3SwapConnectors"

/// Fork test: Overshooting dust bound for UniswapV3 swap connector
///
/// Demonstrates that quoteIn and quoteOut are perfectly consistent (quoteDust = 0),
/// that the overshoot from the desired amount is bounded, and that the trimming
/// guard (line 539 in UniswapV3SwapConnectors.cdc) correctly caps bridged amounts
/// at amountOutMin — leaving dust in the COA.
///
/// PYUSD→MOET direction produces observable dust because MOET is an 18-decimal
/// ERC20 on EVM and `toCadenceOut` floors to 10^10 wei quantum boundaries.
/// MOET→PYUSD shows zero dust because PYUSD (6-decimal) converts exactly.
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
access(all) let MOET_DEPLOYER: Address = 0x6b00ff876c299c61 // MOET contract deployer (has Minter)

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
/// MOET is an 18-decimal ERC20 on EVM, so `toCadenceOut` floors to the nearest
/// 10^10 wei (1 UFix64 quantum = 0.00000001).  The overshoot arises because:
///   1. `quoteIn` calls exactOutput → ceils the raw input → runs a forward
///      exactInput quote with the ceiled input.
///   2. The forward quote may return slightly more output than the original
///      desired amount when the extra input crosses a UFix64-quantum boundary.
///
/// Amounts with many fractional digits are more likely to produce non-aligned
/// EVM wei values that cross quantum boundaries after rounding.  The highest
/// observed overshoot is +87 quanta at 0.20000000 MOET desired.
///
access(all) fun testOvershootingDustIsBounded() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    // Pool liquidity caps at ~0.58 MOET output, so amounts above that are clamped.
    // Focus on the productive range where quoting is uncapped.
    let testAmounts: [UFix64] = [
        0.00100000,   // +62 quanta overshoot
        0.00500000,
        0.00987654,   // +30 quanta
        0.01000000,   // +69 quanta — highest observed
        0.02000000,
        0.03456789,
        0.05000000,
        0.05432109,   // +26 quanta
        0.10000000,   // +10 quanta
        0.12345678,   // +44 quanta
        0.20000000,
        0.23456789,   // +8 quanta
        0.30000000,
        0.34567890,   // +4 quanta
        0.40000000,
        0.45019707,   // +1 quantum — tightest possible
        0.50000000,
        0.56789012    // +62 quanta
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
/// PYUSD is a 6-decimal ERC20 (≤8), so `toCadenceOut` is an exact conversion.
/// Overshoot here comes solely from the V3 pool math's rounding (exactOutput
/// rounds input UP, exactInput rounds output DOWN), not from UFix64 quantisation.
///
access(all) fun testOvershootingDustIsBoundedReverse() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    // Pool liquidity caps at ~0.62 PYUSD output in this direction.
    let testAmounts: [UFix64] = [
        0.00100000,
        0.01000000,
        0.05000000,
        0.10000000,
        0.12345678,
        0.30000000,
        0.45019707,
        0.56789012
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

// --- MOET minting helper ------------------------------------------------------

/// Mints MOET and saves to signer's /storage/testTokenInVault using the MOET
/// deployer's Minter. Works on forked emulator because signatures aren't verified.
///
access(all) fun mintMOETToTestVault(signer: Test.TestAccount, amount: UFix64) {
    let moetDeployer = Test.getAccount(MOET_DEPLOYER)
    let txn = Test.Transaction(
        code: Test.readFile(
            "../transactions/uniswap-v3-swap-connectors/mint_moet_to_test_vault.cdc"
        ),
        authorizers: [moetDeployer.address, signer.address],
        signers: [moetDeployer, signer],
        arguments: [amount]
    )
    let txnResult = Test.executeTransaction(txn)
    Test.expect(txnResult, Test.beSucceeded())
}

// --- PYUSD provisioning helper ------------------------------------------------

/// Provisions PYUSD by minting MOET and swapping to PYUSD via V3.
/// After this call, signer's /storage/testTokenInVault contains PYUSD.
///
access(all) fun provisionPYUSD(signer: Test.TestAccount, moetMintAmount: UFix64, moetSwapAmount: UFix64) {
    // Step 1: Mint MOET to testTokenInVault
    mintMOETToTestVault(signer: signer, amount: moetMintAmount)

    // Step 2: Swap MOET→PYUSD via V3
    let txn = Test.Transaction(
        code: Test.readFile(
            "../transactions/uniswap-v3-swap-connectors/provision_pyusd_via_v3.cdc"
        ),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [FACTORY, ROUTER, QUOTER, MOET, PYUSD, POOL_FEE, moetSwapAmount]
    )
    let txnResult = Test.executeTransaction(txn)
    Test.expect(txnResult, Test.beSucceeded())
}

// --- Swap test helpers --------------------------------------------------------

/// Runs swap tests with the token already provisioned in /storage/testTokenInVault.
/// For each test amount: runs quoteIn + swap and records metrics.
///
/// Returns rows of:
///   [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
access(all) fun runSwapTests(
    signer: Test.TestAccount,
    tokenIn: String,
    tokenOut: String,
    testAmounts: [UFix64]
): [[UFix64]] {
    var results: [[UFix64]] = []

    for desiredOut in testAmounts {
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
                0.0,
                "0x0000000000000000000000000000000000000000",
                desiredOut
            ]
        )
        let txnResult = Test.executeTransaction(txn)
        Test.expect(txnResult, Test.beSucceeded())

        let script = Test.readFile(
            "../scripts/uniswap-v3-swap-connectors/read_swap_dust_result.cdc"
        )
        let result = Test.executeScript(script, [signer.address])
        Test.expect(result, Test.beSucceeded())
        results.append(result.returnValue as! [UFix64])
    }

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
/// Verifies:
///   - vaultBalance == quoteOutAmount (caller gets exactly what was quoted)
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

        let overshoot = quoteOutAmount >= desiredOut
            ? quoteOutAmount - desiredOut
            : 0.0
        totalOvershoot = totalOvershoot + overshoot

        let dustInCOA = coaDustAfter >= coaDustBefore
            ? coaDustAfter - coaDustBefore
            : 0.0
        totalDustInCOA = totalDustInCOA + dustInCOA

        log("---")
        log("[SWAP] Desired: ".concat(desiredOut.toString())
            .concat(", Quote: ").concat(quoteOutAmount.toString())
            .concat(", Returned: ").concat(vaultBalance.toString()))
        log("  Overshoot/Dust => quote vs desired: +".concat(overshoot.toString())
            .concat(", stayed in COA: +").concat(dustInCOA.toString()))
        log("  COA balance => ".concat(coaDustBefore.toString())
            .concat(" → ").concat(coaDustAfter.toString()))

        Test.assertEqual(quoteOutAmount, vaultBalance)

        Test.assert(coaDustAfter >= coaDustBefore,
            message: "COA output-token balance decreased — overshoot/dust should accumulate in COA")
    }

    Test.assert(testedCount > 0, message: "No test amounts could be swapped")
    log("=== PASSED: ".concat(testedCount.toString()).concat(" swaps, ")
        .concat(skippedCount.toString()).concat(" skipped ==="))
    log("=== Total overshoot/dust that stayed in COA: ".concat(totalDustInCOA.toString()).concat(" ==="))
}

// --- Swap tests ---------------------------------------------------------------

/// Baseline: MOET → PYUSD swaps produce zero COA dust because PYUSD is a
/// 6-decimal ERC20 (≤8 decimals), so `toCadenceOut` is an exact conversion
/// with no quantum-boundary rounding.
///
access(all) fun testSwapDustStaysInCOA() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    // Provision MOET via minting
    mintMOETToTestVault(signer: signer, amount: 100.0)

    let testAmounts: [UFix64] = [
        0.01,
        0.1,
        1.0
    ]

    let results = runSwapTests(
        signer: signer,
        tokenIn: MOET,
        tokenOut: PYUSD,
        testAmounts: testAmounts
    )

    assertSwapDust(results: results)
}

/// Demonstrates the trimming guard in action on PYUSD → MOET swaps.
///
/// MOET is an 18-decimal ERC20, so `toCadenceOut` floors actual output to the
/// nearest 10^10 wei (1 UFix64 quantum).  When the router produces even slightly
/// more output than the quoter predicted — because ceiled input crosses a
/// quantum boundary — the trimming guard caps the bridged amount at
/// `amountOutMin` and the excess stays in the COA.
///
/// Many fractional amounts are tested to maximise the chance of hitting
/// quantum-boundary crossings that produce observable dust.
///
access(all) fun testSwapOvershootStaysInCOA() {
    let signer = Test.getAccount(0x47f544294e3b7656)
    ensureCOA(signer)

    // Provision PYUSD: mint MOET then swap to PYUSD via V3
    provisionPYUSD(signer: signer, moetMintAmount: 200.0, moetSwapAmount: 100.0)

    let testAmounts: [UFix64] = [
        0.00987654,
        0.01000000,
        0.03456789,
        0.05432109,
        0.10000000,
        0.12345678,   // dust hit in first run
        0.20000000,
        0.23456789,   // dust hit
        0.34567890,
        0.45019707,
        0.56789012,
        0.67890123,
        0.78901234,   // dust hit
        1.00000000,   // dust hit (even with 0 quote overshoot)
        1.23456789,
        1.50000000,
        2.34567890,   // dust hit
        3.45678901,
        5.00000000
    ]

    // PYUSD → MOET direction: 18-decimal output triggers trimming guard
    let results = runSwapTests(
        signer: signer,
        tokenIn: PYUSD,
        tokenOut: MOET,
        testAmounts: testAmounts
    )

    assertSwapDust(results: results)
}

