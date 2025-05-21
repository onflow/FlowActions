import "FungibleToken"

access(all) contract TestTokenMinter {
    access(all) resource interface Minter {
        access(all) fun mintTokens(amount: UFix64): @{FungibleToken.Vault}
    }    
}