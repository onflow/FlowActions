import "DeFiActions"

/// Rebalances the AutoBalancer stored at the specified path, forcing as defined
///
/// @param storagePath: the storage path of the stored AutoBalancer
/// @param force: whether to force the rebalance or not. If `true`, the AutoBalancer will balance regardless of the
///     configured upper/lower thresholds (assuming it has been configured with the appropriate 
///     rebalanceSink/rebalanceSource). If `false`, the AutoBalancer will only rebalance if the relative value
///     thresholds have been met.
///
transaction(storagePath: StoragePath, force: Bool) {
    
    let autoBalancer: auth(DeFiActions.Auto) &DeFiActions.AutoBalancer

    prepare(signer: auth(BorrowValue) &Account) {
        // assign the AutoBalancer
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Auto) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not configured properly at \(storagePath)")
    }

    execute {
        self.autoBalancer.rebalance(force: force)
    }
}
