import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"

access(all) let serviceAccount = Test.serviceAccount()

access(all) fun setup() {
    var err = Test.deployContract(
        name: "DFB",
        path: "../contracts/interfaces/DFB.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenStack",
        path: "../contracts/connectors/FungibleTokenStack.cdc",
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