import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "TokenA"
import "EVM"
import "DeFiActions"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let bridgeAccount = Test.getAccount(0x0000000000000007)
access(all) let tokenAAccount = Test.getAccount(0x0000000000000010)
access(all) var tokenAERCAddress = ""

access(all) var wflowHex = ""

access(all) fun setup() {
    setupBridge(bridgeAccount: bridgeAccount, serviceAccount: serviceAccount, unpause: true)

    createCOA(serviceAccount, fundingAmount: 0.0)
    wflowHex = deployWFLOW(serviceAccount)
    createWFLOWHandler(bridgeAccount, wflowAddress: wflowHex)

    var err = Test.deployContract(
        name: "TestTokenMinter",
        path: "./contracts/TestTokenMinter.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "TokenA",
        path: "./contracts/TokenA.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    // onboard to the bridge
    let onboardResult = _executeTransaction(
        "./transactions/bridge/onboard_by_type_identifier.cdc",
        [Type<@TokenA.Vault>().identifier],
        tokenAAccount
    )
    Test.expect(onboardResult, Test.beSucceeded())
    // get the EVM address associated with the TokenA type
    tokenAERCAddress = getEVMAddressAssociated(withType: Type<@TokenA.Vault>().identifier)!

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
}

access(all) fun testSinkDepositFlowAsWFLOWSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 FLOW to the COA as WFLOW via the Sink
    let depositAmount = 10.0
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@FlowToken.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native balance of the COA
    let balance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(depositAmount, balance)
}

access(all) fun testSinkDepositFlowAsWFLOWWithMaxSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    let fundingAmount = 0.0
    createCOA(user, fundingAmount: fundingAmount)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 FLOW to the COA via the Sink which should result in a balance of 10 WFLOW on the COA
    let sinkMax = 10.0
    let surplus = 5.0
    let depositAmount = sinkMax + surplus
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [sinkMax, depositAmount, Type<@FlowToken.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native FLOW balance of the COA
    let balance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(sinkMax, balance)
}

access(all) fun testSinkDepositTokenASucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 1.0
    let tokenABalance = 100.0

    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    setupGenericVault(signer: user, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    mintTestTokens(signer: tokenAAccount, recipient: user.address, amount: tokenABalance, minterStoragePath: TokenA.AdminStoragePath, receiverPublicPath: TokenA.ReceiverPublicPath)

    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 TokenA to the COA via the Sink which should result in a balance of 10 TokenA on the COA
    let depositAmount = 10.0
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@TokenA.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native balance of the COA
    let balance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(depositAmount, balance)
}

access(all) fun testSinkDepositTokenAWithMaxSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 1.0
    let tokenABalance = 100.0

    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    setupGenericVault(signer: user, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    mintTestTokens(signer: tokenAAccount, recipient: user.address, amount: tokenABalance, minterStoragePath: TokenA.AdminStoragePath, receiverPublicPath: TokenA.ReceiverPublicPath)

    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 TokenA to the COA
    let sinkMax = 10.0
    let surplus = 5.0
    let depositAmount = sinkMax + surplus
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [sinkMax, depositAmount, Type<@TokenA.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native FLOW balance of the COA
    let balance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(sinkMax, balance)
}

access(all) fun testSourceWithdrawWFLOWAsFlowSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)

    var cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(cadenceBalance, flowBalance)

    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 FLOW to the COA as WFLOW via the Sink
    let depositAmount = flowBalance
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@FlowToken.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(cadenceBalance, 0.0)

    // get the WFLOW balance of the COA
    var wflowBalance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(depositAmount, wflowBalance)

    // withdraw 100 WFLOW from the COA as FLOW
    let withdrawAmount = depositAmount
    let withdrawResult = _executeTransaction(
        "../transactions/evm-token-connectors/withdraw_via_source.cdc",
        [nil, withdrawAmount, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the FLOW balance of the user
    cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(cadenceBalance, flowBalance)

    // get the WFLOW balance of the COA
    wflowBalance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(wflowBalance, 0.0)
}

access(all) fun testSourceWithdrawWFLOWAsFlowWithMinSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)

    // create a COA for the user
    let fundingAmount = 0.0
    createCOA(user, fundingAmount: fundingAmount)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 10 FLOW to the COA as WFLOW via the Sink
    let depositAmount = flowBalance
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@FlowToken.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the WFLOW balance of the COA
    var wflowBalance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(depositAmount, wflowBalance)

    // withdraw 10 FLOW from the COA as FLOW
    // TODO set minimum amount to 10.0 WFLOW
    let minAmount = 10.0
    let withdrawAmount = depositAmount
    let withdrawResult = _executeTransaction(
        "../transactions/evm-token-connectors/withdraw_via_source.cdc",
        [minAmount, withdrawAmount, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the FLOW balance of the user
    let cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(cadenceBalance, flowBalance - minAmount)

    // get the WFLOW balance of the COA
    wflowBalance = getEVMTokenBalance(of: recipient, erc20Address: wflowHex)
    Test.assertEqual(wflowBalance, minAmount)
}

access(all) fun testSourceWithdrawTokenASucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 1.0
    let tokenABalance = 100.0

    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    setupGenericVault(signer: user, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    mintTestTokens(signer: tokenAAccount, recipient: user.address, amount: tokenABalance, minterStoragePath: TokenA.AdminStoragePath, receiverPublicPath: TokenA.ReceiverPublicPath)

    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 100 TokenA to the COA as TokenA via the Sink
    let depositAmount = tokenABalance
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@TokenA.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the TokenA balance of the COA
    var evmTokenABalance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(depositAmount, evmTokenABalance)

    // withdraw 100 TokenA from the COA as TokenA
    let withdrawAmount = depositAmount
    let withdrawResult = _executeTransaction(
        "../transactions/evm-token-connectors/withdraw_via_source.cdc",
        [nil, withdrawAmount, Type<@TokenA.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the TokenA balance of the user
    let cadenceBalance = getBalance(address: user.address, vaultPublicPath: TokenA.ReceiverPublicPath)!
    Test.assertEqual(cadenceBalance, tokenABalance)

    // get the WTokenA balance of the COA
    evmTokenABalance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(evmTokenABalance, 0.0)
}

access(all) fun testSourceWithdrawTokenAWithMinSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 1.0
    let tokenABalance = 100.0

    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    setupGenericVault(signer: user, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    mintTestTokens(signer: tokenAAccount, recipient: user.address, amount: tokenABalance, minterStoragePath: TokenA.AdminStoragePath, receiverPublicPath: TokenA.ReceiverPublicPath)

    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)

    // deposit 100 TokenA to the COA as TokenA via the Sink
    let depositAmount = tokenABalance
    let depositResult = _executeTransaction(
        "../transactions/evm-token-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, Type<@TokenA.Vault>().identifier, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the TokenA balance of the COA
    var evmTokenABalance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(depositAmount, evmTokenABalance)

    // withdraw 100 TokenA from the COA as TokenA
    let minAmount = 10.0
    let withdrawAmount = depositAmount
    let withdrawResult = _executeTransaction(
        "../transactions/evm-token-connectors/withdraw_via_source.cdc",
        [minAmount, withdrawAmount, Type<@TokenA.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the TokenA balance of the user
    let cadenceBalance = getBalance(address: user.address, vaultPublicPath: TokenA.ReceiverPublicPath)!
    Test.assertEqual(cadenceBalance, tokenABalance - minAmount)

    // get the TokenA balance of the COA
    evmTokenABalance = getEVMTokenBalance(of: recipient, erc20Address: tokenAERCAddress)
    Test.assertEqual(evmTokenABalance, minAmount)
}