import "EVM"
import "FlowEVMBridgeConfig"

/// Resolves the Cadence type identifier for a given EVM token address.
/// Returns the type identifier string, or empty string if not found.
///
access(all) fun main(tokenHex: String): String {
    let evmAddr = EVM.addressFromString(tokenHex)
    let associatedType = FlowEVMBridgeConfig.getTypeAssociated(with: evmAddr)
    if let t = associatedType {
        return t.identifier
    }
    return ""
}
