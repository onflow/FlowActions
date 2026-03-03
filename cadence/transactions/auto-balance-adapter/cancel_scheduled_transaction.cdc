import "FungibleToken"
import "FlowToken"
import "DeFiActions"
import "FlowTransactionScheduler"

/// Cancels a scheduled transaction for the AutoBalancer stored at the specified path
///
/// @param storagePath: the storage path of the stored AutoBalancer
/// @param id: the ID of the scheduled transaction to cancel
///
transaction(storagePath: StoragePath, id: UInt64) {
    let autoBalancer: auth(FlowTransactionScheduler.Cancel) &DeFiActions.AutoBalancer
    let refundReceiver: &{FungibleToken.Vault}

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // reference the AutoBalancer
        self.autoBalancer = signer.storage.borrow<auth(FlowTransactionScheduler.Cancel) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not found in signer's storage at \(storagePath)")
        // reference the refund receiver
        self.refundReceiver = signer.storage.borrow<&{FungibleToken.Vault}>(from: /storage/flowTokenVault)
            ?? panic("Refund receiver was not found in signer's storage at /storage/flowTokenVault")
    }

    execute {
        // cancel the scheduled transaction
        if let refund <- self.autoBalancer.cancelScheduledTransaction(id: id) as @{FungibleToken.Vault}? {
            self.refundReceiver.deposit(from: <-refund)
        }
    }
}
