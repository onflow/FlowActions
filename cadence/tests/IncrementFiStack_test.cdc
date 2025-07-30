import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "IncrementFiStack"
import "Staking"
import "TokenA"
import "SwapConfig"

access(all) let serviceAccount = Test.serviceAccount()

access(all) fun setup() {
    setupIncrementFiDependencies()

    var err = Test.deployContract(
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
        name: "IncrementFiStack",
        path: "../contracts/connectors/IncrementFiStack.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSource() {
    let user = Test.createAccount()

    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: 200.0,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    ) 

    let pid: UInt64 = 0
    let saveResult = executeTransaction(
        "../transactions/increment-fi-stack/save_pool_sink.cdc",
        [pid],
        user
    )
    Test.expect(saveResult.error, Test.beNil())

    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(1))

    let tokenStakedEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    Test.expect(
        tokenStakedEvent.tokenKey,
        Test.equal(SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier))
    )
    Test.expect(
        tokenStakedEvent.operator,
        Test.equal(user.address)
    )
    Test.expect(
        tokenStakedEvent.amount,
        Test.equal(200.0)
    )
    Test.expect(
        tokenStakedEvent.pid,
        Test.equal(pid)
    )
}