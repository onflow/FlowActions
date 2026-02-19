import "FungibleToken"
import "MOET"

/// Mints MOET and saves directly to recipient's /storage/testTokenInVault for swap testing.
///
/// Since forked emulator doesn't verify signatures, the MOET deployer can be used
/// as signer to access the Minter resource.
///
/// Signer 1: MOET deployer (has the Minter at MOET.AdminStoragePath)
/// Signer 2: test recipient (where vault is saved)
///
transaction(amount: UFix64) {
    prepare(
        moetDeployer: auth(BorrowValue) &Account,
        recipient: auth(SaveValue, LoadValue) &Account
    ) {
        // Clean up any existing test vault
        if let existing <- recipient.storage.load<@{FungibleToken.Vault}>(from: /storage/testTokenInVault) {
            destroy existing
        }

        let minter = moetDeployer.storage.borrow<&MOET.Minter>(from: MOET.AdminStoragePath)
            ?? panic("Could not borrow MOET Minter from deployer at ".concat(MOET.AdminStoragePath.toString()))

        let vault <- minter.mintTokens(amount: amount)
        log("Minted ".concat(vault.balance.toString()).concat(" MOET to test vault"))
        recipient.storage.save(<-vault, to: /storage/testTokenInVault)
    }
}
