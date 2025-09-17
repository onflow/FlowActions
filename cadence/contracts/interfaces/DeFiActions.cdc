import "Burner"
import "ViewResolver"
import "FungibleToken"

import "DeFiActionsUtils"
import "DeFiActionsMathUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// [BETA] DeFiActions
///
/// DeFiActions is a library of small DeFi components that act as glue to connect typical DeFi primitives (dexes, lending
/// pools, farms) into individual aggregations.
///
/// The core component of DeFiActions is the “Connector”; a conduit between the more complex pieces of the DeFi puzzle.
/// Connectors aren't to do anything especially complex, but make it simple and straightforward to connect the
/// traditional DeFi pieces together into new, custom aggregations.
///
/// Connectors should be thought of analogously with the small text processing tools of Unix that are mostly meant to be
/// connected with pipe operations instead of being operated individually. All Connectors are either a “Source” or
/// “Sink”.
///
access(all) contract DeFiActions {

    /* --- FIELDS --- */

    /// The current ID assigned to UniqueIdentifiers as they are initialized
    /// It is incremented by 1 every time a UniqueIdentifier is created so each ID is only ever used once
    access(all) var currentID: UInt64
    /// The AuthenticationToken Capability required to create a UniqueIdentifier
    access(self) let authTokenCap: Capability<auth(Identify) &AuthenticationToken>
    /// The StoragePath for the AuthenticationToken resource
    access(self) let AuthTokenStoragePath: StoragePath

    /* --- INTERFACE-LEVEL EVENTS --- */

    /// Emitted when value is deposited to a Sink
    access(all) event Deposited(
        type: String,
        amount: UFix64,
        fromUUID: UInt64,
        uniqueID: UInt64?,
        sinkType: String
    )
    /// Emitted when value is withdrawn from a Source
    access(all) event Withdrawn(
        type: String,
        amount: UFix64,
        withdrawnUUID: UInt64,
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
    /// Emitted when a Flasher executes a flash loan
    access(all) event Flashed(
        requestedAmount: UFix64,
        borrowType: String,
        uniqueID: UInt64?,
        flasherType: String
    )
    /// Emitted when an IdentifiableResource's UniqueIdentifier is aligned with another DFA component
    access(all) event UpdatedID(
        oldID: UInt64?,
        newID: UInt64?,
        component: String,
        uuid: UInt64?
    )
    /// Emitted when an AutoBalancer is created
    access(all) event CreatedAutoBalancer(
        lowerThreshold: UFix64,
        upperThreshold: UFix64,
        vaultType: String,
        vaultUUID: UInt64,
        uuid: UInt64,
        uniqueID: UInt64?
    )
    /// Emitted when AutoBalancer.rebalance() is called
    access(all) event Rebalanced(
        amount: UFix64,
        value: UFix64,
        unitOfAccount: String,
        isSurplus: Bool,
        vaultType: String,
        vaultUUID: UInt64,
        balancerUUID: UInt64,
        address: Address?,
        uuid: UInt64,
        uniqueID: UInt64?
    )

    /// Emitted when Liquidator.liquidate is called
    access(all) event Liquidated()

    /* --- CONSTRUCTS --- */

    access(all) entitlement Identify

    /// AuthenticationToken
    ///
    /// A resource intended to ensure UniqueIdentifiers are only created by the DeFiActions contract
    ///
    access(all) resource AuthenticationToken {}

    /// UniqueIdentifier
    ///
    /// This construct enables protocols to trace stack operations via DeFiActions interface-level events, identifying
    /// them by UniqueIdentifier IDs. IdentifiableResource Implementations should ensure that access to them is
    /// encapsulated by the structures they are used to identify.
    ///
    access(all) struct UniqueIdentifier {
        /// The ID value of this UniqueIdentifier
        access(all) let id: UInt64
        /// The AuthenticationToken Capability required to create this UniqueIdentifier. Since this is a struct which
        /// can be created in any context, this authorized Capability ensures that the UniqueIdentifier can only be
        /// created by the DeFiActions contract, thus preventing forged UniqueIdentifiers from being created.
        access(self) let authCap: Capability<auth(Identify) &AuthenticationToken>

        access(contract) view init(_ id: UInt64, _ authCap: Capability<auth(Identify) &AuthenticationToken>) {
            pre {
                authCap.check(): "Invalid AuthenticationToken Capability provided"
            }
            self.id = id
            self.authCap = authCap
        }
    }

    /// ComponentInfo
    ///
    /// A struct containing minimal information about a DeFiActions component and its inner components
    ///
    access(all) struct ComponentInfo {
        /// The type of the component
        access(all) let type: Type
        /// The UniqueIdentifier.id of the component
        access(all) let id: UInt64?
        /// The inner component types of the serving component
        access(all) let innerComponents: [ComponentInfo]
        init(
            type: Type,
            id: UInt64?,
            innerComponents: [ComponentInfo]
        ) {
            self.type = type
            self.id = id
            self.innerComponents = innerComponents
        }
    }

    /// Extend entitlement allowing for the authorized copying of UniqueIdentifiers from existing components
    access(all) entitlement Extend

    /// IdentifiableResource
    ///
    /// A resource interface containing a UniqueIdentifier and convenience getters about it
    ///
    access(all) struct interface IdentifiableStruct {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        ///
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification unless the implementation itself is known and trusted
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            post {
                result?.id == self.uniqueID?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully copied"
            }
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            post {
                self.uniqueID?.id == id?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully set"
                DeFiActions.emitUpdatedID(
                    oldID: before(self.uniqueID?.id),
                    newID: self.uniqueID?.id,
                    component: self.getType().identifier,
                    uuid: nil // no UUID for structs
                ): "Unknown error emitting DeFiActions.UpdatedID from IdentifiableStruct \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// IdentifiableResource
    ///
    /// A resource interface containing a UniqueIdentifier and convenience getters about it
    ///
    access(all) resource interface IdentifiableResource {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        ///
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification unless the implementation itself is known and trusted
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            post {
                result?.id == self.uniqueID?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully copied"
            }
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            post {
                self.uniqueID?.id == id?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully set"
                DeFiActions.emitUpdatedID(
                    oldID: before(self.uniqueID?.id),
                    newID: self.uniqueID?.id,
                    component: self.getType().identifier,
                    uuid: self.uuid
                ): "Unknown error emitting DeFiActions.UpdatedID from IdentifiableStruct \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Sink
    ///
    /// A Sink Connector (or just “Sink”) is analogous to the Fungible Token Receiver interface that accepts deposits of
    /// funds. It differs from the standard Receiver interface in that it is a struct interface (instead of resource
    /// interface) and allows for the graceful handling of Sinks that have a limited capacity on the amount they can
    /// accept for deposit. Implementations should therefore avoid the possibility of reversion with graceful fallback
    /// on unexpected conditions, executing no-ops instead of reverting.
    ///
    access(all) struct interface Sink : IdentifiableStruct {
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            pre {
                from.getType() == self.getSinkType():
                "Invalid vault provided for deposit - \(from.getType().identifier) is not \(self.getSinkType().identifier)"
            }
            post {
                DeFiActions.emitDeposited(
                    type: from.getType().identifier,
                    beforeBalance: before(from.balance),
                    afterBalance: from.balance,
                    fromUUID: from.uuid,
                    uniqueID: self.uniqueID?.id,
                    sinkType: self.getType().identifier
                ): "Unknown error emitting DeFiActions.Withdrawn from Sink \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Source
    ///
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
                result.getType() == self.getSourceType():
                "Invalid vault provided for withdraw - \(result.getType().identifier) is not \(self.getSourceType().identifier)"
                DeFiActions.emitWithdrawn(
                    type: result.getType().identifier,
                    amount: result.balance,
                    withdrawnUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    sourceType: self.getType().identifier
                ): "Unknown error emitting DeFiActions.Withdrawn from Source \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Quote
    ///
    /// An interface for an estimate to be returned by a Swapper when asking for a swap estimate. This may be helpful
    /// for passing additional parameters to a Swapper relevant to the use case. Implementations may choose to add
    /// fields relevant to their Swapper implementation and downcast in swap() and/or swapBack() scope.
    ///
    access(all) struct interface Quote {
        /// The quoted pre-swap Vault type
        access(all) let inType: Type
        /// The quoted post-swap Vault type
        access(all) let outType: Type
        /// The quoted amount of pre-swap currency
        access(all) let inAmount: UFix64
        /// The quoted amount of post-swap currency for the defined inAmount
        access(all) let outAmount: UFix64
    }

    /// Swapper
    ///
    /// A basic interface for a struct that swaps between tokens. Implementations may choose to adapt this interface
    /// to fit any given swap protocol or set of protocols.
    ///
    access(all) struct interface Swapper : IdentifiableStruct {
        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inType(): Type
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outType(): Type
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {Quote} // fun quoteIn/Out
        /// The estimated amount delivered out for a provided input balance
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {Quote}
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre {
                inVault.getType() == self.inType():
                "Invalid vault provided for swap - \(inVault.getType().identifier) is not \(self.inType().identifier)"
                (quote?.inType ?? inVault.getType()) == inVault.getType():
                "Quote.inType type \(quote!.inType.identifier) does not match the provided inVault \(inVault.getType().identifier)"
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
                residual.getType() == self.outType():
                "Invalid vault provided for swapBack - \(residual.getType().identifier) is not \(self.outType().identifier)"
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

    /// PriceOracle
    ///
    /// An interface for a price oracle adapter. Implementations should adapt this interface to various price feed
    /// oracles deployed on Flow
    ///
    access(all) struct interface PriceOracle : IdentifiableStruct {
        /// Returns the asset type serving as the price basis - e.g. USD in FLOW/USD
        access(all) view fun unitOfAccount(): Type
        /// Returns the latest price data for a given asset denominated in unitOfAccount() if available, otherwise `nil`
        /// should be returned. Callers should note that although an optional is supported, implementations may choose
        /// to revert.
        access(all) fun price(ofToken: Type): UFix64? {
            post {
                result == nil || result! > 0.0:
                "PriceOracle must return a price greater than 0.0 if available"
            }
        }
    }

    /// Flasher
    ///
    /// An interface for a flash loan adapter. Implementations should adapt this interface to various flash loan
    /// protocols deployed on Flow
    ///
    access(all) struct interface Flasher : IdentifiableStruct {
        /// Returns the asset type this Flasher can issue as a flash loan
        access(all) view fun borrowType(): Type
        /// Returns the estimated fee for a flash loan of the specified amount
        access(all) fun calculateFee(loanAmount: UFix64): UFix64
        /// Performs a flash loan of the specified amount. The callback function is passed the fee amount, a Vault
        /// containing the loan, and the data. The callback function should return a Vault containing the loan + fee.
        access(all) fun flashLoan(
            amount: UFix64,
            data: AnyStruct?,
            callback: fun(UFix64, @{FungibleToken.Vault}, AnyStruct?): @{FungibleToken.Vault} // fee, loan, data
        ) {
            post {
                emit Flashed(
                    requestedAmount: amount,
                    borrowType: self.borrowType().identifier,
                    uniqueID: self.uniqueID?.id ?? nil,
                    flasherType: self.getType().identifier
                )
            }
        }
    }

    /// Liquidator
    ///
    /// A Liquidator connector enables the liquidation of funds. The general use case is withdrawing all
    /// available funds from a connected liquidity source.
    ///
    access(all) struct interface Liquidator : IdentifiableStruct {
        /// Returns the type this Liquidator provides on liquidation
        access(all) view fun getLiquidationType(): Type
        /// Returns the amount available for liquidation
        access(all) fun liquidationAmount(): UFix64
        /// Liquidates available funds. It's up to the implementation to cast and utilize the provided data
        /// if any is provided.
        access(FungibleToken.Withdraw) fun liquidate(data: AnyStruct?): @{FungibleToken.Vault} {
            post {
                result.getType() == self.getLiquidationType():
                "Invalid liquidation - expected \(self.getLiquidationType().identifier) but returned \(result.getType().identifier)"
                emit Liquidated()
            }
        }
    }

    /*******************************************************************************************************************
        NOTICE: The AutoBalancer will extend the FlowCallbackScheduler.CallbackHandler interface which is not yet
        finalized. To avoid the need for re-deploying with that interface and related fields managing ScheduleCallback
        structs, the AutoBalancer and its connectors are omitted from the DeFiActions contract on Testnet & Mainnet
        until the FlowCallbackScheduler contract is available.
     *******************************************************************************************************************/

    /// AutoBalancerSink
    ///
    /// A DeFiActions Sink enabling the deposit of funds to an underlying AutoBalancer resource. As written, this Source
    /// may be used with externally defined AutoBalancer implementations
    ///
    access(all) struct AutoBalancerSink : Sink {
        /// The Type this Sink accepts
        access(self) let type: Type
        /// An authorized Capability on the underlying AutoBalancer where funds are deposited
        access(self) let autoBalancer: Capability<&AutoBalancer>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?

        init(autoBalancer: Capability<&AutoBalancer>, uniqueID: UniqueIdentifier?) {
            pre {
                autoBalancer.check():
                "Invalid AutoBalancer Capability Provided"
            }
            self.type = autoBalancer.borrow()!.vaultType()
            self.autoBalancer = autoBalancer
            self.uniqueID = uniqueID
        }

        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.type
        }
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        /// can currently only be UFix64.max or 0.0
        access(all) fun minimumCapacity(): UFix64 {
            return self.autoBalancer.check() ? UFix64.max : 0.0
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if let ab = self.autoBalancer.borrow() {
                ab.deposit(from: <-from.withdraw(amount: from.balance))
            }
            return
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo {
            return ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            self.uniqueID = id
        }
    }

    /// AutoBalancerSource
    ///
    /// A DeFiActions Source targeting an underlying AutoBalancer resource. As written, this Source may be used with
    /// externally defined AutoBalancer implementations
    ///
    access(all) struct AutoBalancerSource : Source {
        /// The Type this Source provides
        access(self) let type: Type
        /// An authorized Capability on the underlying AutoBalancer where funds are sourced
        access(self) let autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?

        init(autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>, uniqueID: UniqueIdentifier?) {
            pre {
                autoBalancer.check():
                "Invalid AutoBalancer Capability Provided"
            }
            self.type = autoBalancer.borrow()!.vaultType()
            self.autoBalancer = autoBalancer
            self.uniqueID = uniqueID
        }

        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type {
            return self.type
        }
        /// Returns an estimate of how much of the associated Vault Type can be provided by this Source
        access(all) fun minimumAvailable(): UFix64 {
            if let ab = self.autoBalancer.borrow() {
                return ab.vaultBalance()
            }
            return 0.0
        }
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            if let ab = self.autoBalancer.borrow() {
                return <-ab.withdraw(
                    amount: maxAmount <= ab.vaultBalance() ? maxAmount : ab.vaultBalance()
                )
            }
            return <- DeFiActionsUtils.getEmptyVault(self.type)
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo {
            return ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            self.uniqueID = id
        }
    }

    /// Entitlement used by the AutoBalancer to set inner Sink and Source
    access(all) entitlement Auto
    access(all) entitlement Set
    access(all) entitlement Get

    /// AutoBalancer
    ///
    /// A resource designed to enable permissionless rebalancing of value around a wrapped Vault. An
    /// AutoBalancer can be a critical component of DeFiActions stacks by allowing for strategies to compound, repay
    /// loans or direct accumulated value to other sub-systems and/or user Vaults.
    ///
    access(all) resource AutoBalancer : IdentifiableResource, FungibleToken.Receiver, FungibleToken.Provider, ViewResolver.Resolver, Burner.Burnable {
        /// The value in deposits & withdrawals over time denominated in oracle.unitOfAccount()
        access(self) var _valueOfDeposits: UFix64
        /// The percentage low and high thresholds defining when a rebalance executes
        /// Index 0 is low, index 1 is high
        access(self) var _rebalanceRange: [UFix64; 2]
        /// Oracle used to track the baseValue for deposits & withdrawals over time
        access(self) let _oracle: {PriceOracle}
        /// The inner Vault's Type captured for the ResourceDestroyed event
        access(self) let _vaultType: Type
        /// Vault used to deposit & withdraw from made optional only so the Vault can be burned via Burner.burn() if the
        /// AutoBalancer is burned and the Vault's burnCallback() can be called in the process
        access(self) var _vault: @{FungibleToken.Vault}?
        /// An optional Sink used to deposit excess funds from the inner Vault once the converted value exceeds the
        /// rebalance range. This Sink may be used to compound yield into a position or direct excess value to an
        /// external Vault
        access(self) var _rebalanceSink: {Sink}?
        /// An optional Source used to deposit excess funds to the inner Vault once the converted value is below the
        /// rebalance range
        access(self) var _rebalanceSource: {Source}?
        /// Capability on this AutoBalancer instance
        access(self) var _selfCap: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>?
        /// An optional UniqueIdentifier tying this AutoBalancer to a given stack
        access(contract) var uniqueID: UniqueIdentifier?

        /// Emitted when the AutoBalancer is destroyed
        access(all) event ResourceDestroyed(
            uuid: UInt64 = self.uuid,
            vaultType: String = self._vaultType.identifier,
            balance: UFix64? = self._vault?.balance,
            uniqueID: UInt64? = self.uniqueID?.id
        )

        init(
            lower: UFix64,
            upper: UFix64,
            oracle: {PriceOracle},
            vaultType: Type,
            outSink: {Sink}?,
            inSource: {Source}?,
            uniqueID: UniqueIdentifier?
        ) {
            pre {
                lower < upper && 0.01 <= lower && lower < 1.0 && 1.0 < upper && upper < 2.0:
                "Invalid rebalanceRange [lower, upper]: [\(lower), \(upper)] - thresholds must be set such that 0.01 <= lower < 1.0 and 1.0 < upper < 2.0 relative to value of deposits"
                DeFiActionsUtils.definingContractIsFungibleToken(vaultType):
                "The contract defining Vault \(vaultType.identifier) does not conform to FungibleToken contract interface"
            }
            assert(oracle.price(ofToken: vaultType) != nil,
                message: "Provided Oracle \(oracle.getType().identifier) could not provide a price for vault \(vaultType.identifier)")
            self._valueOfDeposits = 0.0
            self._rebalanceRange = [lower, upper]
            self._oracle = oracle
            self._vault <- DeFiActionsUtils.getEmptyVault(vaultType)
            self._vaultType = vaultType
            self._rebalanceSink = outSink
            self._rebalanceSource = inSource
            self._selfCap = nil
            self.uniqueID = uniqueID

            emit CreatedAutoBalancer(
                lowerThreshold: lower,
                upperThreshold: upper,
                vaultType: vaultType.identifier,
                vaultUUID: self._borrowVault().uuid,
                uuid: self.uuid,
                uniqueID: self.id()
            )
        }

        /* Core AutoBalancer Functionality */

        /// Returns the balance of the inner Vault
        ///
        /// @return the current balance of the inner Vault
        ///
        access(all) view fun vaultBalance(): UFix64 {
            return self._borrowVault().balance
        }
        /// Returns the Type of the inner Vault
        ///
        /// @return the Type of the inner Vault
        ///
        access(all) view fun vaultType(): Type {
            return self._borrowVault().getType()
        }
        /// Returns the low and high rebalance thresholds as a fixed length UFix64 containing [low, high]
        ///
        /// @return a sorted fixed-length array containing the relative lower and upper thresholds conditioning
        ///     rebalance execution
        ///
        access(all) view fun rebalanceThresholds(): [UFix64; 2] {
            return self._rebalanceRange
        }
        /// Returns the value of all accounted deposits/withdraws as they have occurred denominated in unitOfAccount.
        /// The returned value is the value as tracked historically, not necessarily the current value of the inner
        /// Vault's balance.
        ///
        /// @return the historical value of deposits
        ///
        access(all) view fun valueOfDeposits(): UFix64 {
            return self._valueOfDeposits
        }
        /// Returns the token Type serving as the price basis of this AutoBalancer
        ///
        /// @return the price denomination of value of the underlying vault as returned from the inner PriceOracle
        ///
        access(all) view fun unitOfAccount(): Type {
            return self._oracle.unitOfAccount()
        }
        /// Returns the current value of the inner Vault's balance. If a price is not available from the AutoBalancer's
        /// PriceOracle, `nil` is returned
        ///
        /// @return the current value of the inner's Vault's balance denominated in unitOfAccount() if a price is
        ///     available, `nil` otherwise
        ///
        access(all) fun currentValue(): UFix64? {
            if let price = self._oracle.price(ofToken: self.vaultType()) {
                return price * self._borrowVault().balance
            }
            return nil
        }
        /// Returns a ComponentInfo struct containing information about this AutoBalancer and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): ComponentInfo {
            // get the inner components
            let oracle = self._borrowOracle()
            let inner: [ComponentInfo] = [oracle.getComponentInfo()]

            // get the info for the optional inner components if they exist
            let maybeSink = self._borrowSink()
            let maybeSource = self._borrowSource()
            if let sink = maybeSink {
                inner.append(sink.getComponentInfo())
            }
            if let source = maybeSource {
                inner.append(source.getComponentInfo())
            }

            // create the ComponentInfo for the AutoBalancer and insert it at the beginning of the list
            return ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: inner
            )
        }
        /// Convenience method issuing a Sink allowing for deposits to this AutoBalancer. If the AutoBalancer's
        /// Capability on itself is not set or is invalid, `nil` is returned.
        ///
        /// @return a Sink routing deposits to this AutoBalancer
        ///
        access(all) fun createBalancerSink(): {Sink}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return AutoBalancerSink(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }
        /// Convenience method issuing a Source enabling withdrawals from this AutoBalancer. If the AutoBalancer's
        /// Capability on itself is not set or is invalid, `nil` is returned.
        ///
        /// @return a Source routing withdrawals from this AutoBalancer
        ///
        access(Get) fun createBalancerSource(): {Source}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return AutoBalancerSource(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }
        /// A setter enabling an AutoBalancer to set a Sink to which overflow value should be deposited
        ///
        /// @param sink: The optional Sink DeFiActions connector from which funds are sourced when this AutoBalancer
        ///     current value rises above the upper threshold relative to its valueOfDeposits(). If `nil`, overflown
        ///     value will not rebalance
        ///
        access(Set) fun setSink(_ sink: {Sink}?, updateSinkID: Bool) {
            if sink != nil && updateSinkID {
                let toUpdate = &sink! as auth(Extend) &{IdentifiableStruct}
                let toAlign = &self as auth(Identify) &{IdentifiableResource}
                DeFiActions.alignID(toUpdate: toUpdate, with: toAlign)
            }
            self._rebalanceSink = sink
        }
        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn
        ///
        /// @param source: The optional Source DeFiActions connector from which funds are sourced when this AutoBalancer
        ///     current value falls below the lower threshold relative to its valueOfDeposits(). If `nil`, underflown
        ///     value will not rebalance
        ///
        access(Set) fun setSource(_ source: {Source}?, updateSourceID: Bool) {
            if source != nil && updateSourceID {
                let toUpdate = &source! as auth(Extend) &{IdentifiableStruct}
                let toAlign = &self as auth(Identify) &{IdentifiableResource}
                DeFiActions.alignID(toUpdate: toUpdate, with: toAlign)
            }
            self._rebalanceSource = source
        }
        /// Enables the setting of a Capability on the AutoBalancer for the distribution of Sinks & Sources targeting
        /// the AutoBalancer instance. Due to the mechanisms of Capabilities, this must be done after the AutoBalancer
        /// has been saved to account storage and an authorized Capability has been issued.
        access(Set) fun setSelfCapability(_ cap: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>) {
            pre {
                self._selfCap == nil || self._selfCap!.check() != true:
                "Internal AutoBalancer Capability has been set and is still valid - cannot be re-assigned"
                cap.check(): "Invalid AutoBalancer Capability provided"
                self.getType() == cap.borrow()!.getType() && self.uuid == cap.borrow()!.uuid:
                "Provided Capability does not target this AutoBalancer of type \(self.getType().identifier) with UUID \(self.uuid) - "
                    .concat("provided Capability for AutoBalancer of type \(cap.borrow()!.getType().identifier) with UUID \(cap.borrow()!.uuid)")
            }
            self._selfCap = cap
        }
        /// Sets the rebalance range of this AutoBalancer
        ///
        /// @param range: a sorted array containing lower and upper thresholds that condition rebalance execution. The
        ///     thresholds must be values such that 0.01 <= range[0] < 1.0 && 1.0 < range[1] < 2.0
        ///
        access(Set) fun setRebalanceRange(_ range: [UFix64; 2]) {
            pre {
                range[0] < range[1] && 0.01 <= range[0] && range[0] < 1.0 && 1.0 < range[1] && range[1] < 2.0:
                "Invalid rebalanceRange [lower, upper]: [\(range[0]), \(range[1])] - thresholds must be set such that 0.01 <= range[0] < 1.0 and 1.0 < range[1] < 2.0 relative to value of deposits"
            }
            self._rebalanceRange = range
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// Allows for external parties to call on the AutoBalancer and execute a rebalance according to it's rebalance
        /// parameters. This method must be called by external party regularly in order for rebalancing to occur.
        ///
        /// @param force: if false, rebalance will occur only when beyond upper or lower thresholds; if true, rebalance
        ///     will execute as long as a price is available via the oracle and the current value is non-zero
        ///
        access(Auto) fun rebalance(force: Bool) {
            let currentPrice = self._oracle.price(ofToken: self._vaultType)
            if currentPrice == nil {
                return // no price available -> do nothing
            }
            let currentValue = self.currentValue()!
            // calculate the difference between the current value and the historical value of deposits
            var valueDiff: UFix64 = currentValue < self._valueOfDeposits ? self._valueOfDeposits - currentValue : currentValue - self._valueOfDeposits
            // if deficit detected, choose lower threshold, otherwise choose upper threshold
            let isDeficit = currentValue < self._valueOfDeposits
            let threshold = isDeficit ? (1.0 - self._rebalanceRange[0]) : (self._rebalanceRange[1] - 1.0)

            if currentPrice == 0.0 || valueDiff == 0.0 || ((valueDiff / self._valueOfDeposits) < threshold && !force) {
                // division by zero, no difference, or difference does not exceed rebalance ratio & not forced -> no-op
                return
            }

            let vault = self._borrowVault()
            //var amount = valueDiff / currentPrice!
            var amount = DeFiActionsMathUtils.divUFix64WithRounding(valueDiff, currentPrice!)
            var executed = false
            let maybeRebalanceSource = &self._rebalanceSource as auth(FungibleToken.Withdraw) &{Source}?
            let maybeRebalanceSink = &self._rebalanceSink as &{Sink}?
            if isDeficit && maybeRebalanceSource != nil {
                // rebalance back up to baseline sourcing funds from _rebalanceSource
                let depositVault <- maybeRebalanceSource!.withdrawAvailable(maxAmount: amount)
                amount = depositVault.balance // update the rebalanced amount based on actual deposited amount
                vault.deposit(from: <-depositVault)
                executed = true
            } else if !isDeficit && maybeRebalanceSink != nil {
                // rebalance back down to baseline depositing excess to _rebalanceSink
                if amount > vault.balance {
                    amount = vault.balance // protect underflow
                }
                let surplus <- vault.withdraw(amount: amount)
                maybeRebalanceSink!.depositCapacity(from: &surplus as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                executed = true
                if surplus.balance == 0.0 {
                    Burner.burn(<-surplus) // could destroy
                } else {
                    amount = amount - surplus.balance // update the rebalanced amount
                    valueDiff = valueDiff - (surplus.balance * currentPrice!) // update the value difference
                    vault.deposit(from: <-surplus) // deposit any excess not taken by the Sink
                }
            }
            // emit event only if rebalance was executed
            if executed {
                emit Rebalanced(
                    amount: amount,
                    value: valueDiff,
                    unitOfAccount: self.unitOfAccount().identifier,
                    isSurplus: !isDeficit,
                    vaultType: self.vaultType().identifier,
                    vaultUUID: self._borrowVault().uuid,
                    balancerUUID: self.uuid,
                    address: self.owner?.address,
                    uuid: self.uuid,
                    uniqueID: self.id()
                )
            }
        }

        /* ViewResolver.Resolver conformance */

        /// Passthrough to inner Vault's view Types
        access(all) view fun getViews(): [Type] {
            return self._borrowVault().getViews()
        }
        /// Passthrough to inner Vault's view resolution
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            return self._borrowVault().resolveView(view)
        }

        /* FungibleToken.Receiver & .Provider conformance */

        /// Only the nested Vault type is supported by this AutoBalancer for deposits & withdrawal for the sake of
        /// single asset accounting
        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            return { self.vaultType(): true }
        }
        /// True if the provided Type is the nested Vault Type, false otherwise
        access(all) view fun isSupportedVaultType(type: Type): Bool {
            return self.getSupportedVaultTypes()[type] == true
        }
        /// Passthrough to the inner Vault's isAvailableToWithdraw() method
        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
            return self._borrowVault().isAvailableToWithdraw(amount: amount)
        }
        /// Deposits the provided Vault to the nested Vault if it is of the same Type, reverting otherwise. In the
        /// process, the current value of the deposited amount (denominated in unitOfAccount) increments the
        /// AutoBalancer's baseValue. If a price is not available via the internal PriceOracle, the operation reverts.
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            pre {
                from.getType() == self.vaultType():
                "Invalid Vault type \(from.getType().identifier) deposited - this AutoBalancer only accepts \(self.vaultType().identifier)"
            }
            // assess value & complete deposit - if none available, revert
            let price = self._oracle.price(ofToken: from.getType())
                ?? panic("No price available for \(from.getType().identifier) to assess value of deposit")
            self._valueOfDeposits = self._valueOfDeposits + (from.balance * price)
            self._borrowVault().deposit(from: <-from)
        }
        /// Returns the requested amount of the nested Vault type, reducing the baseValue by the current value
        /// (denominated in unitOfAccount) of the token amount. The AutoBalancer's valueOfDeposits is decremented
        /// in proportion to the amount withdrawn relative to the inner Vault's balance
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            pre {
                amount <= self.vaultBalance(): "Withdraw amount \(amount) exceeds current vault balance \(self.vaultBalance())"
            }
            if amount == 0.0 {
                return <- self._borrowVault().createEmptyVault()
            }
            // adjust historical value of deposits proportionate to the amount withdrawn & return withdrawn vault
            // self._valueOfDeposits = (1.0 - amount / self.vaultBalance()) * self._valueOfDeposits
            let proportion: UFix64 = 1.0 - DeFiActionsMathUtils.divUFix64WithRounding(amount, self.vaultBalance())
            let newValue = self._valueOfDeposits * proportion
            self._valueOfDeposits = newValue
            return <- self._borrowVault().withdraw(amount: amount)
        }

        /* Burnable.Burner conformance */

        /// Executed in Burner.burn(). Passes along the inner vault to be burned, executing the inner Vault's
        /// burnCallback() logic
        access(contract) fun burnCallback() {
            let vault <- self._vault <- nil
            Burner.burn(<-vault) // executes the inner Vault's burnCallback()
        }

        /* Internal */

        /// Returns a reference to the inner Vault
        access(self) view fun _borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault} {
            return (&self._vault)!
        }
        /// Returns a reference to the inner Vault
        access(self) view fun _borrowOracle(): &{PriceOracle} {
            return &self._oracle
        }
        /// Returns a reference to the inner Vault
        access(self) view fun _borrowSink(): &{Sink}? {
            return &self._rebalanceSink
        }
        /// Returns a reference to the inner Source
        access(self) view fun _borrowSource(): auth(FungibleToken.Withdraw) &{Source}? {
            return &self._rebalanceSource as auth(FungibleToken.Withdraw) &{Source}?
        }
    }

    /* --- PUBLIC METHODS --- */

    /// Returns an AutoBalancer wrapping the provided Vault.
    ///
    /// @param oracle: The oracle used to query deposited & withdrawn value and to determine if a rebalance should execute
    /// @param vault: The Vault wrapped by the AutoBalancer
    /// @param rebalanceRange: The percentage range from the AutoBalancer's base value at which a rebalance is executed
    /// @param outSink: An optional DeFiActions Sink to which excess value is directed when rebalancing
    /// @param inSource: An optional DeFiActions Source from which value is withdrawn to the inner vault when rebalancing
    /// @param uniqueID: An optional DeFiActions UniqueIdentifier used for identifying rebalance events
    ///
    access(all) fun createAutoBalancer(
        oracle: {PriceOracle},
        vaultType: Type,
        lowerThreshold: UFix64,
        upperThreshold: UFix64,
        rebalanceSink: {Sink}?,
        rebalanceSource: {Source}?,
        uniqueID: UniqueIdentifier?
    ): @AutoBalancer {
        let ab <- create AutoBalancer(
            lower: lowerThreshold,
            upper: upperThreshold,
            oracle: oracle,
            vaultType: vaultType,
            outSink: rebalanceSink,
            inSource: rebalanceSource,
            uniqueID: uniqueID
        )
        return <- ab
    }

    /// Creates a new UniqueIdentifier used for identifying action stacks
    ///
    /// @return a new UniqueIdentifier
    ///
    access(all) fun createUniqueIdentifier(): UniqueIdentifier {
        let id = UniqueIdentifier(self.currentID, self.authTokenCap)
        self.currentID = self.currentID + 1
        return id
    }

    /// Aligns the UniqueIdentifier of the provided component with the provided component, setting the UniqueIdentifier of
    /// the provided component to the UniqueIdentifier of the provided component. Parameters are AnyStruct to allow for
    /// alignment of both IdentifiableStruct and IdentifiableResource. However, note that the provided component must
    /// be an auth(Extend) &{IdentifiableStruct} or auth(Extend) &{IdentifiableResource} to be aligned.
    ///
    /// @param toUpdate: The component to update the UniqueIdentifier of. Must be an auth(Extend) &{IdentifiableStruct}
    ///     or auth(Extend) &{IdentifiableResource}
    /// @param with: The component to align the UniqueIdentifier of the provided component with. Must be an
    ///     auth(Identify) &{IdentifiableStruct} or auth(Identify) &{IdentifiableResource}
    ///
    access(all) fun alignID(toUpdate: AnyStruct, with: AnyStruct) {
        let maybeISToUpdate = toUpdate as? auth(Extend) &{IdentifiableStruct}
        let maybeIRToUpdate = toUpdate as? auth(Extend) &{IdentifiableResource}
        let maybeISWith = with as? auth(Identify) &{IdentifiableStruct}
        let maybeIRWith = with as? auth(Identify) &{IdentifiableResource}

        if maybeISToUpdate != nil && maybeISWith != nil {
            maybeISToUpdate!.setID(maybeISWith!.copyID())
        } else if maybeISToUpdate != nil && maybeIRWith != nil {
            maybeISToUpdate!.setID(maybeIRWith!.copyID())
        } else if maybeIRToUpdate != nil && maybeISWith != nil {
            maybeIRToUpdate!.setID(maybeISWith!.copyID())
        } else if maybeIRToUpdate != nil && maybeIRWith != nil {
            maybeIRToUpdate!.setID(maybeIRWith!.copyID())
        }
        return
    }

    /* --- INTERNAL CONDITIONAL EVENT EMITTERS --- */

    /// Emits Deposited event if a change in balance is detected
    access(self) view fun emitDeposited(
        type: String,
        beforeBalance: UFix64,
        afterBalance: UFix64,
        fromUUID: UInt64,
        uniqueID: UInt64?,
        sinkType: String
    ): Bool {
        if beforeBalance == afterBalance {
            return true
        }
        emit Deposited(
            type: type,
            amount: beforeBalance > afterBalance ? beforeBalance - afterBalance : afterBalance - beforeBalance,
            fromUUID: fromUUID,
            uniqueID: uniqueID,
            sinkType: sinkType
        )
        return true
    }

    /// Emits Withdrawn event if a change in balance is detected
    access(self) view fun emitWithdrawn(
        type: String,
        amount: UFix64,
        withdrawnUUID: UInt64,
        uniqueID: UInt64?,
        sourceType: String
    ): Bool {
        if amount == 0.0 {
            return true
        }
        emit Withdrawn(
            type: type,
            amount: amount,
            withdrawnUUID: withdrawnUUID,
            uniqueID: uniqueID,
            sourceType: sourceType
        )
        return true
    }

    /// Emits Aligned event if a change in UniqueIdentifier is detected
    access(self) view fun emitUpdatedID(
        oldID: UInt64?,
        newID: UInt64?,
        component: String,
        uuid: UInt64?
    ): Bool {
        if oldID == newID {
            return true
        }
        emit UpdatedID(
            oldID: oldID,
            newID: newID,
            component: component,
            uuid: uuid
        )
        return true
    }

    init() {
        self.currentID = 0
        self.AuthTokenStoragePath = /storage/authToken

        self.account.storage.save(<-create AuthenticationToken(), to: self.AuthTokenStoragePath)
        self.authTokenCap = self.account.capabilities.storage.issue<auth(Identify) &AuthenticationToken>(self.AuthTokenStoragePath)

        assert(self.authTokenCap.check(), message: "Failed to issue AuthenticationToken Capability")
    }
}
