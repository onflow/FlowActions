import "EVM"

/// Returns true if the given address has a COA at /storage/evm
///
access(all)
fun main(address: Address): Bool {
    let account = getAuthAccount<auth(Storage) &Account>(address)
    return account.storage.type(at: /storage/evm) != nil
}

