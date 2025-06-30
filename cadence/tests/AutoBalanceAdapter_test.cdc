import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "DFB"

import "TokenA"
import "TokenB"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let dfbAccount = Test.getAccount(0x0000000000000009)

access(all) let tokenAIdentifier: String = Type<@TokenA.Vault>().identifier // MockOracle's unitOfAccount
access(all) let tokenBIdentifier: String = Type<@TokenB.Vault>().identifier

access(all) let autoBalancerStoragePath = /storage/autoBalancerTest
access(all) let autoBalancerPublicPath = /public/autoBalancerTest

access(all) var snapshot: UInt64 = 0

access(all) fun setup() {
    var err = Test.deployContract(
        name: "DFBUtils",
        path: "../contracts/utils/DFBUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
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

    err = Test.deployContract(
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
    err = Test.deployContract(
        name: "TokenB",
        path: "./contracts/TokenB.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "MockOracle",
        path: "./contracts/MockOracle.cdc",
        arguments: [tokenAIdentifier], // unitOfAccountIdentifier
    )
    Test.expect(err, Test.beNil())

    // set TokenB price in MockOracle
    let setRes = executeTransaction(
        "./transactions/mock-oracle/set_price.cdc",
        [tokenBIdentifier, 2.0], // double the price of TokenA
        dfbAccount
    )
    Test.expect(setRes, Test.beSucceeded())

    snapshot = getCurrentBlockHeight()
}

access(all) fun test_SetupAutoBalancerSucceeds() {
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let evts = Test.eventsOfType(Type<DFB.CreatedAutoBalancer>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DFB.CreatedAutoBalancer
    Test.assertEqual(lowerThreshold, evt.lowerThreshold)
    Test.assertEqual(upperThreshold, evt.upperThreshold)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

access(all) fun test_SetRebalanceSinkSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let tokenBBalance = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)
    Test.assertEqual(0.0, tokenBBalance!)
}

access(all) fun test_SetRebalanceSourceSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    // setup user with TokenB Vault
    let vaultRes = executeTransaction(
            "./transactions/test-tokens/setup_vault.cdc",
            [tokenBIdentifier],
            user
        )
    Test.expect(vaultRes, Test.beSucceeded())

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_source_as_token_source.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setRes, Test.beSucceeded())

    let tokenBBalance = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)
    Test.assertEqual(0.0, tokenBBalance!)
}
