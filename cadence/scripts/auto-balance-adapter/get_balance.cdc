import "FungibleToken"

import "DFB"

/// Returns the balance of tokens contained by an AutoBalancer at the specified address via the Capability published
/// at the specified public path. If no AutoBalancer is found, `nil` is returned.
///
/// @param address: the address of the account
/// @param publicPath: the PublicPath where the AutoBalancer's public Capability can be found
///
access(all)
fun main(address: Address, publicPath: PublicPath): UFix64? {
    if let autoBalancer = getAccount(address).capabilities.borrow<&DFB.AutoBalancer>(publicPath) {
        return autoBalancer.vaultBalance()
    }
    return nil
}
