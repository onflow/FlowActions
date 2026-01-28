import "FungibleToken"
import "FlowToken"
import "EVM"
import "ERC4626Utils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "FlowEVMBridgeConfig"
import "MorphoERC4626SwapConnectors"

/// Returns a quote for the amount of assets required to receive the desired amount of shares
///
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string
/// @param desiredShares: The desired amount of shares to receive
///
access(all) fun main(
    coaHost: Address,
    erc4626VaultEVMAddressHex: String,
    desiredShares: UFix64
): {DeFiActions.Quote} {
    let erc4626VaultEVMAddress = EVM.addressFromString(erc4626VaultEVMAddressHex)
    let assetEVMAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: erc4626VaultEVMAddress)
        ?? panic("Cannot get an underlying asset EVM address from the vault")
    let assetType = FlowEVMBridgeConfig.getTypeAssociated(with: assetEVMAddress)
        ?? panic("Invalid asset vault identifier: \(assetEVMAddress.toString())")

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

    // create the Swapper
    let swapper = MorphoERC4626SwapConnectors.Swapper(
        assetType: assetType,
        vaultEVMAddress: erc4626VaultEVMAddress,
        coa: coa,
        feeSource: feeSource,
        uniqueID: nil
    )

    // get the quote for the desired shares
    return swapper.quoteIn(forDesired: desiredShares, reverse: false)
}
