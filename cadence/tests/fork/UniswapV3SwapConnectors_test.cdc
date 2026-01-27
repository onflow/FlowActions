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

// FlowSwap V3 addresses (from https://developers.flow.com/ecosystem/defi-liquidity/defi-contracts):
access(all) let FACTORY_ADDR = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
access(all) let ROUTER_ADDR = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
access(all) let QUOTER_ADDR = "0x370A8DF17742867a44e56223EC20D82092242C85"

// USDC on Flow EVM: 0xF1815bd50389c46847f0Bda824eC8da914045D14
// Flow EVM bridge mainnet: 1e4aa0b87d10b141
// Type identifier: A.<bridge_address>.EVMVMBridgedToken_<evm_token_address_lowercase>.Vault
access(all) let USDC_TYPE_ID = "A.1e4aa0b87d10b141.EVMVMBridgedToken_f1815bd50389c46847f0bda824ec8da914045d14.Vault"

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

/// Test FLOW -> USDC swap using exactInput against real FlowSwap V3
access(all) fun testSwapExactInputAgainstFlowSwapV3() {
    let swapAmount = 0.1 // Small amount to test (0.1 FLOW)
    let fee: UInt32 = 3000 // 0.3% fee tier

    let signer = Test.getAccount(0xb13b21a06b75536d)

    let tokenInType = Type<@FlowToken.Vault>()
    let tokenOutType = CompositeType(USDC_TYPE_ID)!

    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [swapAmount, FACTORY_ADDR, ROUTER_ADDR, QUOTER_ADDR, tokenInType, tokenOutType, fee]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}

/// Test FLOW -> USDC swap using exactOutput against real FlowSwap V3
access(all) fun testSwapExactOutputAgainstFlowSwapV3() {
    let desiredAmountOut = 0.001 // Desired output amount (0.001 USDC)
    let maxAmountIn = 10.0 // Max input willing to spend (10 FLOW)
    let fee: UInt32 = 3000 // 0.3% fee tier

    let signer = Test.getAccount(0xb13b21a06b75536d)

    let tokenInType = Type<@FlowToken.Vault>()
    let tokenOutType = CompositeType(USDC_TYPE_ID)!

    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap_exact_output.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [desiredAmountOut, maxAmountIn, FACTORY_ADDR, ROUTER_ADDR, QUOTER_ADDR, tokenInType, tokenOutType, fee]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}
