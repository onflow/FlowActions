import "DeFiActions"
import "EVMTokenConnectors"

/// Returns the ComponentInfo for EVMTokenConnectors.Sink from storage
access(all) fun main(address: Address): DeFiActions.ComponentInfo {
    let sink = getAuthAccount<auth(BorrowValue) &Account>(address)
        .storage.borrow<&EVMTokenConnectors.Sink>(from: /storage/evmTokenSink)
        ?? panic("Could not borrow Sink from storage")

    return sink.getComponentInfo()
}