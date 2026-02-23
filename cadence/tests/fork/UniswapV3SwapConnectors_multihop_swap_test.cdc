#test_fork(network: "mainnet", height: 142038853)

import Test
import "FlowToken"

/// Tests against FlowSwap V3 on Flow Testnet (from https://developers.flow.com/defi/defi-contracts-testnet):
access(all) let UniswapV3Factory  = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
access(all) let SwapRouter02 = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
access(all) let QuoterV2 = "0x370A8DF17742867a44e56223EC20D82092242C85"

// Flow EVM bridge mainnet: 1e4aa0b87d10b141
// Type identifier: A.<bridge_address>.EVMVMBridgedToken_<evm_token_address_lowercase>.Vault

// WBTC on Flow EVM: 717dae2baf7656be9a9b01dee31d571a9d4c9579
access(all) let WBTC_TYPE_ID = "A.1e4aa0b87d10b141.EVMVMBridgedToken_717dae2baf7656be9a9b01dee31d571a9d4c9579.Vault"
// WETH on Flow EVM - 2f6f07cdcf3588944bf4c42ac74ff24bf56e7590
access(all) let WETH_TYPE_ID= "A.1e4aa0b87d10b141.EVMVMBridgedToken_2f6f07cdcf3588944bf4c42ac74ff24bf56e7590.Vault"
// USDF (USD Flow) on Flow EVM - 2aabea2058b5ac2d339b163c6ab6f2b6d53aabed
access(all) let USDF_TYPE_ID = "A.1e4aa0b87d10b141.EVMVMBridgedToken_2aabea2058b5ac2d339b163c6ab6f2b6d53aabed.Vault"

access(all) let WBTC_STORAGE_PATH=/storage/EVMVMBridgedToken_717dae2baf7656be9a9b01dee31d571a9d4c9579Vault
access(all) let USDF_STORAGE_PATH=/storage/EVMVMBridgedToken_2aabea2058b5ac2d339b163c6ab6f2b6d53aabedVault

access(all) let WBTC_PUBLIC_PATH=/public/EVMVMBridgedToken_717dae2baf7656be9a9b01dee31d571a9d4c9579Receiver
access(all) let USDF_PUBLIC_PATH=/public/EVMVMBridgedToken_2aabea2058b5ac2d339b163c6ab6f2b6d53aabedReceiver

/// Deploys all required contracts for the UniswapV3SwapConnectors test suite.
access(all) fun setup() {
    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
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

// testMultiHopSwapExecution tests suite validates multi-hop swap functionality using Uniswap V3
// on Flow EVM. It forks Flow mainnet at a specific block height to test
// against real on-chain state and liquidity pools.
//
// Test Account: 0x47f544294e3b7656 (WBTC holder on mainnet)
// Swap Path: WBTC → WETH → USDF (2-hop swap)
access(all) fun testMultiHopSwapExecution() {
    // 0x47f544294e3b7656 - WBTC holder
    let signer = Test.getAccount(0x47f544294e3b7656)
    let amount = 0.0001

    let USDF = CompositeType(USDF_TYPE_ID)!
    let WETH = CompositeType(WETH_TYPE_ID)!
    let WBTC = CompositeType(WBTC_TYPE_ID)!
    
    let tokenPath: [Type] = [WBTC, WETH, USDF]
    let feePath: [UInt32] = [3000, 3000]

    // First, setup the output vault for USDF
    var setupVaultTxn = Test.Transaction(
        code: Test.readFile("../../transactions/fungible-tokens/setup_generic_vault.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [USDF_TYPE_ID]
    )
    var setupResult = Test.executeTransaction(setupVaultTxn)
    Test.expect(setupResult, Test.beSucceeded())

    let WBTCBalanceBefore = getBalance(address: signer.address, vaultPublicPath: WBTC_PUBLIC_PATH)!
    let USDFBalanceBefore: UFix64 = getBalance(address: signer.address, vaultPublicPath: USDF_PUBLIC_PATH)!

    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/evm/uniswap-v3-swap-connectors/uniswap_v3_swap.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [
            amount,
            UniswapV3Factory,
            SwapRouter02,
            QuoterV2,
            tokenPath,
            feePath,
            WBTC_STORAGE_PATH,
            USDF_STORAGE_PATH
        ]
    )

    let result = Test.executeTransaction(swapTxn)
    Test.expect(result, Test.beSucceeded())

    let WBTCBalanceAfter = getBalance(address: signer.address, vaultPublicPath: WBTC_PUBLIC_PATH)!
    let USDFBalanceAfter = getBalance(address: signer.address, vaultPublicPath: USDF_PUBLIC_PATH)!

    let WBTCSpent = WBTCBalanceBefore - WBTCBalanceAfter
    Test.assert(WBTCSpent >= amount, message: "Spent less WBTC than expected! Spent: \(WBTCSpent), expected at least: \(amount)")
    log("WBTC spent: \(WBTCSpent)")

    let usdcReceived = USDFBalanceAfter - USDFBalanceBefore
    Test.assert(usdcReceived > 0.0, message: "No USDC received from swap! Balance before: \(USDFBalanceBefore), after: \(USDFBalanceAfter)")
    log("USDC received: \(usdcReceived)")
}

/// getBalance retrieves the balance of a fungible token vault via its public capability.
access(all)
fun getBalance(address: Address, vaultPublicPath: PublicPath): UFix64? {
    let res = Test.executeScript(Test.readFile("../../scripts/tokens/get_balance.cdc"), [address, vaultPublicPath])
    Test.expect(res, Test.beSucceeded())
    return res.returnValue as! UFix64?
}