import "DeFiActions"
import "EVMTokenConnectors"

/// Returns the ComponentInfo for EVMTokenConnectors.Source from storage
access(all) fun main(address: Address, storagePath: StoragePath): DeFiActions.ComponentInfo {
    let source = getAuthAccount<auth(BorrowValue) &Account>(address)
        .storage.borrow<&EVMTokenConnectors.Source>(from: storagePath)
        ?? panic("Could not borrow Source from storage")

    return source.getComponentInfo()
}