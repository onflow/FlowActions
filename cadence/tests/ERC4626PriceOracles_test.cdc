import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "DeFiActions"
import "EVM"
import "ERC4626PriceOracles"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let bridgeAccount = Test.getAccount(0x0000000000000007)
access(all) let deployerAccount = Test.createAccount()

access(all) var wflowHex = ""

access(all) let initialAssets: UInt256 = 1_000_000_000_000_000_000_000

access(all) fun setup() {
    // setup VM Bridge & configure WFLOW handler
    setupBridge(bridgeAccount: bridgeAccount, serviceAccount: serviceAccount, unpause: true)
    createCOA(serviceAccount, fundingAmount: 0.0)
    wflowHex = deployWFLOW(serviceAccount)
    createWFLOWHandler(bridgeAccount, wflowAddress: wflowHex)

    // create deployer account and fund it
    transferFlow(signer: serviceAccount, recipient: deployerAccount.address, amount: 101.0)
    createCOA(deployerAccount, fundingAmount: 100.0)

    var err = Test.deployContract(
        name: "EVMAbiHelpers",
        path: "../contracts/utils/EVMAbiHelpers.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // setup More Vaults & create a Minimal Vault
    setupMoreVaults(deployerAccount, wflow: EVM.addressFromString(wflowHex), initialAssets: initialAssets)
    
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
        name: "ERC4626Utils",
        path: "../contracts/utils/ERC4626Utils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "ERC4626PriceOracles",
        path: "../contracts/connectors/evm/ERC4626PriceOracles.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSetupSuccess() {
    log("ERC4626PriceOracles deployment success")
}
