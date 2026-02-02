import "DeFiActions"
import "EVMTokenConnectors"

/// Returns the ComponentInfo for EVMTokenConnectors.Sink from storage
access(all) fun main(address: Address, storagePath: StoragePath): DeFiActions.ComponentInfo {
    let sink = getAuthAccount<auth(BorrowValue) &Account>(address)
        .storage.borrow<&EVMTokenConnectors.Sink>(from: storagePath)
        ?? panic("Could not borrow Sink from storage")

    return sink.getComponentInfo()
}