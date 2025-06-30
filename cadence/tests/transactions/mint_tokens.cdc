import "FungibleToken"
import "TestTokenMinter"
import "FungibleTokenMetadataViews"

/// TEST SUITE TRANSACTION
///
/// This transaction mints using the signer's TestTokenMinter.Minter
///
transaction(recipient: Address, amount: UFix64, minterStoragePath: StoragePath, receiverPublicPath: PublicPath) {

    let tokenMinter: &{TestTokenMinter.Minter}
    let tokenReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue) &Account) {
        self.tokenMinter = signer.storage.borrow<&{TestTokenMinter.Minter}>(from: minterStoragePath)
            ?? panic("Signer does not have a TestTokenMinter.Minter conforming resource at \(minterStoragePath)")

        // let contractAddress = self.tokenMinter.getType().address!
        // let contractName = self.tokenMinter.getType().contractName!
        // let vaultData = getAccount(contractAddress).contracts.borrow<&{FungibleToken}>(name: contractName)!
        //     .resolveContractView(
        //         resourceType: nil,
        //         viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        //     ) as! FungibleTokenMetadataViews.FTVaultData?
        //     ?? panic("Could not get vault data view for the contract")
    
        self.tokenReceiver = getAccount(recipient).capabilities.borrow<&{FungibleToken.Receiver}>(receiverPublicPath)
            ?? panic("Could not borrow receiver reference to the Vault")
    }

    execute {
        self.tokenReceiver.deposit(
            from: <- self.tokenMinter.mintTokens(amount: amount)
        )
    }
}