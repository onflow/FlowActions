import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "DeFiActions"
import "EVM"
import "ERC4626Utils"
import "ERC4626PriceOracles"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let bridgeAccount = Test.getAccount(0x0000000000000007)
access(all) let deployerAccount = Test.createAccount()

access(all) var wflowHex = ""
access(all) var underlyingIdentifier = ""
access(all) var vaultIdentifier = ""

access(all) let initialAssets: UInt256 = 1_000_000_000_000_000_000_000 // 1_000.0 tokens at 18 decimals
access(all) var expectedInitialShares: UInt256 = 100_000_0000000000_0000000000 // 100_000.0 tokens at 20 decimals

access(all) var vaultDeploymentInfo = MoreVaultDeploymentResult(
    wflow: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    underlying: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    stable: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    factory: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    vault: EVM.addressFromString("0x0000000000000000000000000000000000000000")
)

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
    let price = executeScript(
        "../scripts/erc4626-price-oracles/price.cdc",
        [vaultDeploymentInfo.vault.toString(), underlyingIdentifier]
    )
    Test.expect(price, Test.beSucceeded())
    let priceValue = price.returnValue as! UFix64
    // For initial deposit: assets = 1e24, shares = 1e24 * 100 = 1e26, price = assets/shares = 0.01
    let expectedPrice = 0.01
    Test.assert(priceValue == expectedPrice, message: "Price should be \(expectedPrice) for initial deposit")
}
