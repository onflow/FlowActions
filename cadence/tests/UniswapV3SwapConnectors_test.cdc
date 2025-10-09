import Test
import BlockchainHelpers
import "test_helpers.cdc"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let bridgeAccount = Test.getAccount(0x0000000000000007)

access(all) let uniV2DeployerAccount = Test.createAccount()
access(all) var uniV2DeployerCOAHex = ""

access(all) var tokenAHex = ""
access(all) var tokenBHex = ""
access(all) var wflowHex = ""
access(all) var uniV2RouterHex = ""

access(all)
fun setup() {
    setupBridge(bridgeAccount: bridgeAccount, serviceAccount: serviceAccount, unpause: true)
    
    transferFlow(signer: serviceAccount, recipient: uniV2DeployerAccount.address, amount: 10.0)
    createCOA(uniV2DeployerAccount, fundingAmount: 1.0)

    wflowHex = deployWFLOW(uniV2DeployerAccount)
    createWFLOWHandler(bridgeAccount, wflowAddress: wflowHex)    
    
    uniV2DeployerCOAHex = getCOAAddressHex(atFlowAddress: uniV2DeployerAccount.address)

    uniV2RouterHex = setupUniswapV2(uniV2DeployerAccount, feeToSetter: uniV2DeployerCOAHex, wflowAddress: wflowHex)

    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActionsMathUtils",
        path: "../contracts/utils/DeFiActionsMathUtils.cdc",
        arguments: [],
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
}

access(all)
fun testSetupSucceeds() {
    log("UniswapV3SwapConnectors deployment success")
}
