import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "FungibleTokenConnectors"
import "ERC4626SwapConnectors"
import "ERC4626SinkConnectors"

/// Returns the minimum capacity of the asset sink for the ERC4626 vault
///
/// @param coaHost: The address of the account hosting the COA
/// @param assetVaultIdentifier: The identifier of the asset token type
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string
access(all) fun main(
    coaHost: Address,
    assetVaultIdentifier: String,
    erc4626VaultEVMAddressHex: String
): UFix64 {
    let assetVaultType = CompositeType(assetVaultIdentifier)
        ?? panic("Invalid asset vault identifier: \(assetVaultIdentifier)")

    let erc4626VaultEVMAddress = EVM.addressFromString(erc4626VaultEVMAddressHex)

    let acct = getAuthAccount<auth(Storage, Capabilities) &Account>(coaHost)

    // get the COA capability
    let coa = acct.capabilities.storage.issue<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(/storage/evm)

    // create a fee source
    let feeVault = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
        /storage/flowTokenVault
    )
    let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
        min: nil,
        max: nil,
        vault: feeVault,
        uniqueID: nil
    )

    // create the AssetSink
    let assetSink = ERC4626SinkConnectors.AssetSink(
        asset: assetVaultType,
        vault: erc4626VaultEVMAddress,
        coa: coa,
        feeSource: feeSource,
        uniqueID: nil
    )

    // return the minimum capacity
    return assetSink.minimumCapacity()
}