import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "FungibleTokenConnectors"
import "ERC4626SwapConnectors"

/// Returns a quote for the amount of assets required to receive the desired amount of shares
///
/// @param coaHost: The address of the account hosting the COA
/// @param desiredShares: The desired amount of shares to receive
/// @param assetVaultIdentifier: The identifier of the asset token type
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string
///
access(all) fun main(
    coaHost: Address,
    desiredShares: UFix64,
    assetVaultIdentifier: String,
    erc4626VaultEVMAddressHex: String
): {DeFiActions.Quote} {
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

    // create the Swapper
    let swapper = ERC4626SwapConnectors.Swapper(
        asset: assetVaultType,
        vault: erc4626VaultEVMAddress,
        coa: coa,
        feeSource: feeSource,
        uniqueID: nil
    )

    // get the quote for the desired shares
    return swapper.quoteIn(forDesired: desiredShares, reverse: false)
}
