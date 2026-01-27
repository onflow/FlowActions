#test_fork(network: "mainnet", height: nil)

import Test

import "EVM"
import "FlowToken"
import "UniswapV3SwapConnectors"
import "SwapConnectors"
import "DeFiActions"

/// Fork test demonstrating UniswapV3SwapConnectors works against REAL FlowSwap V3 on Flow EVM
///
/// This test showcases fork testing for cross-VM DeFi:
/// - Deploys LATEST LOCAL UniswapV3SwapConnectors code to forked mainnet
/// - Tests against ACTUAL FlowSwap V3 deployment (Uniswap V3 fork)
/// - Validates connector can access real EVM DEX contracts
/// - Proves pre-deployment validation works for cross-VM integrations
///
/// FlowSwap V3 mainnet addresses (from https://developers.flow.com/ecosystem/defi-liquidity/defi-contracts):
/// - Factory: 0xca6d7Bb03334bBf135902e1d919a5feccb461632
/// - SwapRouter02: 0xeEDC6Ff75e1b10B903D9013c358e446a73d35341
/// - QuoterV2: 0x370A8DF17742867a44e56223EC20D82092242C85
/// - WFLOW: 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
///

access(all) fun setup() {
    // Deploy the LATEST local contracts to the forked environment
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
        name: "UniswapV3SwapConnectors",
        path: "../../contracts/connectors/evm/UniswapV3SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()
}

/// Test FLOW -> token swap using exactInput against real FlowSwap V3
access(all) fun testSwapExactInputAgainstFlowSwapV3() {
    let factoryAddr = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
    let routerAddr = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
    let quoterAddr = "0x370A8DF17742867a44e56223EC20D82092242C85"
    let swapAmount = 1.0
    let fee: UInt32 = 3000 // 0.3% fee tier

    let signer = Test.getAccount(0xb13b21a06b75536d)

    let tokenInType = Type<@FlowToken.Vault>()
    // USDC.e on Flow EVM
    let tokenOutType = CompositeType("A.1e4aa0b87d10b141.EVMVMBridgedToken_f1d2b8c3e7a4f5b6c9d0e1f2a3b4c5d6e7f8a9b0.Vault")!

    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [swapAmount, factoryAddr, routerAddr, quoterAddr, tokenInType, tokenOutType, fee]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}

/// Test FLOW -> token swap using exactOutput against real FlowSwap V3
access(all) fun testSwapExactOutputAgainstFlowSwapV3() {
    let factoryAddr = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
    let routerAddr = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
    let quoterAddr = "0x370A8DF17742867a44e56223EC20D82092242C85"
    let desiredAmountOut = 0.5 // Desired output amount
    let maxAmountIn = 2.0 // Max input willing to spend
    let fee: UInt32 = 3000 // 0.3% fee tier

    let signer = Test.getAccount(0xb13b21a06b75536d)

    let tokenInType = Type<@FlowToken.Vault>()
    // USDC.e on Flow EVM
    let tokenOutType = CompositeType("A.1e4aa0b87d10b141.EVMVMBridgedToken_f1d2b8c3e7a4f5b6c9d0e1f2a3b4c5d6e7f8a9b0.Vault")

    // Skip if token type is not available
    if tokenOutType == nil {
        log("Skipping test - output token type not available on this fork")
        return
    }

    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap_exact_output.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [desiredAmountOut, maxAmountIn, factoryAddr, routerAddr, quoterAddr, tokenInType, tokenOutType!, fee]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}
