import "EVM"

import "FlowEVMBridgeUtils"

/// Returns the balance of the owner (hex-encoded EVM address) of a given ERC20 fungible token defined
/// at the hex-encoded EVM contract address
///
/// @param owner: The hex-encoded EVM address of the owner
/// @param evmContractAddress: The hex-encoded EVM contract address of the ERC20 contract
///
/// @return The ERC20 balance of the address as a UFix64, reverting if the given contract address does not implement
///     the ERC20 method "balanceOf(address)(uint256)"
///
access(all) fun main(owner: String, evmContractAddress: String): UFix64 {
    let uintBalance = FlowEVMBridgeUtils.balanceOf(
        owner: EVM.addressFromString(owner),
        evmContractAddress: EVM.addressFromString(evmContractAddress)
    )
    return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
        uintBalance,
        erc20Address: EVM.addressFromString(evmContractAddress)
    )
}
