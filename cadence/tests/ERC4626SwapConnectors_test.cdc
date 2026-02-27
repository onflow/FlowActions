import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FlowToken"
import "DeFiActions"
import "EVM"
import "ERC4626Utils"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let deployerAccount = Test.createAccount()

access(all) var wflowHex = ""
access(all) var deployerCOAAddress = ""
access(all) var underlyingIdentifier = ""
access(all) var vaultIdentifier = ""

access(all) let initialAssets: UInt256 = 1_000_000_000_000_000_000_000 // 1_000.0 tokens at 18 decimals
access(all) var expectedInitialShares: UInt256 = initialAssets * 100 // 1_000.0 tokens at 20 decimals - decimals offset of 2
access(all) let uintDepositAmount: UInt256 = 10_000_000_000_000_000_000 // 10.0 tokens at 18 decimals
access(all) let ufixDepositAmount = 10.0

access(all) var snapshot: UInt64 = 0

access(all) var vaultDeploymentInfo = MoreVaultDeploymentResult(
    wflow: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    underlying: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    stable: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    factory: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    vault: EVM.addressFromString("0x0000000000000000000000000000000000000000")
)

access(all) fun setup() {
    log("================== Setting up ERC4626SwapConnectors test ==================")
    wflowHex = getEVMAddressAssociated(withType: Type<@FlowToken.Vault>().identifier)!

    // TODO: remove this step once the VM bridge templates are updated for test env
    // see https://github.com/onflow/flow-go/issues/8184
    tempUpsertBridgeTemplateChunks(serviceAccount)

    // create deployer account and fund it
    transferFlow(signer: serviceAccount, recipient: deployerAccount.address, amount: 101.0)
    createCOA(deployerAccount, fundingAmount: 100.0)
    deployerCOAAddress = getCOAAddressHex(atFlowAddress: deployerAccount.address)

    var err = Test.deployContract(
        name: "EVMAbiHelpers",
        path: "../contracts/utils/EVMAbiHelpers.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // setup More Vaults & create a Minimal Vault
    vaultDeploymentInfo = setupMoreVaults(deployerAccount, wflow: EVM.addressFromString(wflowHex), initialAssets: initialAssets)

    // onboard the underlying and vault EVM addresses to the bridge
    onboardByEVMAddress(deployerAccount, evmAddress: vaultDeploymentInfo.underlying.toString())
    onboardByEVMAddress(deployerAccount, evmAddress: vaultDeploymentInfo.vault.toString())

    // assign the identifiers of Cadence types associated with the underlying and vault EVM addresses
    underlyingIdentifier = getTypeAssociated(withEVMAddress: vaultDeploymentInfo.underlying.toString())!.identifier
    vaultIdentifier = getTypeAssociated(withEVMAddress: vaultDeploymentInfo.vault.toString())!.identifier

    // deploy DeFiActionsUtils & DeFiActions
    err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "SwapConnectors",
        path: "../contracts/connectors/SwapConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "EVMTokenConnectors",
        path: "../contracts/connectors/evm/EVMTokenConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "ERC4626Utils",
        path: "../contracts/utils/ERC4626Utils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "EVMAmountUtils",
        path: "../contracts/connectors/evm/EVMAmountUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "ERC4626SinkConnectors",
        path: "../contracts/connectors/evm/ERC4626SinkConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "ERC4626SwapConnectors",
        path: "../contracts/connectors/evm/ERC4626SwapConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // mint 100.0 tokens of the underlying to the deployer account
    let mintCalldata = String.encodeHex(EVM.encodeABIWithSignature("mint(address,uint256)",
            [EVM.addressFromString(deployerCOAAddress), uintDepositAmount]
        ))
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.underlying.toString(),
        calldata: mintCalldata,
        gasLimit: 1000000,
        value: 0,
        beFailed: false
    )
    // bridge the asset tokens to the deployer account
    let bridgeRes = executeTransaction(
        "./transactions/bridge/bridge_tokens_from_evm.cdc",
        [underlyingIdentifier, uintDepositAmount],
        deployerAccount
    )
    Test.expect(bridgeRes, Test.beSucceeded())

    snapshot = getCurrentBlockHeight()
}

access(all) fun testSwapAssetsInForSharesSucceeds() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    let beforeTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let beforeTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(beforeTotalShares, expectedInitialShares)
    Test.assertEqual(beforeTotalAssets, initialAssets)

    let swapRes = executeTransaction(
            "../transactions/erc4626-swap-connectors/swap_assets_in_for_shares.cdc",
            [ufixDepositAmount, 0.01, underlyingIdentifier, vaultDeploymentInfo.vault.toString()],
            deployerAccount
        )
    Test.expect(swapRes, Test.beSucceeded())

    let afterTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let afterTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(afterTotalShares, expectedInitialShares + uintDepositAmount * 100) // increase by 100x due to decimals offset
    Test.assertEqual(afterTotalAssets, initialAssets + uintDepositAmount)
}

access(all) fun testSwapAssetsForSharesOutSucceeds() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    let beforeTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let beforeTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(beforeTotalShares, expectedInitialShares)
    Test.assertEqual(beforeTotalAssets, initialAssets)

    let swapRes = executeTransaction(
            "../transactions/erc4626-swap-connectors/swap_assets_for_shares_out.cdc",
            [ufixDepositAmount, 10.0, underlyingIdentifier, vaultDeploymentInfo.vault.toString()],
            deployerAccount
        )
    Test.expect(swapRes, Test.beSucceeded())

    let afterTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let afterTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(afterTotalShares, expectedInitialShares + uintDepositAmount * 100) // increase by 100x due to decimals offset
    Test.assertEqual(afterTotalAssets, initialAssets + uintDepositAmount)
}

access(all) fun testQuoteInWithLargeAmountReturnsMaxWhenOverflow() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Donate assets directly to the vault (no shares minted) to make assets/share > 1.
    // With a 2x asset/share ratio, requesting UFix64.max shares should overflow the
    // asset-decimal max check but still be below the vault-decimal max check.
    let beforeTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let beforeTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(beforeTotalShares, expectedInitialShares)
    Test.assertEqual(beforeTotalAssets, initialAssets)

    let donationAmount = initialAssets
    let donateCalldata = String.encodeHex(EVM.encodeABIWithSignature("mint(address,uint256)",
            [vaultDeploymentInfo.vault, donationAmount]
        ))
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.underlying.toString(),
        calldata: donateCalldata,
        gasLimit: 1000000,
        value: 0,
        beFailed: false
    )

    let afterTotalShares = getEVMTotalSupply(callAs: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    let afterTotalAssets = getERC4626TotalAssets(callAs: deployerCOAAddress, erc4626Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(afterTotalShares, expectedInitialShares)
    Test.assertEqual(afterTotalAssets, initialAssets + donationAmount)
    let quoteRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_in.cdc",
        [deployerAccount.address, UFix64.max, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteRes, Test.beSucceeded())

    let quote = quoteRes.returnValue! as! {DeFiActions.Quote}
    log("Quote In (max) - inAmount: \(quote.inAmount), outAmount: \(quote.outAmount)")

    // With assets/share > 1, the overflow guard should cap inAmount at UFix64.max.
    Test.assertEqual(quote.outAmount, UFix64.max)
    Test.assertEqual(quote.inAmount, UFix64.max)
}

/// testQuoteInCapsAtMaxCapacity tests that quoteIn() caps the required input amount at maxCapacity when the desired shares
/// would require more assets than the vault can accept.
access(all) fun testQuoteInCapsAtMaxCapacity() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Get the asset sink's minimum capacity
    let maxCapacityRes = executeScript(
        "./scripts/erc4626-swap-connectors/get_asset_sink_min_capacity.cdc",
        [deployerAccount.address, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(maxCapacityRes, Test.beSucceeded())
    let maxCapacity = maxCapacityRes.returnValue! as! UFix64
    log("Asset sink min capacity: \(maxCapacity)")

    // Request a quote for shares that would require more assets than maxCapacity
    let largeDesiredShares = 100000000.0 // Very large amount of shares

    let quoteInRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_in.cdc",
        [deployerAccount.address, largeDesiredShares, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteInRes, Test.beSucceeded())

    let quoteIn = quoteInRes.returnValue! as! {DeFiActions.Quote}
    log("Quote In (large) - inAmount: \(quoteIn.inAmount), outAmount: \(quoteIn.outAmount)")

    // The inAmount should be capped at maxCapacity
    Test.assert(quoteIn.inAmount <= maxCapacity, message: "inAmount should be capped at maxCapacity")
    
    // outAmount should be recalculated based on the capped inAmount
    // Verify by getting a quoteOut for the capped amount
    let quoteOutRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_out.cdc",
        [deployerAccount.address, quoteIn.inAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteOutRes, Test.beSucceeded())
    let quoteOut = quoteOutRes.returnValue! as! {DeFiActions.Quote}
    
    // The outAmount from quoteIn should match the outAmount from quoteOut for the same inAmount
    Test.assertEqual(quoteIn.outAmount, quoteOut.outAmount)
}

/// testQuoteInAndQuoteOutConsistencyWithCapacityLimit tests that quoteIn() and quoteOut() 
/// return consistent results for amounts within the capacity limit.
access(all) fun testQuoteInAndQuoteOutConsistencyWithCapacityLimit() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Get the asset sink's minimum capacity
    let maxCapacityRes = executeScript(
        "./scripts/erc4626-swap-connectors/get_asset_sink_min_capacity.cdc",
        [deployerAccount.address, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(maxCapacityRes, Test.beSucceeded())
    let maxCapacity = maxCapacityRes.returnValue! as! UFix64
    log("Asset sink min capacity: \(maxCapacity)")

    // Test with an amount below maxCapacity - should work normally
    let normalAmount = 5.0
    
    let quoteOutRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_out.cdc",
        [deployerAccount.address, normalAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteOutRes, Test.beSucceeded())
    let quoteOut = quoteOutRes.returnValue! as! {DeFiActions.Quote}
    log("Quote Out (normal) - inAmount: \(quoteOut.inAmount), outAmount: \(quoteOut.outAmount)")

    // Now get quoteIn for the shares we'd receive
    let quoteInRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_in.cdc",
        [deployerAccount.address, quoteOut.outAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteInRes, Test.beSucceeded())
    let quoteIn = quoteInRes.returnValue! as! {DeFiActions.Quote}
    log("Quote In (normal) - inAmount: \(quoteIn.inAmount), outAmount: \(quoteIn.outAmount)")

    // For amounts within capacity, both should give consistent results
    Test.assert(quoteIn.inAmount <= maxCapacity, message: "quoteIn.inAmount should be within maxCapacity")
    Test.assert(quoteOut.inAmount <= maxCapacity, message: "quoteOut.inAmount should be within maxCapacity")
}

/// testQuoteInWithExactMaxCapacity tests that quoteIn() correctly handles a request for shares that would require exactly maxCapacity assets.
access(all) fun testQuoteInWithExactMaxCapacity() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Get the asset sink's minimum capacity
    let maxCapacityRes = executeScript(
        "./scripts/erc4626-swap-connectors/get_asset_sink_min_capacity.cdc",
        [deployerAccount.address, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(maxCapacityRes, Test.beSucceeded())
    let maxCapacity = maxCapacityRes.returnValue! as! UFix64
    log("Asset sink min capacity: \(maxCapacity)")

    // First get a quoteOut at maxCapacity to know how many shares that would give
    let quoteOutRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_out.cdc",
        [deployerAccount.address, maxCapacity, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteOutRes, Test.beSucceeded())
    let quoteOut = quoteOutRes.returnValue! as! {DeFiActions.Quote}
    log("Quote Out (maxCapacity) - inAmount: \(quoteOut.inAmount), outAmount: \(quoteOut.outAmount)")

    // Now request quoteIn for exactly those shares
    let quoteInRes = executeScript(
        "./scripts/erc4626-swap-connectors/quote_in.cdc",
        [deployerAccount.address, quoteOut.outAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()]
    )
    Test.expect(quoteInRes, Test.beSucceeded())
    let quoteIn = quoteInRes.returnValue! as! {DeFiActions.Quote}
    log("Quote In (exact shares) - inAmount: \(quoteIn.inAmount), outAmount: \(quoteIn.outAmount)")

    // inAmount should be at or below maxCapacity
    Test.assert(quoteIn.inAmount <= maxCapacity, message: "quoteIn.inAmount should not exceed maxCapacity")
}
