import "DeFiActions"
import "ExecutionCallbackRecorder"

/// Test helper: creates an ExecutionCallbackRecorder, saves it, and sets it as the AutoBalancer's execution callback.
///
/// @param autoBalancerStoragePath: storage path of the AutoBalancer
///
transaction(autoBalancerStoragePath: StoragePath) {

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        let recorder <- ExecutionCallbackRecorder.createRecorder()
        signer.storage.save(<-recorder, to: /storage/autoBalancerExecutionCallback)
        let cap = signer.capabilities.storage.issue<&{DeFiActions.AutoBalancerExecutionCallback}>(/storage/autoBalancerExecutionCallback)
        let ab = signer.storage.borrow<auth(DeFiActions.Set) &DeFiActions.AutoBalancer>(from: autoBalancerStoragePath)
            ?? panic("AutoBalancer not found at \(autoBalancerStoragePath)")
        ab.setExecutionCallback(cap)
    }
}
