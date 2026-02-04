import "FlowToken"
import "FungibleToken"
import "SwapFactory"

transaction(token0Identifier: String, token1Identifier: String, stableMode: Bool) {

    let accountCreationFeeVault: @FlowToken.Vault
    let token0Vault: @{FungibleToken.Vault}
    let token1Vault: @{FungibleToken.Vault}

    prepare(signer: auth(BorrowValue) &Account) {
        let flowVaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!
        assert(
            flowVaultRef.balance >= 0.002,
            message: "Insufficient balance to create pair, minimum balance requirement: 0.002 flow"
        )
        self.accountCreationFeeVault <- flowVaultRef.withdraw(amount: 0.001) as! @FlowToken.Vault
        
        /// e.g.: "A.1654653399040a61.FlowToken.Vault"
        let token0VaultType = CompositeType(token0Identifier) ?? panic("Invalid token0Vault type \(token1Identifier)")
        let token1VaultType = CompositeType(token1Identifier) ?? panic("Invalid token1Vault type \(token1Identifier)")
        assert(token0VaultType.isSubtype(of: Type<@{FungibleToken.Vault}>()),
            message: "Token0 \(token0Identifier) is not a FungibleToken Vault")
        assert(token1VaultType.isSubtype(of: Type<@{FungibleToken.Vault}>()),
            message: "Token1 \(token1Identifier) is not a FungibleToken Vault")
        self.token0Vault <- getAccount(token0VaultType.address!).contracts.borrow<&{FungibleToken}>(
                name: token0VaultType.contractName!
            )!.createEmptyVault(vaultType: token0VaultType)
        self.token1Vault <- getAccount(token1VaultType.address!).contracts.borrow<&{FungibleToken}>(
                name: token1VaultType.contractName!
            )!.createEmptyVault(vaultType: token1VaultType)
    }

    execute {
        let _ = SwapFactory.createPair(
            token0Vault: <-self.token0Vault,
            token1Vault: <-self.token1Vault,
            accountCreationFee: <-self.accountCreationFeeVault,
            stableMode: stableMode
        )
    }
}