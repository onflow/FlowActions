#test_fork(network: "mainnet", height: nil)

import Test

/// Backward-compatibility fork test.
///
/// Redeploys every FlowActions contract that has a mainnet deployment on top of
/// the live mainnet fork state. A successful setup() proves that all local
/// contract sources are upgrade-compatible with the current on-chain state.

access(all) fun setup() {
    log("==== FlowActions Backward-Compatibility Redeploy Test ====")

    // DeFiActionsUtils — no FlowActions deps
    log("Deploying DeFiActionsUtils...")
    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../../contracts/utils/DeFiActionsUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // DeFiActions — imports DeFiActionsUtils
    log("Deploying DeFiActions...")
    err = Test.deployContract(
        name: "DeFiActions",
        path: "../../contracts/interfaces/DeFiActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // SwapConnectors — imports DeFiActions
    log("Deploying SwapConnectors...")
    err = Test.deployContract(
        name: "SwapConnectors",
        path: "../../contracts/connectors/SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // EVMAbiHelpers — no FlowActions deps
    log("Deploying EVMAbiHelpers...")
    err = Test.deployContract(
        name: "EVMAbiHelpers",
        path: "../../contracts/utils/EVMAbiHelpers.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // EVMAmountUtils — imports EVMAbiHelpers
    log("Deploying EVMAmountUtils...")
    err = Test.deployContract(
        name: "EVMAmountUtils",
        path: "../../contracts/connectors/evm/EVMAmountUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // FungibleTokenConnectors — imports DeFiActions
    log("Deploying FungibleTokenConnectors...")
    err = Test.deployContract(
        name: "FungibleTokenConnectors",
        path: "../../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // EVMTokenConnectors — imports DeFiActions, EVMAmountUtils
    log("Deploying EVMTokenConnectors...")
    err = Test.deployContract(
        name: "EVMTokenConnectors",
        path: "../../contracts/connectors/evm/EVMTokenConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // EVMNativeFLOWConnectors — imports DeFiActions, EVMAmountUtils
    log("Deploying EVMNativeFLOWConnectors...")
    err = Test.deployContract(
        name: "EVMNativeFLOWConnectors",
        path: "../../contracts/connectors/evm/EVMNativeFLOWConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // UniswapV2SwapConnectors — imports DeFiActions, SwapConnectors, EVMAmountUtils
    log("Deploying UniswapV2SwapConnectors...")
    err = Test.deployContract(
        name: "UniswapV2SwapConnectors",
        path: "../../contracts/connectors/evm/UniswapV2SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // UniswapV3SwapConnectors — imports DeFiActions, SwapConnectors, EVMAbiHelpers, EVMAmountUtils
    log("Deploying UniswapV3SwapConnectors...")
    err = Test.deployContract(
        name: "UniswapV3SwapConnectors",
        path: "../../contracts/connectors/evm/UniswapV3SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // ERC4626Utils — imports EVMAbiHelpers, EVMAmountUtils
    log("Deploying ERC4626Utils...")
    err = Test.deployContract(
        name: "ERC4626Utils",
        path: "../../contracts/utils/ERC4626Utils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // ERC4626SwapConnectors — imports DeFiActions, SwapConnectors, ERC4626Utils, EVMAmountUtils
    log("Deploying ERC4626SwapConnectors...")
    err = Test.deployContract(
        name: "ERC4626SwapConnectors",
        path: "../../contracts/connectors/evm/ERC4626SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // ERC4626SinkConnectors — imports DeFiActions, ERC4626Utils, EVMAmountUtils
    log("Deploying ERC4626SinkConnectors...")
    err = Test.deployContract(
        name: "ERC4626SinkConnectors",
        path: "../../contracts/connectors/evm/ERC4626SinkConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // ERC4626PriceOracles — imports DeFiActions, ERC4626Utils
    log("Deploying ERC4626PriceOracles...")
    err = Test.deployContract(
        name: "ERC4626PriceOracles",
        path: "../../contracts/connectors/evm/ERC4626PriceOracles.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // MorphoERC4626SwapConnectors — imports ERC4626SwapConnectors, SwapConnectors
    log("Deploying MorphoERC4626SwapConnectors...")
    err = Test.deployContract(
        name: "MorphoERC4626SwapConnectors",
        path: "../../contracts/connectors/evm/morpho/MorphoERC4626SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // MorphoERC4626SinkConnectors — imports ERC4626SinkConnectors
    log("Deploying MorphoERC4626SinkConnectors...")
    err = Test.deployContract(
        name: "MorphoERC4626SinkConnectors",
        path: "../../contracts/connectors/evm/morpho/MorphoERC4626SinkConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    // BandOracleConnectors — imports DeFiActions
    log("Deploying BandOracleConnectors...")
    err = Test.deployContract(
        name: "BandOracleConnectors",
        path: "../../contracts/connectors/band-oracle/BandOracleConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    Test.commitBlock()

    log("==== All FlowActions contracts redeployed successfully ====")
}

access(all) fun testAllContractsRedeployedWithoutError() {
    log("All FlowActions contracts redeployed without error (verified in setup)")
}
