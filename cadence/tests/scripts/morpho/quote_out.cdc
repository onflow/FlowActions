import "FungibleToken"
import "FlowToken"
import "EVM"
import "ERC4626Utils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "FlowEVMBridgeConfig"
import "MorphoERC4626SwapConnectors"

/// Returns a quote for the amount of assets received for the provided amount of shares (shares -> assets direction)
///
/// @param erc4626VaultEVMAddressHex: The EVM address of the ERC4626 vault as a hex string
/// @param providedShares: The amount of shares to provide
///
access(all) fun main(
    coaHost: Address,
    erc4626VaultEVMAddressHex: String,
    providedShares: UFix64
): {DeFiActions.Quote} {
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
    let swapper = MorphoERC4626SwapConnectors.Swapper(
        vaultEVMAddress: erc4626VaultEVMAddress,
        coa: coa,
        feeSource: feeSource,
        uniqueID: nil,
        isReversed: false,
    )

    // get the quote for the provided shares in the shares -> assets direction
    return swapper.quoteOut(forProvided: providedShares, reverse: true)
}
