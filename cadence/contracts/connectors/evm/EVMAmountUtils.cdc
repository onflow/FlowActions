import "FlowEVMBridgeUtils"
import "EVM"

/// EVMAmountUtils
///
/// Shared utility contract for precision-safe EVM ↔ Cadence UFix64 amount conversions.
///
/// EVM tokens can have up to 18 decimal places, while Cadence UFix64 only supports 8.
/// Converting naively truncates lower-order digits, which can cause rounding errors in
/// DeFi operations. These helpers apply directional rounding:
///
/// - `toCadenceOut` (round **down**): safe for **output** amounts — user receives at most this much
/// - `toCadenceIn` (round **up**): safe for **input** amounts — user must provide at least this much
///
access(all) contract EVMAmountUtils {

    /// Convert an ERC20 `UInt256` amount into a Cadence `UFix64` **by rounding down** to the
    /// maximum `UFix64` precision (8 decimal places).
    ///
    /// - For `decimals <= 8`, the value is exactly representable, so this is a direct conversion.
    /// - For `decimals > 8`, this floors the ERC20 amount to the nearest multiple of
    ///   `quantum = 10^(decimals - 8)` so the result round-trips safely:
    ///   `ufix64ToUInt256(result) <= amt`.
    access(all) fun toCadenceOut(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)
        let remainder: UInt256 = amt % quantum
        let floored: UInt256 = amt - remainder

        return FlowEVMBridgeUtils.uint256ToUFix64(value: floored, decimals: decimals)
    }

    /// Convert an ERC20 `UInt256` amount into a Cadence `UFix64` **by rounding up** to the
    /// smallest representable value at `UFix64` precision (8 decimal places).
    ///
    /// - For `decimals <= 8`, the value is exactly representable, so this is a direct conversion.
    /// - For `decimals > 8`, this ceils the ERC20 amount to the next multiple of
    ///   `quantum = 10^(decimals - 8)` (unless already exact), ensuring:
    ///   `ufix64ToUInt256(result) >= amt`, and the increase is `< quantum`.
    access(all) fun toCadenceIn(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)

        let remainder: UInt256 = amt % quantum
        var padded = amt
        if remainder != 0 {
            padded = amt + (quantum - remainder)
        }

        return FlowEVMBridgeUtils.uint256ToUFix64(value: padded, decimals: decimals)
    }

    /// Convenience: resolve token decimals and round down for output amounts
    access(all) fun toCadenceOutForToken(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
        let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
        return self.toCadenceOut(amt, decimals: decimals)
    }

    /// Convenience: resolve token decimals and round up for input amounts
    access(all) fun toCadenceInForToken(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
        let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
        return self.toCadenceIn(amt, decimals: decimals)
    }

    init() {}
}
