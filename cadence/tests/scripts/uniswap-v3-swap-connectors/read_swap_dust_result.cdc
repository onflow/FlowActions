/// Reads a single swap dust test result stored at /storage/swapDustResult.
///
/// Result: [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
access(all)
fun main(addr: Address): [UFix64] {
    let account = getAuthAccount<auth(Storage) &Account>(addr)
    return account.storage.copy<[UFix64]>(from: /storage/swapDustResult) ?? []
}
