import "EVM"
import "FlowToken"
import "TokenA"
import "UniswapV3SwapperProvider"

/// Attempts to create a TokenConfig with mismatched type and EVM address
/// This should fail because the flowType is not associated with the evmAddress
///
access(all) fun main(typeIdentifier: String, evmAddressHex: String): Bool {
    // Try to create a TokenConfig with TokenA type but WFLOW address
    // This should panic with "flowType must be associated with evmAddress"
    let tokenConfig = UniswapV3SwapperProvider.TokenConfig(
        flowType: CompositeType(typeIdentifier)!,
        evmAddress: EVM.addressFromString(evmAddressHex)
    )

    return true
}
