import "DeFiActions"
import "ExecutionCallbackRecorder"

/// Test helper: creates an ExecutionCallbackRecorder, saves it, and publishes
/// it at DeFiActions.executionCallbackPublicPath() so the AutoBalancer can
/// discover it dynamically at execution time.
///
transaction() {

    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability, UnpublishCapability) &Account) {
        let recorder <- ExecutionCallbackRecorder.createRecorder()
        signer.storage.save(<-recorder, to: /storage/autoBalancerExecutionCallback)

        let publicPath = DeFiActions.executionCallbackPublicPath()
        let _ = signer.capabilities.unpublish(publicPath)
        let cap = signer.capabilities.storage.issue<&{DeFiActions.AutoBalancerExecutionCallback}>(
            /storage/autoBalancerExecutionCallback
        )
        signer.capabilities.publish(cap, at: publicPath)
    }
}
