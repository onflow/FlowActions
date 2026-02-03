import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FlowToken"
import "DeFiActions"
import "EVM"
import "ERC4626Utils"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let deployerAccount = Test.createAccount()

access(all) var wflowHex = ""
access(all) var deployerCOAAddress = ""
access(all) var underlyingIdentifier = ""
access(all) var vaultIdentifier = ""

access(all) let initialAssets: UInt256 = 1_000_000_000_000_000_000_000 // 1_000.0 tokens at 18 decimals
access(all) var expectedInitialShares: UInt256 = initialAssets * 100 // 1_000.0 tokens at 20 decimals - decimals offset of 2
access(all) let uintDepositAmount: UInt256 = 10_000_000_000_000_000_000 // 100.0 tokens at 18 decimals
access(all) let ufixDepositAmount: UFix64 = 10.0

access(all) var vaultDeploymentInfo = MoreVaultDeploymentResult(
    wflow: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    underlying: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    stable: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    factory: EVM.addressFromString("0x0000000000000000000000000000000000000000"),
    vault: EVM.addressFromString("0x0000000000000000000000000000000000000000")
)

access(all) fun setup() {
    log("================== Setting up ERC4626SinkConnectors test ==================")
    wflowHex = getEVMAddressAssociated(withType: Type<@FlowToken.Vault>().identifier)!

    // TODO: remove this step once the VM bridge templates are updated for test env
    // see https://github.com/onflow/flow-go/issues/8184
    tempUpsertBridgeTemplateChunks(serviceAccount)

    // create deployer account and fund it
    transferFlow(signer: serviceAccount, recipient: deployerAccount.address, amount: 101.0)
    createCOA(deployerAccount, fundingAmount: 100.0)
    deployerCOAAddress = getCOAAddressHex(atFlowAddress: deployerAccount.address)

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
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "EVMTokenConnectors",
        path: "../contracts/connectors/evm/EVMTokenConnectors.cdc",
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
        name: "ERC4626SinkConnectors",
        path: "../contracts/connectors/evm/ERC4626SinkConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // mint 100.0 tokens of the underlying to the deployer account
    let mintCalldata = String.encodeHex(EVM.encodeABIWithSignature("mint(address,uint256)",
            [EVM.addressFromString(deployerCOAAddress), uintDepositAmount]
        ))
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.underlying.toString(),
        calldata: mintCalldata,
        gasLimit: 1000000,
        value: 0,
        beFailed: false
    )
    // bridge the asset tokens to the deployer account
    let bridgeRes = executeTransaction(
        "./transactions/bridge/bridge_tokens_from_evm.cdc",
        [underlyingIdentifier, uintDepositAmount],
        deployerAccount
    )
    Test.expect(bridgeRes, Test.beSucceeded())
}

access(all) fun testDepositToERC4626ViaSinkSucceeds() {
    let beforeShares = getEVMTokenBalance(of: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())

    let depositRes = executeTransaction(
        "../transactions/erc4626-sink-connectors/deposit_to_erc4626_vault.cdc",
        [ufixDepositAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()],
        deployerAccount
    )
    Test.expect(depositRes, Test.beSucceeded())

    let afterShares = getEVMTokenBalance(of: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    Test.assert(afterShares > beforeShares)
}

access(all) fun testDepositToPausedVaultRecoversGracefully() {
    // mint and bridge more tokens for this test (test 1 depleted the balance)
    let mintCalldata = String.encodeHex(EVM.encodeABIWithSignature("mint(address,uint256)",
            [EVM.addressFromString(deployerCOAAddress), uintDepositAmount]
        ))
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.underlying.toString(),
        calldata: mintCalldata,
        gasLimit: 1_000_000,
        value: 0,
        beFailed: false
    )
    let bridgeRes = executeTransaction(
        "./transactions/bridge/bridge_tokens_from_evm.cdc",
        [underlyingIdentifier, uintDepositAmount],
        deployerAccount
    )
    Test.expect(bridgeRes, Test.beSucceeded())

    let beforeShares = getEVMTokenBalance(of: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())

    // pause the ERC4626 vault
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.vault.toString(),
        calldata: String.encodeHex(EVM.encodeABIWithSignature("pause()", [])),
        gasLimit: 1_000_000,
        value: 0,
        beFailed: false
    )

    // attempt deposit to paused vault — should not panic
    let depositRes = _executeTransaction(
        "./transactions/erc4626-sink-connectors/deposit_to_paused_vault.cdc",
        [ufixDepositAmount, underlyingIdentifier, vaultDeploymentInfo.vault.toString()],
        deployerAccount
    )
    Test.expect(depositRes, Test.beSucceeded())

    // verify no shares were gained
    let afterShares = getEVMTokenBalance(of: deployerCOAAddress, erc20Address: vaultDeploymentInfo.vault.toString())
    Test.assertEqual(beforeShares, afterShares)

    // unpause the vault for cleanup
    evmCall(deployerAccount,
        target: vaultDeploymentInfo.vault.toString(),
        calldata: String.encodeHex(EVM.encodeABIWithSignature("unpause()", [])),
        gasLimit: 1_000_000,
        value: 0,
        beFailed: false
    )
}
