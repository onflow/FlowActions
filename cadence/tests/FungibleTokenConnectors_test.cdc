import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"

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
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSink() {
    let user = Test.createAccount()
    let recipient = Test.createAccount()
 
    transferFlow(signer: serviceAccount, recipient: user.address, amount: 100.0)

    let saveResult = executeTransaction(
        "../transactions/fungible-token-stack/save_vault_sink.cdc",
        [recipient.address, /public/flowTokenReciever, StoragePath(identifier: "flowTokenVaultSink_\(recipient.address)")!, nil, nil],
        user
    )
}
