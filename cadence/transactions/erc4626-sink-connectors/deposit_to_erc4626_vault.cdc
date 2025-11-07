import "FungibleToken"
import "FungibleTokenMetadataViews"
import "MetadataViews"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "ERC4626SinkConnectors"

/// Deposits the given amount of the asset token type to the given ERC4626 vault
///
/// @param amount: The amount of the deposit token type to deposit
/// @param assetVaultIdentifier: The identifier of the asset token type - must be the underlying token type of the
///     ERC4626 vault
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string - must be the address of the
///     ERC4626 vault
///
transaction(amount: UFix64, assetVaultIdentifier: String, erc4626VaultEVMAddressHex: String) {
    /// the funds to deposit to the recipient via the Sink
    let assets: @{FungibleToken.Vault}
    /// the Sink to deposit the funds to
    let sink: {DeFiActions.Sink}
    /// the capacity of the Sink
    let capacity: UFix64

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue, PublishCapability, UnpublishCapability) &Account) {
        // init the runtime type from the identifier & the ERC4626 EVM address from the hex string
        let assetVaultType = CompositeType(assetVaultIdentifier)
            ?? panic("Invalid deposit token identifier: \(assetVaultIdentifier)")
        let erc4626VaultEVMAddress = EVM.addressFromString(erc4626VaultEVMAddressHex)

        // get the signer's asset token Vault
        let assetVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: assetVaultIdentifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(assetVaultType.identifier)")
        let assetVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: assetVaultData.storagePath)
            ?? panic("Could not find FlowToken Vault in signer's storage at path \(assetVaultData.storagePath)")

        // get the COA capability to use for the AssetSink
        let coaPath = /storage/evm
        if signer.storage.type(at: coaPath) == nil {    
            // COA not found in standard path - create and publish a public unentitled capability
            signer.storage.save(<-EVM.createCadenceOwnedAccount(), to: coaPath)
            let coaCapability = signer.capabilities.storage.issue<&EVM.CadenceOwnedAccount>(coaPath)
            signer.capabilities.unpublish(/public/evm)
            signer.capabilities.publish(coaCapability, at: /public/evm)
        }
        // get the signer's COA capability
        let coa = signer.capabilities.storage.issue<auth(EVM.Call) &EVM.CadenceOwnedAccount>(coaPath)

        // create the fee source that pays the VM bridge fees
        let feeVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                /storage/flowTokenVault
            )
        let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: feeVault,
            uniqueID: nil
        )
        
        // create the asset Sink
        self.sink = ERC4626SinkConnectors.AssetSink(
            asset: assetVaultType,
            vault: erc4626VaultEVMAddress,
            coa: coa,
            feeSource: feeSource,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )

        // withdraw the funds from the signer's FlowToken Vault
        self.capacity = self.sink.minimumCapacity()
        let withdrawAmount = amount < self.capacity ? amount : self.capacity
        self.assets <- assetVault.withdraw(amount: withdrawAmount)
    }

    pre {
        self.assets.getType().identifier == assetVaultIdentifier:
        "Invalid asset type of \(self.assets.getType().identifier) - expected \(assetVaultIdentifier)"
        self.assets.balance == amount || (self.capacity <= amount && self.assets.balance == self.capacity):
        "Invalid asset balance of \(self.assets.balance) - expected \(amount) or \(self.capacity) (if capacity is less than requested amount)"
    }

    execute {
        // deposit the funds to the token Sink if there are any
        if self.assets.balance > 0.0 {
            self.sink.depositCapacity(from: &self.assets as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            assert(self.assets.balance == 0.0,
                message: "Expected 0.0 FLOW in signer's FlowToken Vault after deposit to Sink but found \(self.assets.balance)")
        }
        // destroy the empty Vault
        destroy self.assets
    }
}
