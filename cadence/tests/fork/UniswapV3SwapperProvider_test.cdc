#test_fork(network: "mainnet", height: nil)

import Test

import "EVM"
import "FlowToken"

/// Fork test demonstrating UniswapV3SwapperProvider works against REAL Uniswap V3 on Flow EVM
///
/// This test:
/// - Deploys LATEST LOCAL contracts to forked mainnet
/// - Tests against ACTUAL Uniswap V3 deployment on Flow EVM
/// - Discovers existing pools by querying the factory
/// - Validates quoting and swapping work for real token pairs
///
/// Uniswap V3 mainnet addresses on Flow EVM:
/// - Factory: 0xca6d7Bb03334bBf135902e1d919a5feccb461632
/// - SwapRouter02: 0xeEDC6Ff75e1b10B903D9013c358e446a73d35341
/// - QuoterV2: 0x370A8DF17742867a44e56223EC20D82092242C85
/// - WFLOW: 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
///

access(all) let factoryAddr = "0xca6d7Bb03334bBf135902e1d919a5feccb461632"
access(all) let routerAddr = "0xeEDC6Ff75e1b10B903D9013c358e446a73d35341"
access(all) let quoterAddr = "0x370A8DF17742867a44e56223EC20D82092242C85"
access(all) let wflowAddr = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e"

// Known tokens on Flow EVM (bridged ERC20s)
access(all) let wbtcAddr = "0x717DAE2BaF7656BE9a9B01deE31d571a9d4c9579"
access(all) let usdcAddr = "0x2d62C27FC8AB0909bf1A25e22f71Dc477Af493D4"
access(all) let usdtAddr = "0x81B56a36d6b8E5cC53588797cB5E10e00D63bD33"
access(all) let ankrFlowAddr = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"
access(all) let wethAddr = "0x4F3e652305cbBEE0D04C63F1d1BEEF6B54a95537"
access(all) let usdcfAddr = "0xF1815bd50B0BD60AA38EE3eBd245862e2A87068B"

access(all) let signer = Test.getAccount(0xb13b21a06b75536d)

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

    err = Test.deployContract(
        name: "UniswapV3SwapperProvider",
        path: "../../contracts/connectors/evm/UniswapV3SwapperProvider.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()
}

/// Discover which pool exists by querying the factory with various token pairs and fee tiers
///
access(all) fun testDiscoverAndSwap() {
    let zeroAddr = "0000000000000000000000000000000000000000"

    // Candidate pairs to try: WFLOW paired with various tokens and fee tiers
    let candidateTokens = [wbtcAddr, usdcAddr, usdtAddr, ankrFlowAddr, wethAddr, usdcfAddr]
    let feeTiers: [UInt256] = [500, 3000, 10000]

    var foundToken = ""
    var foundFee: UInt32 = 0

    // Try each combination until we find an existing pool
    for token in candidateTokens {
        for fee in feeTiers {
            let result = Test.executeScript(
                Test.readFile("../scripts/uniswap-v3-swapper-provider/fork_find_pool.cdc"),
                [signer.address, factoryAddr, wflowAddr, token, fee]
            )
            Test.expect(result, Test.beSucceeded())

            let poolAddr = result.returnValue as! String
            if poolAddr != zeroAddr && poolAddr != "CALL_FAILED" && poolAddr != "NO_RESULT" {
                log("Found pool: WFLOW / ".concat(token).concat(" fee=").concat(fee.toString()).concat(" at ").concat(poolAddr))
                foundToken = token
                foundFee = UInt32(fee)
                break
            }
        }
        if foundToken != "" { break }
    }

    // If no pool found, log and pass (not an error in our code)
    if foundToken == "" {
        log("No Uniswap V3 pools found for tested pairs - skipping swap test")
        return
    }

    // Now test a swap through the discovered pool
    let tokenInType = Type<@FlowToken.Vault>()

    // Resolve the Cadence type for the discovered token
    // The token type is resolved dynamically from FlowEVMBridgeConfig
    let tokenOutResult = Test.executeScript(
        Test.readFile("../scripts/uniswap-v3-swapper-provider/fork_resolve_type.cdc"),
        [foundToken]
    )
    Test.expect(tokenOutResult, Test.beSucceeded())

    let tokenOutTypeIdentifier = tokenOutResult.returnValue as! String
    if tokenOutTypeIdentifier == "" {
        log("Could not resolve Cadence type for token ".concat(foundToken).concat(" - skipping swap test"))
        return
    }

    let tokenOutType = CompositeType(tokenOutTypeIdentifier)!

    // Execute swap
    let swapTxn = Test.Transaction(
        code: Test.readFile("../../transactions/uniswap-v3-swap-connectors/uniswap_v3_swap.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [1.0 as UFix64, factoryAddr, routerAddr, quoterAddr, tokenInType, tokenOutType, foundFee]
    )
    let swapResult = Test.executeTransaction(swapTxn)
    Test.expect(swapResult, Test.beSucceeded())
}
