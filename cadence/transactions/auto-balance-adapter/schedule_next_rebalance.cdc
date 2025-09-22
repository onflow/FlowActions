import "DeFiActions"

/// Schedules the next rebalance of the AutoBalancer stored at the specified path
///
/// @param storagePath: the storage path of the stored AutoBalancer
///
transaction(storagePath: StoragePath) {
    let autoBalancer: auth(DeFiActions.Auto) &DeFiActions.AutoBalancer

    prepare(signer: auth(BorrowValue) &Account) {
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Auto) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not found in signer's storage at \(storagePath)")
    }

    execute {
        let err = self.autoBalancer.scheduleNextExecution(whileExecuting: nil)
        if err != nil {
            panic("Failed to schedule next rebalance: \(err!)")
        }
    }
}
