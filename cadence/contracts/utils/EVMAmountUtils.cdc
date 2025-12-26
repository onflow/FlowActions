import "EVM"
import "FlowEVMBridgeUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// EVMAmountUtils
///
/// Utilities for converting ERC20 UInt256 amounts to Cadence UFix64 with explicit rounding direction.
/// Use out functions (round down) for outputs and in functions (round up) for required inputs.
///
access(all) contract EVMAmountUtils {

    /// Convert an ERC20 UInt256 amount to a Cadence UFix64 by rounding down to UFix64 precision.
    /// This is appropriate for outputs to avoid overstating amountOut.
    access(all) fun toCadenceOut(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
        let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
        return self.toCadenceOutWithDecimals(amt, decimals: decimals)
    }

    /// Convert an ERC20 UInt256 amount to a Cadence UFix64 by rounding up to UFix64 precision.
    /// This is appropriate for inputs to avoid understating amountIn.
    access(all) fun toCadenceIn(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
        let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
        return self.toCadenceInWithDecimals(amt, decimals: decimals)
    }

    /// Convert an ERC20 UInt256 amount to Cadence UFix64 by rounding down at the given decimals.
    access(all) fun toCadenceOutWithDecimals(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum: UInt256 = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)
        let remainder: UInt256 = amt % quantum
        let floored: UInt256 = amt - remainder

        return FlowEVMBridgeUtils.uint256ToUFix64(value: floored, decimals: decimals)
    }

    /// Convert an ERC20 UInt256 amount to Cadence UFix64 by rounding up at the given decimals.
    access(all) fun toCadenceInWithDecimals(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum: UInt256 = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)
        let remainder: UInt256 = amt % quantum
        var padded: UInt256 = amt

        if remainder != 0 {
            let delta = quantum - remainder
            assert(amt <= UInt256.max - delta, message: "Amount too large to pad to UFix64 precision")
            padded = amt + delta
        }

        return FlowEVMBridgeUtils.uint256ToUFix64(value: padded, decimals: decimals)
    }
}
