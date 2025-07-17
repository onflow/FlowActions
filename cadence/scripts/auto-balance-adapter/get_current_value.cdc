import "FungibleToken"

import "DeFiActions"

/// Returns the current value of the tokens contained by an AutoBalancer at the specified address via the Capability
/// published at the specified public path. `nil` may be returned if the AutoBalancer's PriceOracle cannot return a
/// price. If no AutoBalancer is found, script reverts.
///
/// @param address: the address of the account
/// @param publicPath: the PublicPath where the AutoBalancer's public Capability can be found
///
access(all)
fun main(address: Address, publicPath: PublicPath): UFix64? {
    return getAccount(address).capabilities.borrow<&DeFiActions.AutoBalancer>(publicPath)
        ?.currentValue()
        ?? panic("Could not find an AutoBalancer in address \(address) at path \(publicPath)")
}
