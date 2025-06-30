import "FungibleToken"
import "FungibleTokenMetadataViews"

import "DFB"
import "FungibleTokenStack"

/// An example transaction configuring a DeFiBlocks AutoBalancer with a rebalance Sink directing overflown value to the
/// signer's stored Vault
///
/// @param vaultIdentifier: the Vault type which the AutoBalancer contains. If `nil` the Source is set to `nil`
/// @param sourceMin: the optional minimum balance the VaultSink will allow
/// @param autoBalancerStoragePath: the storage path of the stored AutoBalancer
///
transaction(vaultIdentifier: String?, sourceMin: UFix64?, autoBalancerStoragePath: StoragePath) {

    var autoBalancer: auth(DFB.Set) &DFB.AutoBalancer
    var vaultSource: FungibleTokenStack.VaultSource?

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

            // get the Vault's authorized Capability and construct the VaultSource
            let withdrawVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                    vaultData.storagePath
                )
            assert(withdrawVault.check(),
                message: "Invalid authorized FungibleToken.Vault Capability issued against \(vaultData.storagePath) - ensure a Vault is configured at the expected path"
            )
            self.vaultSource = FungibleTokenStack.VaultSource(min: sourceMin, withdrawVault: withdrawVault, uniqueID: nil)
        } else {
            self.vaultSource = nil
        }

        // assign the AutoBalancer
        self.autoBalancer = signer.storage.borrow<auth(DFB.Set) &DFB.AutoBalancer>(from: autoBalancerStoragePath)
            ?? panic("AutoBalancer was not configured properly at \(autoBalancerStoragePath)")
    }

    execute {
        // Set the VaultSource as the AutoBalancer's rebalanceSource
        self.autoBalancer.setSource(self.vaultSource)
    }
}
