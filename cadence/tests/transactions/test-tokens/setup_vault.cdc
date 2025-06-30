import "FungibleToken"
import "ViewResolver"
import "FungibleTokenMetadataViews"

transaction(vaultIdentifier: String) {

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account) {
        let tokenType = CompositeType(vaultIdentifier) ?? panic("Invalid vaultIdentifier \(vaultIdentifier)")
        let contractAddress = tokenType.address ?? panic("Could not derive contract address from vaultIdentifier \(vaultIdentifier)")
        let contractName = tokenType.contractName ?? panic("Could not derive contract name from vaultIdentifier \(vaultIdentifier)")
        let tokenContract = getAccount(contractAddress).contracts.borrow<&{FungibleToken}>(name: contractName)
            ?? panic("Could not borrow Vault's contract \(contractName) from address \(contractAddress) - does not appear to be FungibleToken conformance")
        let vaultData = tokenContract.resolveContractView(resourceType: tokenType, viewType: Type<FungibleTokenMetadataViews.FTVaultData>())
            as! FungibleTokenMetadataViews.FTVaultData?
            ?? panic("Could not resolve FTVaultData for vaultIdentifier \(vaultIdentifier)")
        
        // return early if the account already stores something
        if signer.storage.type(at: vaultData.storagePath) != nil {
            return
        }

        // save the new Vault
        signer.storage.save(<-vaultData.createEmptyVault(), to: vaultData.storagePath)

        // publish public Capability
        var cap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(vaultData.storagePath)
        signer.capabilities.unpublish(vaultData.receiverPath)
        signer.capabilities.unpublish(vaultData.metadataPath)
        signer.capabilities.publish(cap, at: vaultData.receiverPath)
        signer.capabilities.publish(cap, at: vaultData.metadataPath)
    }
}
