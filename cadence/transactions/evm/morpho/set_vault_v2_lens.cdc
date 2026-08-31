import "EVM"

/// Sets or clears the VaultV2Lens EVM address used by MorphoERC4626SwapConnectors to gate redemption quotes
/// on servicable liquidity. The address is stored in the contract account's storage (not contract state) so it
/// can be changed without a contract update. Must be signed by the MorphoERC4626SwapConnectors contract account.
///
/// @param lensEVMAddressHex: The VaultV2Lens EVM address as a hex string, or nil to clear the configuration and
///         revert to the liquidityAdapter/idle-assets heuristic.
///
transaction(lensEVMAddressHex: String?) {
    prepare(signer: auth(Storage) &Account) {
        let existing = signer.storage.load<EVM.EVMAddress>(from: /storage/MorphoERC4626VaultV2Lens)
        if let hex = lensEVMAddressHex {
            signer.storage.save(EVM.addressFromString(hex), to: /storage/MorphoERC4626VaultV2Lens)
        }
    }
}
