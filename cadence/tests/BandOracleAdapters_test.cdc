import Test
import BlockchainHelpers
import "test_helpers.cdc"

access(all) let serviceAccount = Test.serviceAccount()

access(all) fun setup() {
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
        name: "BandOracle",
        path: "../../imports/6801a6222ebf784a/BandOracle.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "BandOracleConnectors",
        path: "../contracts/connectors/band-oracle/BandOracleConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSetupSuccess() {
    log("BandOracleConnectors deployment success")
}
