/// Reads swap dust test results stored at /storage/swapDustResults.
///
/// Each row: [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
access(all)
fun main(addr: Address): [[UFix64]] {
    let account = getAuthAccount<auth(Storage) &Account>(addr)
    return account.storage.load<[[UFix64]]>(from: /storage/swapDustResults) ?? []
}
