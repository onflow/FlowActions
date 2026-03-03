import "DeFiActions"

/// Schedules the next rebalance of the AutoBalancer stored at the specified path
///
/// @param storagePath: the storage path of the stored AutoBalancer
///
transaction(storagePath: StoragePath) {
    let autoBalancer: auth(DeFiActions.Schedule) &DeFiActions.AutoBalancer

    prepare(signer: auth(BorrowValue) &Account) {
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Schedule) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not found in signer's storage at \(storagePath)")
    }

    execute {
        if let err = self.autoBalancer.scheduleNextRebalance(whileExecuting: nil) {
            panic("Failed to schedule next rebalance: \(err)")
        }
    }
}
