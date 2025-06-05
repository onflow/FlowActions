import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "TokenA"
import "TokenB"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let adapterAccount = Test.getAccount(0x0000000000000007)
access(all) let bandOracleAccount = Test.getAccount(0x0000000000000007)

access(all) var tokenAIdentifier: String = ""
access(all) var tokenBIdentifier: String = ""

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
        name: "BandOracle",
        path: "../../imports/6801a6222ebf784a/BandOracle.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "BandOracleAdapters",
        path: "../contracts/adapters/BandOracleAdapters.cdc",
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

    // add price data to BandOracle contract
    let updateRes = executeTransaction(
        "./transactions/band-oracle/update_data.cdc",
        [{"A": UInt64(1500000000), "B": UInt64(3000000000)}],
        bandOracleAccount
    )
    Test.expect(updateRes, Test.beSucceeded())

    tokenAIdentifier = Type<@TokenA.Vault>().identifier
    tokenBIdentifier = Type<@TokenB.Vault>().identifier

    var symbolRes = executeTransaction(
            "../transactions/band-oracle-adapter/add_symbol.cdc",
            ["A", tokenAIdentifier],
            adapterAccount
        )
    Test.expect(symbolRes, Test.beSucceeded())
    symbolRes = executeTransaction(
            "../transactions/band-oracle-adapter/add_symbol.cdc",
            ["B", tokenBIdentifier],
            adapterAccount
        )
    Test.expect(symbolRes, Test.beSucceeded())
}

access(all) fun testSetupAutoBalancerSucceeds() {
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, /storage/autoBalancerTest, /public/autoBalancerTest],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())
}
