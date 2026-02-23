import "FungibleToken"

/// Cleans up test vault stored at /storage/testTokenInVault after test completion.
///
transaction() {
    prepare(signer: auth(Storage) &Account) {
        // Remove and destroy the test vault if it exists
        if let vault <- signer.storage.load<@{FungibleToken.Vault}>(from: /storage/testTokenInVault) {
            destroy vault
        }
    }
}
