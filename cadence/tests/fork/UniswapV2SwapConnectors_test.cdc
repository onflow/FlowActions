#test_fork(network: "mainnet", height: nil)

import Test

import "EVM"
import "FlowToken"
import "UniswapV2SwapConnectors"

/// Fork test demonstrating UniswapV2SwapConnectors works against REAL PunchSwap V2 on Flow EVM
///
/// This test showcases fork testing for cross-VM DeFi:
/// - Deploys LATEST LOCAL UniswapV2SwapConnectors code to forked mainnet
/// - Tests against ACTUAL PunchSwap V2 deployment (KittyPunch's Uniswap V2 fork)
/// - Validates connector can access real EVM DEX contracts
/// - Proves pre-deployment validation works for cross-VM integrations
///
/// PunchSwap V2 mainnet addresses (from https://kittypunch.gitbook.io/kittypunch-docs/protocols-and-products-flow/punchswap):
/// - Router: 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d
/// - Factory: 0x29372c22459a4e373851798bFd6808e71EA34A71
/// - WFLOW: 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
/// - WBTC: 0x717DAE2BaF7656BE9a9B01deE31d571a9d4c9579
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
        name: "UniswapV2SwapConnectors",
        path: "../../contracts/connectors/evm/UniswapV2SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()
}

/// Test FLOW → WBTC swap against real PunchSwap V2 using type-safe Cadence Types
/// The transaction accepts Cadence Types and resolves EVM addresses via FlowEVMBridgeConfig
///
access(all) fun testSwapAgainstPunchSwapV2() {
    let routerAddr = "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d"
    let swapAmount = 1.0
    let signer = Test.getAccount(0xb13b21a06b75536d)
    
    let tokenInType = Type<@FlowToken.Vault>()
    let tokenOutType = CompositeType("A.1e4aa0b87d10b141.EVMVMBridgedToken_717dae2baf7656be9a9b01dee31d571a9d4c9579.Vault")!
    
    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v2-swap-connectors/uniswap_v2_swap.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [swapAmount, routerAddr, tokenInType, tokenOutType]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}
