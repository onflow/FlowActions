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

/// Test transaction that attempts to deposit to a paused ERC4626 vault. When the vault is paused, either:
/// - minimumCapacity() returns 0 (if maxDeposit is guarded by pause) → no-op, balance unchanged
/// - deposit() reverts → recovery bridges tokens back, balance approximately unchanged
///
/// In both cases the transaction succeeds without panic and no shares are gained.
///
transaction(amount: UFix64, assetVaultIdentifier: String, erc4626VaultEVMAddressHex: String) {
    let assetVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let sink: {DeFiActions.Sink}
    let beforeBalance: UFix64

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue, PublishCapability, UnpublishCapability) &Account) {
        let assetVaultType = CompositeType(assetVaultIdentifier)
            ?? panic("Invalid deposit token identifier: \(assetVaultIdentifier)")
        let erc4626VaultEVMAddress = EVM.addressFromString(erc4626VaultEVMAddressHex)

        let assetVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: assetVaultIdentifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(assetVaultType.identifier)")
        self.assetVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: assetVaultData.storagePath)
            ?? panic("Could not find asset Vault in signer's storage at path \(assetVaultData.storagePath)")

        let coaPath = /storage/evm
        let coa = signer.capabilities.storage.issue<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(coaPath)

        let feeVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                /storage/flowTokenVault
            )
        let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: feeVault,
            uniqueID: nil
        )

        self.sink = ERC4626SinkConnectors.AssetSink(
            asset: assetVaultType,
            vault: erc4626VaultEVMAddress,
            coa: coa,
            feeSource: feeSource,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )

        self.beforeBalance = self.assetVault.balance
    }

    execute {
        self.sink.depositCapacity(from: self.assetVault)

        // After a paused deposit, balance should be restored (either no-op or recovery).
        // Allow small rounding tolerance from the bridge round-trip conversion.
        let afterBalance = self.assetVault.balance
        let tolerance: UFix64 = 0.00000001
        assert(
            afterBalance >= self.beforeBalance - tolerance,
            message: "Asset balance dropped unexpectedly: before=\(self.beforeBalance) after=\(afterBalance)"
        )
    }
}
