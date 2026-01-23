import "DeFiActions"
import "EVMTokenConnectors"

/// Returns the ComponentInfo for EVMTokenConnectors.Source from storage
access(all) fun main(address: Address): DeFiActions.ComponentInfo {
    let source = getAuthAccount<auth(BorrowValue) &Account>(address)
        .storage.borrow<&EVMTokenConnectors.Source>(from: /storage/evmTokenSource)
        ?? panic("Could not borrow Source from storage")

    return source.getComponentInfo()
}