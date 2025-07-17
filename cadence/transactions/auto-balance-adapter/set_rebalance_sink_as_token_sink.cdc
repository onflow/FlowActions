import "FungibleToken"
import "FungibleTokenMetadataViews"

import "DeFiActions"
import "FungibleTokenStack"

/// An example transaction configuring a DeFiActions AutoBalancer with a rebalance Sink directing overflown value to the
/// signer's stored Vault
///
/// @param vaultIdentifier: the Vault type which the AutoBalancer contains. If `nil` the Source is set to `nil`
/// @param sinkMax: the optional maximum balance the VaultSink will allow
/// @param autoBalancerStoragePath: the storage path of the stored AutoBalancer
///
transaction(vaultIdentifier: String?, sinkMax: UFix64?, autoBalancerStoragePath: StoragePath) {

    let autoBalancer: auth(DeFiActions.Set) &DeFiActions.AutoBalancer
    let vaultSink: FungibleTokenStack.VaultSink?

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability, UnpublishCapability) &Account) {
        if vaultIdentifier != nil {
            // get the Vault's default storage data from its defining contract
            let tokenType = CompositeType(vaultIdentifier!) ?? panic("Invalid vaultIdentifier \(vaultIdentifier!)")
            let contractAddress = tokenType.address ?? panic("Could not derive contract address from vaultIdentifier \(vaultIdentifier!)")
            let contractName = tokenType.contractName ?? panic("Could not derive contract name from vaultIdentifier \(vaultIdentifier!)")
            let tokenContract = getAccount(contractAddress).contracts.borrow<&{FungibleToken}>(name: contractName)
                ?? panic("Could not borrow Vault's contract \(contractName) from address \(contractAddress) - does not appear to be FungibleToken conformance")
            let vaultData = tokenContract.resolveContractView(resourceType: tokenType, viewType: Type<FungibleTokenMetadataViews.FTVaultData>())
                as! FungibleTokenMetadataViews.FTVaultData?
                ?? panic("Could not resolve FTVaultData for vaultIdentifier \(vaultIdentifier!)")

            // ensure a Vault is configured at the default path
            if signer.storage.type(at: vaultData.storagePath) == nil {
                // save the new Vault
                signer.storage.save(<-vaultData.createEmptyVault(), to: vaultData.storagePath)
                // publish public Capability
                var cap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(vaultData.storagePath)
                signer.capabilities.unpublish(vaultData.receiverPath)
                signer.capabilities.unpublish(vaultData.metadataPath)
                signer.capabilities.publish(cap, at: vaultData.receiverPath)
                signer.capabilities.publish(cap, at: vaultData.metadataPath)
            }

            // get the Vault's Capability and construct the VaultSink
            let depositVault = signer.capabilities.get<&{FungibleToken.Vault}>(vaultData.receiverPath)
            self.vaultSink = FungibleTokenStack.VaultSink(max: sinkMax, depositVault: depositVault, uniqueID: nil)
        } else {
            self.vaultSink = nil
        }

        // assign the AutoBalancer
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Set) &DeFiActions.AutoBalancer>(from: autoBalancerStoragePath)
            ?? panic("AutoBalancer was not configured properly at \(autoBalancerStoragePath)")
    }

    execute {
        // Set the VaultSink as the AutoBalancer's rebalanceSink
        self.autoBalancer.setSink(self.vaultSink)
    }
}
