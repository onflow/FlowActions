import "DeFiActions"

/// Removes the recurring config for the AutoBalancer stored at the specified path
///
/// @param storagePath: the storage path of the stored AutoBalancer
///
transaction(storagePath: StoragePath) {
    let autoBalancer: auth(DeFiActions.Configure) &DeFiActions.AutoBalancer

    prepare(signer: auth(BorrowValue) &Account) {
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Configure) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not found in signer's storage at \(storagePath)")
    }

    execute {
        self.autoBalancer.setRecurringConfig(nil)
    }
}