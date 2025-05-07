import "EVM"
import "FungibleToken"

/// StackFi
///
/// StackFi is a library of small DeFi components that act as glue to connect typical DeFi primitives (dexes, lending
/// pools, farms) into individual aggregations.
///
/// The core component of StackFi is the “Connector”; a conduit between the more complex pieces of the DeFi puzzle.
/// Connectors isn’t to do anything especially complex, but make it simple and straightforward to connect the
/// traditional DeFi pieces together into new, custom aggregations.
///
/// Connectors should be thought of analogously with the small text processing tools of Unix that are mostly meant to be
/// connected with pipe operations instead of being operated individually. All Connectors are either a “Source” or
/// “Sink”.
///
access(all) contract StackFiInterfaces {
    /// A Sink Connector (or just “Sink”) is analogous to the Fungible Token Receiver interface that accepts deposits of
    /// funds. It differs from the standard Receiver interface in that it is a struct interface (instead of resource
    /// interface) and allows for the graceful handling of Sinks that have a limited capacity on the amount they can
    /// accept for deposit. Implementations should therefore avoid the possibility of reversion with graceful fallback
    /// on unexpected conditions, executing no-ops instead of reverting.
    ///
    access(all) struct interface Sink {
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
    }

    /// A Source Connector (or just “Source”) is analogous to the Fungible Token Provider interface that provides funds
    /// on demand. It differs from the standard Provider interface in that it is a struct interface (instead of resource
    /// interface) and allows for graceful handling of the case that the Source might not know exactly the total amount
    /// of funds available to be withdrawn. Implementations should therefore avoid the possibility of reversion with
    /// graceful fallback on unexpected conditions, executing no-ops or returning an empty Vault instead of reverting.
    ///
    access(all) struct interface Source {
        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type
        /// Returns an estimate of how much of the associated Vault Type can be provided by this Source
        access(all) fun minimumAvailable(): UFix64
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}
    }

    /// A basic interface for a struct that swaps between tokens. Implementations may choose to adapt this interface
    /// to fit any given swap protocol or set of protocols.
    ///
    access(all) struct interface Swapper {
        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inVault(): Type
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outVault(): Type
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun amountIn(forDesired: UFix64): UFix64
        /// The estimated amount delivered out for a provided input balance
        access(all) fun amountOut(forProvided: UFix64): UFix64
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault}
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(residual: @{FungibleToken.Vault}): @{FungibleToken.Vault}
    }
}
