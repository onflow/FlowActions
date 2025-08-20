import "EVM"

/// Returns the EVM-native FLOW balance of the given EVM address
///
/// @param evmAddressHex: The EVM address as a hex string
///
/// @return The EVM-native FLOW balance of the given EVM address
///
access(all)
fun main(evmAddressHex: String): UFix64 {
    let evmAddress = EVM.addressFromString(evmAddressHex)
    let balance = evmAddress.balance().inFLOW()
    return balance
}
