import "Burner"
import "ViewResolver"
import "FungibleToken"

/// DeFiBlocks Interfaces
///
/// DeFiBlocks is a library of small DeFi components that act as glue to connect typical DeFi primitives (dexes, lending
/// pools, farms) into individual aggregations.
///
/// The core component of DeFiBlocks is the “Connector”; a conduit between the more complex pieces of the DeFi puzzle.
/// Connectors aren't to do anything especially complex, but make it simple and straightforward to connect the
/// traditional DeFi pieces together into new, custom aggregations.
///
/// Connectors should be thought of analogously with the small text processing tools of Unix that are mostly meant to be
/// connected with pipe operations instead of being operated individually. All Connectors are either a “Source” or
/// “Sink”.
///
access(all) contract DFB {

    access(all) var currentID: UInt64

    /* --- INTERFACE-LEVEL EVENTS --- */

    /// Emitted when value is deposited to a Sink
    access(all) event Deposited(
        type: String,
        amount: UFix64,
        inUUID: UInt64,
        uniqueID: UInt64?,
        sinkType: String
    )
    /// Emitted when value is withdrawn from a Source
    access(all) event Withdrawn(
        type: String,
        amount: UFix64,
        outUUID: UInt64,
        uniqueID: UInt64?,
        sourceType: String
    )
    /// Emitted when a Swapper executes a Swap
    access(all) event Swapped(
        inVault: String,
        outVault: String,
        inAmount: UFix64,
        outAmount: UFix64,
        inUUID: UInt64,
        outUUID: UInt64,
        uniqueID: UInt64?,
        swapperType: String
    )
    /// Emitted when AutoBalancer.rebalance() is called
    access(all) event Rebalanced(
        beforeAmount: UFix64,
        afterAmount: UFix64,
        uniqueID: UInt64?,
        autoBalancerType: String,
        uuid: UInt64
    )

    /// This interface enables protocols to trace stack operations via the interface-level events, identifying their
    /// UniqueIdentifier types and IDs. Implementations should ensure ID values are unique on initialization.
    ///
    access(all) struct UniqueIdentifier { // make concrete
        access(all) let id: UInt64
        init() {
            self.id = DFB.currentID
            DFB.currentID = DFB.currentID + 1
        }
    }

    /// A struct interface containing a UniqueIdentifier an convenience getters about it
    ///
    access(all) struct interface IdentifiableStruct {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Convenience method returning the inner UniqueIdentifier's Type or `nil` if none is set.
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification
        access(all) view fun idType(): Type? {
            return self.uniqueID?.getType()
        }
    }

    /// A Sink Connector (or just “Sink”) is analogous to the Fungible Token Receiver interface that accepts deposits of
    /// funds. It differs from the standard Receiver interface in that it is a struct interface (instead of resource
    /// interface) and allows for the graceful handling of Sinks that have a limited capacity on the amount they can
    /// accept for deposit. Implementations should therefore avoid the possibility of reversion with graceful fallback
    /// on unexpected conditions, executing no-ops instead of reverting.
    ///
    access(all) struct interface Sink : IdentifiableStruct {
        // TODO - conditional event emission
        // access(contract) view fun emitDeposited(beforeBalance: UFix64) {} - change scope if needed
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            post {
                emit Deposited(
                    type: from.getType().identifier,
                    amount: before(from.balance) >= from.balance ? before(from.balance) - from.balance : 0.0,
                    inUUID: from.uuid, // fromUUID
                    uniqueID: self.uniqueID?.id ?? nil,
                    sinkType: self.getType().identifier // maybe include
                )
            }
        }
    }

    /// A Source Connector (or just “Source”) is analogous to the Fungible Token Provider interface that provides funds
    /// on demand. It differs from the standard Provider interface in that it is a struct interface (instead of resource
    /// interface) and allows for graceful handling of the case that the Source might not know exactly the total amount
    /// of funds available to be withdrawn. Implementations should therefore avoid the possibility of reversion with
    /// graceful fallback on unexpected conditions, executing no-ops or returning an empty Vault instead of reverting.
    ///
    access(all) struct interface Source : IdentifiableStruct {
        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type
        /// Returns an estimate of how much of the associated Vault Type can be provided by this Source
        access(all) fun minimumAvailable(): UFix64
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            post {
                // TODO - conditional emit
                emit Withdrawn(
                    type: result.getType().identifier,
                    amount: result.balance,
                    outUUID: result.uuid, // toUUID
                    uniqueID: self.uniqueID?.id ?? nil,
                    sourceType: self.getType().identifier // maybe include
                )
            }
        }
    }

    /// An interface for an estimate to be returned by a Swapper when asking for a swap estimate. This may be helpful
    /// for passing additional parameters to a Swapper relevant to the use case. Implementations may choose to add
    /// fields relevant to their Swapper implementation and downcast in swap() and/or swapBack() scope.
    ///
    access(all) struct interface Quote {
        /// The quoted pre-swap Vault type
        access(all) let inVault: Type // TODO: make naming consistent
        /// The quoted post-swap Vault type
        access(all) let outVault: Type
        /// The quoted amount of pre-swap currency
        access(all) let inAmount: UFix64
        /// The quoted amount of post-swap currency for the defined inAmount
        access(all) let outAmount: UFix64
    }

    /// A basic interface for a struct that swaps between tokens. Implementations may choose to adapt this interface
    /// to fit any given swap protocol or set of protocols.
    ///
    // Feedback: Either commit to bi-directional
    //      or one-way and accept edge case that swap may return more than requested
    //          how common is this case?
    access(all) struct interface Swapper : IdentifiableStruct {
        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inVaultType(): Type
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outVaultType(): Type
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun amountIn(forDesired: UFix64, reverse: Bool): {Quote} // fun quoteIn/Out
        /// The estimated amount delivered out for a provided input balance
        access(all) fun amountOut(forProvided: UFix64, reverse: Bool): {Quote}
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        // TODO: assign direction from quote quote/inVault type & remove swapBack
        access(all) fun swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { // TODO update on new interface
                inVault.getType() == self.inVaultType():
                "Invalid vault provided for swap - \(inVault.getType().identifier) is not \(self.inVaultType().identifier)"
                (quote?.inVault ?? inVault.getType()) == inVault.getType():
                "Quote.inVault type \(quote!.inVault.identifier) does not match the provided inVault \(inVault.getType().identifier)"
            }
            post {
                emit Swapped(
                    inVault: before(inVault.getType().identifier),
                    outVault: result.getType().identifier,
                    inAmount: before(inVault.balance),
                    outAmount: result.balance,
                    inUUID: before(inVault.uuid),
                    outUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    swapperType: self.getType().identifier
                )
            }
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        // TODO: Impl detail - accept quote that was just used by swap() but reverse the direction assuming swap() was just called
        access(all) fun swapBack(quote: {Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre {
                residual.getType() == self.outVaultType():
                "Invalid vault provided for swapBack - \(residual.getType().identifier) is not \(self.outVaultType().identifier)"
                (quote?.inVault ?? residual.getType()) == residual.getType():
                "Quote.inVault type \(quote!.inVault.identifier) does not match the provided inVault \(residual.getType().identifier)"
            }
            post {
                emit Swapped(
                    inVault: before(residual.getType().identifier),
                    outVault: result.getType().identifier,
                    inAmount: before(residual.balance),
                    outAmount: result.balance,
                    inUUID: before(residual.uuid),
                    outUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    swapperType: self.getType().identifier
                )
            }
        }
    }

    /// An interface for a price oracle adapter. Implementations should adapt this interface to various price feed
    /// oracles deployed on Flow
    access(all) struct interface PriceOracle {
        /// Returns the asset type serving as the price basis - e.g. USD in FLOW/USD
        access(all) view fun unitOfAccount(): Type
        /// Returns the latest price data for a given asset denominated in unitOfAccount() if available, otherwise `nil`
        /// should be returned. Callers should note that although an optional is supported, implementations may choose
        /// to revert.
        access(all) fun price(ofToken: Type): UFix64?
    }

    /// A resource interface containing a UniqueIdentifier an convenience getters about it
    ///
    access(all) resource interface IdentifiableResource {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Convenience method returning the inner UniqueIdentifier's Type or `nil` if none is set.
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification
        access(all) view fun idType(): Type? {
            return self.uniqueID?.getType()
        }
    }

    /// Entitlement used by the AutoBalancer to set inner Sink and Source
    access(all) entitlement Set
    access(all) entitlement Get

    /// A resource interface designed to enable permissionless rebalancing of value around a wrapped Vault. An
    /// AutoBalancer can be a critical component of DeFiBlocks stacks by allowing for strategies to compound, repay
    /// loans or direct accumulated value to other sub-systems and/or user Vaults.
    ///
    access(all) resource interface AutoBalancer : IdentifiableResource, FungibleToken.Receiver, FungibleToken.Provider, ViewResolver.Resolver, Burner.Burnable {
        /// Returns the balance of the inner Vault
        access(all) view fun vaultBalance(): UFix64
        /// Returns the Type of the inner Vault
        access(all) view fun vaultType(): Type
        /// Returns the percentage difference from baseValue at which the AutoBalancer executes a rebalance
        access(all) view fun rebalanceThreshold(): UFix64
        /// Returns the value of all accounted deposits/withdraws as they have occurred denominated in unitOfAccount
        access(all) view fun baseValue(): UFix64
        /// Returns the token Type serving as the price basis of this AutoBalancer
        access(all) view fun unitOfAccount(): Type
        /// Returns the current value of the inner Vault's balance
        access(all) fun currentValue(): UFix64?
        /// Allows for external parties to call on the AutoBalancer and execute a rebalance according to it's rebalance
        /// parameters. Implementations should no-op if a rebalance threshold has not been met
        access(all) fun rebalance() {
            post {
                emit Rebalanced(
                    beforeAmount: before(self.vaultBalance()),
                    afterAmount: self.vaultBalance(),
                    uniqueID: self.uniqueID?.id,
                    autoBalancerType: self.getType().identifier,
                    uuid: self.uuid,
                )
            }
        }
        /// A setter enabling an AutoBalancer to set a Sink to which overflow value should be deposited. Implementations
        /// may wish to revert on call if a Sink is set on `init`
        access(Set) fun setSink(_ sink: {Sink})
        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn. Implementations
        /// may wish to revert on call if a Source is set on `init`
        access(Set) fun setSource(_ source: {Source})
        /// Enables the setting of a Capability on the AutoBalancer for the distribution of Sinks & Sources targeting
        /// the AutoBalancer instance. Due to the mechanisms of Capabilities, this must be done after the AutoBalancer
        /// has been saved to account storage and an authorized Capability has been issued.
        access(Set) fun setSelfCapability(_ cap: Capability<auth(FungibleToken.Withdraw) &{AutoBalancer}>) {
            pre {
                cap.check(): ""
                self.getType() == cap.borrow()!.getType(): ""
                self.uuid == cap.borrow()!.uuid: ""
            }
        }
        /// Convenience method issuing a Sink allowing for deposits to this AutoBalancer
        access(all) fun getBalancerSink(): {Sink}?
        /// Convenience method issuing a Source enabling withdrawals from this AutoBalancer
        access(Get) fun getBalancerSource(): {Source}?
    }

    init() {
        self.currentID = 0
    }
}
