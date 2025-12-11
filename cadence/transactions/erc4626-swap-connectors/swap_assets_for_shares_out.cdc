import "FungibleToken"
import "FungibleTokenMetadataViews"
import "MetadataViews"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "ERC4626SwapConnectors"

/// Swaps the the asset token type via a ERC4626SwapConnectors.Swapper for the given amount of shares
///
/// @param amountIn: The amount of the asset token type to swap
/// @param maxIn: The maximum amount of shares to receive
/// @param assetVaultIdentifier: The identifier of the asset token type - must be the underlying token type of the
///     ERC4626 vault
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string - must be the address of the
///     ERC4626 vault
///
transaction(amountOut: UFix64, maxIn: UFix64, assetVaultIdentifier: String, erc4626VaultEVMAddressHex: String) {
    /// the funds to deposit to the recipient via the Sink
    let assets: @{FungibleToken.Vault}
    /// the Cadence type of the bridged ERC4626 shares
    let sharesType: Type
    /// the shares receiver to deposit the resulting shares to
    let sharesReceiver: &{FungibleToken.Receiver}
    /// the quote for the swap
    let quote: {DeFiActions.Quote}
    /// the Sink to deposit the funds to
    let swapper: {DeFiActions.Swapper}

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue, PublishCapability, UnpublishCapability) &Account) {
        // init the runtime type from the identifier & the ERC4626 EVM address from the hex string
        let assetVaultType = CompositeType(assetVaultIdentifier)
            ?? panic("Invalid deposit token identifier: \(assetVaultIdentifier)")
        let erc4626VaultEVMAddress = EVM.addressFromString(erc4626VaultEVMAddressHex)
        self.sharesType = FlowEVMBridgeConfig.getTypeAssociated(with: erc4626VaultEVMAddress)
            ?? panic("Provided ERC4626 Vault \(erc4626VaultEVMAddress.toString()) is not associated with a Cadence FungibleToken - ensure the type & ERC4626 contracts are associated via the VM bridge")

        // get the asset & shares Vault data
        let assetsVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: assetVaultIdentifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(assetVaultType.identifier)")
        let sharesVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: self.sharesType.identifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(self.sharesType.identifier)")
        let assetVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: assetsVaultData.storagePath)
            ?? panic("Could not find \(assetVaultIdentifier) Vault in signer's storage at path \(assetsVaultData.storagePath)")
        
        // configure a shares vault receiver
        if signer.storage.type(at: sharesVaultData.storagePath) == nil {
            // create and publish a public unentitled capability
            signer.storage.save(<-sharesVaultData.createEmptyVault(), to: sharesVaultData.storagePath)
            let sharesReceiverCapability = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(sharesVaultData.storagePath)
            signer.capabilities.unpublish(sharesVaultData.receiverPath)
            signer.capabilities.unpublish(sharesVaultData.metadataPath)
            signer.capabilities.publish(sharesReceiverCapability, at: sharesVaultData.receiverPath)
            signer.capabilities.publish(sharesReceiverCapability, at: sharesVaultData.metadataPath)
        }
        // reference the shares receiver from the signer's public capabilities
        self.sharesReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(sharesVaultData.receiverPath)
            ?? panic("Could not find \(self.sharesType.identifier) Receiver in signer's public path \(sharesVaultData.receiverPath)")

        // get the COA capability to use for the Swapper
        let coaPath = /storage/evm
        if signer.storage.type(at: coaPath) == nil {    
            // COA not found in standard path - create and publish a public unentitled capability
            signer.storage.save(<-EVM.createCadenceOwnedAccount(), to: coaPath)
            let coaCapability = signer.capabilities.storage.issue<&EVM.CadenceOwnedAccount>(coaPath)
            signer.capabilities.unpublish(/public/evm)
            signer.capabilities.publish(coaCapability, at: /public/evm)
        }
        // get the signer's COA capability
        let coa = signer.capabilities.storage.issue<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(coaPath)

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
        
        // create the Swapper
        self.swapper = ERC4626SwapConnectors.Swapper(
            asset: assetVaultType,
            vault: erc4626VaultEVMAddress,
            coa: coa,
            feeSource: feeSource,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )
        // get the quote for the swap given the exact amount out
        self.quote = self.swapper.quoteIn(forDesired: amountOut, reverse: false)
        let amount = self.quote.inAmount <= maxIn
            ? self.quote.inAmount
            : panic("Quoted in amount \(self.quote.inAmount) is greater than the maximum allowed \(maxIn)")

        // withdraw the funds from the signer's FlowToken Vault
        self.assets <- assetVault.withdraw(amount: amount)
        log("amount: \(amount)")
        log("self.quote.inAmount: \(self.quote.inAmount)")
        log("self.quote.outAmount: \(self.quote.outAmount)")
    }

    pre {
        self.assets.getType().identifier == assetVaultIdentifier:
        "Invalid asset type of \(self.assets.getType().identifier) - expected \(assetVaultIdentifier)"
        self.assets.balance <= maxIn:
        "Invalid asset balance of \(self.assets.balance) - expected to be less than or equal to \(maxIn)"
        self.swapper.inType() == self.assets.getType():
        "Invalid swapper inType of \(self.swapper.inType().identifier) - expected \(self.assets.getType().identifier)"
        self.swapper.outType() == self.sharesType:
        "Invalid swapper outType of \(self.swapper.outType().identifier) - expected \(self.sharesType.identifier)"
        self.sharesReceiver.isSupportedVaultType(type: self.sharesType):
        "Invalid shares receiver - \(self.sharesReceiver.getType().identifier) does not support \(self.sharesType.identifier)"
    }

    execute {
        let shares <- self.swapper.swap(quote: self.quote, inVault: <-self.assets)
        assert(shares.balance >= amountOut,
            message: "Expected \(self.sharesType.identifier) shares to be at least \(amountOut) but found \(shares.balance)")
        self.sharesReceiver.deposit(from: <-shares)
    }
}
