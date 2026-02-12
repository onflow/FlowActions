import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FlowToken"
import "TokenA"
import "TokenB"
import "DeFiActions"
import "UniswapV3SwapConnectors"
import "UniswapV3SwapperProvider"
import "EVM"

// Global test accounts
access(all) let serviceAccount = Test.serviceAccount()
access(all) let deployerAccount = Test.createAccount()
access(all) let testTokenAccount = Test.createAccount()

// EVM addresses (populated in setup)
access(all) var wflowHex = ""
access(all) var tokenAHex = ""
access(all) var tokenBHex = ""
access(all) var deployerCOAHex = ""

// Mock Uniswap V3 addresses (for testing provider logic)
access(all) var uniV3FactoryHex = "0x1234567890123456789012345678901234567890"
access(all) var uniV3RouterHex = "0x2234567890123456789012345678901234567890"
access(all) var uniV3QuoterHex = "0x3234567890123456789012345678901234567890"

// Test state
access(all) var snapshot: UInt64 = 0

access(all) fun setup() {
    log("================== Setting up UniswapV3SwapperProvider test ==================")

    // 1. Initialize bridge templates
    tempUpsertBridgeTemplateChunks(serviceAccount)

    // 2. Get WFLOW address (should be auto-bridged)
    wflowHex = getEVMAddressAssociated(withType: Type<@FlowToken.Vault>().identifier)!

    // 3. Setup test accounts with funding
    transferFlow(signer: serviceAccount, recipient: deployerAccount.address, amount: 50.0)
    transferFlow(signer: serviceAccount, recipient: testTokenAccount.address, amount: 50.0)

    // 4. Create COAs
    createCOA(deployerAccount, fundingAmount: 10.0)
    deployerCOAHex = getCOAAddressHex(atFlowAddress: deployerAccount.address)

    // 5. Set mock addresses for TokenA and TokenB
    // Note: These are not actually bridged, so tests that validate FlowEVMBridgeConfig
    // association will fail. Tests focus on provider logic that can be validated.
    tokenAHex = "0x4444444444444444444444444444444444444444"
    tokenBHex = "0x5555555555555555555555555555555555555555"

    // 6. Deploy DeFiActions contracts
    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
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
        name: "EVMAbiHelpers",
        path: "../contracts/utils/EVMAbiHelpers.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "UniswapV3SwapConnectors",
        path: "../contracts/connectors/evm/UniswapV3SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "UniswapV3SwapperProvider",
        path: "../contracts/connectors/evm/UniswapV3SwapperProvider.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    snapshot = getCurrentBlockHeight()
    log("Setup completed successfully")
}

access(all) fun testSetupSucceeds() {
    log("UniswapV3SwapperProvider deployment success")
}

/* ==================== Configuration Validation Tests ==================== */

access(all) fun testTokenConfigInitWithValidTypes() {
    // Should succeed with proper FungibleToken type and associated EVM address
    // FlowToken should be auto-bridged in the test environment
    let tokenConfig = UniswapV3SwapperProvider.TokenConfig(
        flowType: Type<@FlowToken.Vault>(),
        evmAddress: EVM.addressFromString(wflowHex)
    )
    Test.assertEqual(Type<@FlowToken.Vault>(), tokenConfig.flowType)
    Test.assertEqual(wflowHex, tokenConfig.evmAddress.toString())
}

access(all) fun testTokenConfigFailsWithUnassociatedAddress() {
    // Should panic - WFLOW address not associated with TokenA type
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_invalid_token_config.cdc",
        [Type<@TokenA.Vault>().identifier, wflowHex]  // Wrong address for TokenA
    )
    Test.expect(result, Test.beFailed())
}

access(all) fun testRouteConfigInitWithValidPath() {
    let routeConfig = UniswapV3SwapperProvider.RouteConfig(
        inToken: Type<@FlowToken.Vault>(),
        outToken: Type<@TokenA.Vault>(),
        tokenPath: [EVM.addressFromString(wflowHex), EVM.addressFromString(tokenAHex)],
        feePath: [3000]
    )
    Test.assertEqual(Type<@FlowToken.Vault>(), routeConfig.inToken)
    Test.assertEqual(Type<@TokenA.Vault>(), routeConfig.outToken)
    Test.assertEqual(2, routeConfig.tokenPath.length)
    Test.assertEqual(1, routeConfig.feePath.length)
}

access(all) fun testRouteConfigFailsWithSingleToken() {
    // Should panic - tokenPath must have at least 2 tokens
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_invalid_route_config.cdc",
        ["single_token"]
    )
    Test.expect(result, Test.beFailed())
}

access(all) fun testRouteConfigFailsWithMismatchedFeePath() {
    // Should panic - feePath length must be tokenPath.length - 1
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_invalid_route_config.cdc",
        ["mismatched_fee_path"]
    )
    Test.expect(result, Test.beFailed())
}

access(all) fun testRouteConfigFailsWithSelfSwap() {
    // Should panic - inToken cannot equal outToken
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_invalid_route_config.cdc",
        ["self_swap"]
    )
    Test.expect(result, Test.beFailed())
}

/* ==================== Provider Initialization Tests ==================== */

access(all) fun testProviderInitWithValidConfiguration() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex, tokenBHex],
            3  // Number of routes
        ]
    )
    Test.expect(result, Test.beSucceeded())
}

access(all) fun testProviderInitFailsWithSingleToken() {
    // Should panic - must provide at least 2 tokens
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex],  // Only 1 token
            0
        ]
    )
    Test.expect(result, Test.beFailed())
}

access(all) fun testProviderInitFailsWithNoRoutes() {
    // Should panic - must provide at least one route
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex],
            0  // No routes
        ]
    )
    Test.expect(result, Test.beFailed())
}

access(all) fun testProviderInitFailsWithUnconfiguredRouteToken() {
    // Should panic - route references token not in token config
    let result = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider_invalid_route.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex],  // Only WFLOW and TokenA
            Type<@TokenB.Vault>().identifier  // Route tries to use TokenB
        ]
    )
    Test.expect(result, Test.beFailed())
}

/* ==================== Swapper Retrieval Tests ==================== */

access(all) fun testGetSwapperReturnsConfiguredDirectRoute() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Create provider with WFLOW -> TokenA route
    let createResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex, tokenBHex],
            3
        ]
    )
    Test.expect(createResult, Test.beSucceeded())

    // Get swapper for WFLOW -> TokenA
    let getResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/get_swapper.cdc",
        [
            deployerAccount.address,
            Type<@FlowToken.Vault>().identifier,
            Type<@TokenA.Vault>().identifier
        ]
    )
    Test.expect(getResult, Test.beSucceeded())

    // Verify swapper exists and has correct types
    let hasSwapper = getResult.returnValue as! Bool
    Test.assert(hasSwapper, message: "Swapper should exist for configured route")
}

access(all) fun testGetSwapperReturnsNilForUnconfiguredPair() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Create provider with only WFLOW <-> TokenA routes
    let createResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider_limited.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex]  // Only 2 tokens
        ]
    )
    Test.expect(createResult, Test.beSucceeded())

    // Try to get swapper for TokenA -> TokenB (not configured)
    let getResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/get_swapper.cdc",
        [
            deployerAccount.address,
            Type<@TokenA.Vault>().identifier,
            Type<@TokenB.Vault>().identifier
        ]
    )
    Test.expect(getResult, Test.beSucceeded())

    let hasSwapper = getResult.returnValue as! Bool
    Test.assertEqual(false, hasSwapper)
}

access(all) fun testKeyGenerationIsConsistent() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Create provider
    let createResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex, tokenBHex],
            3
        ]
    )
    Test.expect(createResult, Test.beSucceeded())

    // Get swapper twice with same types
    let result1 = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/get_swapper.cdc",
        [
            deployerAccount.address,
            Type<@FlowToken.Vault>().identifier,
            Type<@TokenA.Vault>().identifier
        ]
    )

    let result2 = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/get_swapper.cdc",
        [
            deployerAccount.address,
            Type<@FlowToken.Vault>().identifier,
            Type<@TokenA.Vault>().identifier
        ]
    )

    Test.expect(result1, Test.beSucceeded())
    Test.expect(result2, Test.beSucceeded())

    // Both should return the same result
    let hasSwapper1 = result1.returnValue as! Bool
    let hasSwapper2 = result2.returnValue as! Bool
    Test.assertEqual(hasSwapper1, hasSwapper2)
}

/* ==================== ComponentInfo Tests ==================== */

access(all) fun testGetComponentInfoContainsAllInnerSwappers() {
    snapshot < getCurrentBlockHeight() ? Test.reset(to: snapshot) : nil

    // Create provider with 3 routes
    let createResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/create_provider.cdc",
        [
            deployerAccount.address,
            uniV3FactoryHex,
            uniV3RouterHex,
            uniV3QuoterHex,
            [wflowHex, tokenAHex, tokenBHex],
            3  // 3 routes
        ]
    )
    Test.expect(createResult, Test.beSucceeded())

    // Get component info
    let infoResult = _executeScript(
        "./scripts/uniswap-v3-swapper-provider/get_component_info.cdc",
        [deployerAccount.address]
    )
    Test.expect(infoResult, Test.beSucceeded())

    let innerComponentCount = infoResult.returnValue as! Int
    Test.assertEqual(3, innerComponentCount)
}

/* ==================== Helper Functions ==================== */
// Note: Helper functions like executeScript and executeTransaction are available from test_helpers.cdc
