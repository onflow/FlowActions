import "DeFiActions"

///
/// Test-only contract: resource that implements AutoBalancerExecutionCallback
/// and emits an event so tests can assert the callback ran.
///
access(all) contract ExecutionCallbackRecorder {

    access(all) event Invoked(balancerUUID: UInt64)

    access(all) fun createRecorder(): @Recorder {
        return <- create Recorder()
    }

    access(all) resource Recorder: DeFiActions.AutoBalancerExecutionCallback {
        access(all) fun onExecuted(balancerUUID: UInt64) {
            emit Invoked(balancerUUID: balancerUUID)
        }
    }
}
