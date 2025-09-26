import "DeFiActions"

/// Returns the scheduled transaction IDs of an AutoBalancer at the specified address via the Capability published
/// at the specified public path. If no AutoBalancer is found, `nil` is returned.
///
/// @param address: the address of the account
/// @param publicPath: the PublicPath where the AutoBalancer's public Capability can be found
///
access(all)
fun main(address: Address, publicPath: PublicPath): [UInt64]? {
    if let autoBalancer = getAccount(address).capabilities.borrow<&DeFiActions.AutoBalancer>(publicPath) {
        return autoBalancer.getScheduledTransactionIDs()
    }
    return nil
}
