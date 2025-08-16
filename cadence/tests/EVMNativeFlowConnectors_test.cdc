import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "EVM"
import "EVMNativeFlowConnectors"
import "DeFiActions"

access(all) let serviceAccount = Test.serviceAccount()

access(all) fun setup() {
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
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "EVMNativeFlowConnectors",
        path: "../contracts/connectors/evm/EVMNativeFlowConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSinkDepositSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)
    
    // deposit 10 FLOW to the COA
    let depositAmount = 10.0
    let depositResult = _executeTransaction(
        "../transactions/evm-native-flow-connectors/deposit_via_sink.cdc",
        [nil, depositAmount, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native FLOW balance of the COA
    let balance = getEVMFlowBalance(recipient)
    Test.assertEqual(balance, depositAmount)
}

access(all) fun testSinkDepositWithMaxSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    let fundingAmount = 5.0
    createCOA(user, fundingAmount: fundingAmount)
    // get the EVM address of the COA
    let recipient = getCOAAddressHex(atFlowAddress: user.address)
    
    // deposit 10 FLOW to the COA
    let sinkMax = 10.0
    let surplus = 5.0
    let depositAmount = sinkMax + surplus
    let depositResult = _executeTransaction(
        "../transactions/evm-native-flow-connectors/deposit_via_sink.cdc",
        [sinkMax, depositAmount, recipient],
        user
    )
    Test.expect(depositResult, Test.beSucceeded())

    // get the EVM-native FLOW balance of the COA
    let balance = getEVMFlowBalance(recipient)
    Test.assertEqual(balance, sinkMax)
}

access(all) fun testSourceWithdrawSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    let fundingAmount = 10.0
    createCOA(user, fundingAmount: fundingAmount)

    // withdraw 10 FLOW from the COA
    let withdrawAmount = fundingAmount
    let withdrawResult = _executeTransaction(
        "../transactions/evm-native-flow-connectors/withdraw_via_source.cdc",
        [nil, withdrawAmount, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the FLOW balance of the user
    let balance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(balance, flowBalance - fundingAmount + withdrawAmount)
}

access(all) fun testSourceWithdrawWithMinSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    // create a COA for the user
    let fundingAmount = 10.0
    createCOA(user, fundingAmount: fundingAmount)

    // withdraw 10 FLOW from the COA
    let sourceMin = fundingAmount
    let withdrawAmount = sourceMin
    let withdrawResult = _executeTransaction(
        "../transactions/evm-native-flow-connectors/withdraw_via_source.cdc",
        [sourceMin, withdrawAmount, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // get the FLOW balance of the user
    let balance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(balance, flowBalance - fundingAmount)
}