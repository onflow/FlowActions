import Test
import BlockchainHelpers
import "test_helpers.cdc"

access(all)
fun setup() {
    setupIncrementFiDependencies()
}

access(all)
fun testSetupSucceeds() {
    log("SUCCESS")
}