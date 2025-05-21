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
        name: "AutoBalancerAdapter",
        path: "../contracts/adapters/AutoBalancerAdapter.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSetupSuccess() {
    log("AutoBalancerAdapter deployment success")
}
