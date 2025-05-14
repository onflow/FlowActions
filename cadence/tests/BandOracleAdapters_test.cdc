import Test
import BlockchainHelpers
import "test_helpers.cdc"

access(all) let serviceAccount = Test.serviceAccount()

access(all) fun setup() {
    var err = Test.deployContract(
        name: "DFB",
        path: "../contracts/interfaces/DFB.cdc",
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
}

access(all) fun testSetupSuccess() {
    log("BandOracleAdapters deployment success")
}
