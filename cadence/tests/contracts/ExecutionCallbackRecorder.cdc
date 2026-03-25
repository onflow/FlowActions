import "DeFiActions"

///
/// Test-only contract: resource that implements AutoBalancerExecutionCallback
/// and emits an event so tests can assert the callback ran.
///
access(all) contract ExecutionCallbackRecorder {

    access(all) event Invoked(resourceUUID: UInt64, uniqueID: UInt64?)

    access(all) fun createRecorder(): @Recorder {
        return <- create Recorder()
    }

    access(all) resource Recorder: DeFiActions.AutoBalancerExecutionCallback {
        access(all) fun onExecuted(resourceUUID: UInt64, uniqueID: UInt64?) {
            emit Invoked(resourceUUID: resourceUUID, uniqueID: uniqueID)
        }
    }
}
