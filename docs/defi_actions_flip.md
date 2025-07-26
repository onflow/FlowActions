---
status: draft
flip: XXX
title: DeFiActions: Composable DeFi Standards for Flow
authors: Giovanni Sanchez (giovanni.sanchez@dapperlabs.com)
sponsor: [TO BE ASSIGNED]
updated: 2025-01-XX
---

# FLIP XXX: DeFiActions - Composable DeFi Standards for Flow

> Standardized interfaces enabling composition of common DeFi operations through pluggable, reusable components

<details>

<summary>Table of contents</summary>

- [FLIP XXX: DeFiActions - Composable DeFi Standards for Flow](#flip-xxx-defiactions---composable-defi-standards-for-flow)
  - [Objective](#objective)
  - [Motivation](#motivation)
  - [User Benefit](#user-benefit)
  - [Design Proposal](#design-proposal)
    - [Core Philosophy](#core-philosophy)
    - [Component Model Overview](#component-model-overview)
    - [Interfaces](#interfaces)
      - [Source Interface](#source-interface)
      - [Sink Interface](#sink-interface)
      - [Swapper Interface](#swapper-interface)
      - [PriceOracle Interface](#priceoracle-interface)
      - [Flasher Interface](#flasher-interface)
    - [Component Composition](#component-composition)
    - [Identification \& Traceability](#identification--traceability)
    - [Stack Introspection](#stack-introspection)
      - [Simple Stack Introspection Example](#simple-stack-introspection-example)
      - [Complex Stack Introspection Example](#complex-stack-introspection-example)
  - [Implementation Details](#implementation-details)
    - [Core Interfaces](#core-interfaces)
    - [Connector Examples](#connector-examples)
      - [FungibleToken Connectors](#fungibletoken-connectors)
      - [Swap Connectors](#swap-connectors)
      - [DEX Adapters](#dex-adapters)
      - [Flash Loan Adapters](#flash-loan-adapters)
    - [AutoBalancer Component](#autobalancer-component)
    - [Event System](#event-system)
  - [Use Cases](#use-cases)
    - [Automated Token Transmission](#automated-token-transmission)
  - [Considerations](#considerations)
    - [Security Model](#security-model)
    - [Performance Implications](#performance-implications)
    - [Testing Challenges](#testing-challenges)
    - [Drawbacks](#drawbacks)
  - [Compatibility](#compatibility)
  - [Future Extensions](#future-extensions)

</details>

## Objective

This proposal introduces DeFiActions (DFA), a suite of standardized Cadence interfaces that enable developers to compose complex DeFi workflows by connecting small, reusable components. DFA provides a "money LEGO" framework where each component performs a single DeFi operation (deposit, withdraw, swap, price lookup) while maintaining composability with other components to create sophisticated financial strategies executable in a single atomic transaction.

## Motivation

Flow's DeFi ecosystem currently lacks standardized interfaces for connecting protocols and creating complex workflows. Developers building applications that interact with multiple DeFi protocols face several challenges:

1. **Protocol Fragmentation**: Each DeFi protocol implements unique interfaces, requiring custom integration code and deep protocol-specific knowledge
<!-- Not so sure about wording or even the underlying concern in 2. -->
2. **Workflow Complexity**: Building multi-step DeFi strategies (like leverage, yield farming, or automated rebalancing) requires managing multiple protocol calls with custom error handling and state management
3. **Limited Composability**: Without shared interfaces, protocols cannot easily integrate with each other, limiting composability and increasing the barrier to entry for new developers
4. **Development Overhead**: Each application must implement protocol-specific logic, leading to duplicated effort and increased maintenance burden

DeFiActions addresses these challenges by providing a unified abstraction layer that makes DeFi protocols interoperable while maintaining the security and flexibility developers expect.

## User Benefit

DeFiActions provides significant benefits to different stakeholders in the Flow ecosystem:

**For Application Developers:**
- **Simplified Integration**: Connect to any DFA-compatible protocol through standardized interfaces
- **Rapid Prototyping**: Build complex DeFi workflows by composing pre-built components
- **Reduced Maintenance**: Protocol updates are abstracted away by adapter implementations, enabling more modular dependency architectures
- **Enhanced Functionality**: Create sophisticated strategies that would be complex to implement from scratch

**For Protocol Developers:**
- **Increased Adoption**: Protocols become instantly compatible with any DFA-built application by simply creating DFA connectors adapted to their protocol
- **Network Effects**: Benefit from integration work done by other protocols in the ecosystem and tapping into a community of DFA-focussed developers
<!-- Need to expand on this one -->
- **Innovation Platform**: Focus on protocol-specific logic rather than integration concerns

**For End Users:**
- **Advanced Strategies**: Access to sophisticated DeFi workflows through simple interfaces
- **Atomic Execution**: Complex multi-protocol operations execute in single transactions
- **Autonomous Operations**: Integration with scheduled callbacks enables self-executing strategies, enabling trustless active management

## Design Proposal

### Core Philosophy

DeFiActions is inspired by Unix terminal piping, where simple commands can be connected together to create complex workflows. Each DFA component is analogous to a Unix command:

- **Single Responsibility**: Each component performs one specific DeFi operation
- **Composable**: Shared standards in an open environment allow developers to reuse and remix actions built by others
- **Standardized**: All components of the same type implement identical interfaces
- **Graceful Failure**: Components handle edge cases gracefully rather than reverting

### Component Model Overview

DFA defines five core component types, each representing a fundamental DeFi operation:

1. **Source**: Provides tokens on demand (e.g. withdraw from vault, claim rewards, pull liquidity)
2. **Sink**: Accepts tokens up to capacity (e.g. deposit to vault, repay loan, add liquidity)  
3. **Swapper**: Exchanges one token type for another (e.g. targetted DEX trades, multi-protocol aggregated swaps)
4. **PriceOracle**: Provides price data for assets (e.g. external price feeds, DEX prices, price caching)
5. **Flasher**: Provides flash loans with atomic repayment (e.g. arbitrage, liquidations)

Additional specialized components build upon these primitives:

6. **AutoBalancer**: Automated rebalancing system that uses Sources, Sinks, and PriceOracles to maintain a token balance around the value of historical deposits, directing excess value to a Sink and topping up deficient value from a Source if either or both are configured
7. **Quote**: Data structure for swap price estimates and execution parameters, allowing Swapper consumers to cache swap quotes in either direction

### Interfaces

#### Source Interface

A Source provides while gracefully handling scenarios where the requested amount may not be fully available:

```cadence
access(all) resource interface Source : Identifiable {
    /// Returns the Vault type provided by this Source
    access(all) view fun getSourceType(): Type

    /// Returns an estimate of how much can be withdrawn
    access(all) fun minimumAvailable(): UFix64

    /// Withdraws up to maxAmount, returning what's actually available
    access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}
}
```

Key design principles:
- **Graceful Degradation**: Returns available amount rather than reverting when full amount unavailable
- **Predictable Interface**: Always returns a Vault, even if empty
- **Estimation**: Provides estimated amount available

#### Sink Interface

A Sink accepts tokens up to its capacity:

```cadence
access(all) resource interface Sink : Identifiable {
    /// Returns the Vault type accepted by this Sink
    access(all) view fun getSinkType(): Type
    
    /// Returns an estimate of remaining capacity
    access(all) fun minimumCapacity(): UFix64
    
    /// Deposits up to capacity, leaving remainder in source vault
    access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
}
```

Key design principles:
- **Capacity Management**: Only accepts tokens up to its current capacity
- **Non-destructive**: Excess tokens remain in the referenced `Vault`
- **Flexible Limits**: Capacity can be dynamic based on underlying recipient's capacity

#### Swapper Interface  

A Swapper exchanges tokens between different types with support for bidirectional swaps and price estimation:

```cadence
access(all) resource interface Swapper : Identifiable {
    /// Input and output token types
    access(all) view fun inType(): Type
    access(all) view fun outType(): Type
    
    /// Price estimation methods
    access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {Quote}
    access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {Quote}
    
    /// Swap execution methods
    access(all) fun swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault}
    access(all) fun swapBack(quote: {Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault}
}
```

Key design principles:
- **Bidirectional**: Supports swaps in both directions via `swapBack()`
- **Price Discovery**: Provides estimation before execution
- **Quote System**: Enables price caching and execution parameter optimization

#### PriceOracle Interface

A PriceOracle provides price data for assets with a consistent denomination:

```cadence
access(all) resource interface PriceOracle : Identifiable {
    /// Returns the denomination asset (e.g., USD, FLOW)
    access(all) view fun unitOfAccount(): Type
    
    /// Returns current price or nil if unavailable
    access(all) fun price(ofToken: Type): UFix64?
}
```

Key design principles:
- **Consistent Denomination**: All prices returned in the same unit of account
- **Graceful Unavailability**: Returns nil rather than reverting in the event a price is unavailable
- **Type-Based**: Prices indexed by Cadence Type for type safety

#### Flasher Interface

A Flasher provides flash loans with atomic repayment requirements:

```cadence
access(all) resource interface Flasher : Identifiable {
    /// Returns the asset type this Flasher can issue as a flash loan
    access(all) view fun borrowType(): Type
    
    /// Returns the estimated fee for a flash loan of the specified amount
    access(all) fun calculateFee(loanAmount: UFix64): UFix64
    
    /// Performs a flash loan of the specified amount. The callback function is passed the fee amount and a Vault
    /// containing the loan. The callback function should return a Vault containing the loan + fee.
    access(all) fun flashLoan(
        amount: UFix64,
        data: {String: AnyStruct},
        callback: fun(UFix64, @{FungibleToken.Vault}, {String: AnyStruct}): @{FungibleToken.Vault} // fee, loan, data
    )
}
```

Key design principles:
- **Atomic Repayment**: Loan must be repaid within the same transaction
- **Callback Pattern**: Consumer logic runs in provided function rather than separate components
- **Fee Transparency**: Implementations provide fee calculation before execution
- **Repayment Guarantee**: Implementers must validate full repayment (loan + fee) before transaction completion

**Design Rationale**: The callback function pattern was chosen over requiring separate Sink/Source components for several reasons:
- **Lighter Weight**: No contract deployment required to define flash loan logic
- **Competitive Advantage**: Transaction-scoped logic maintains user edge over permanent on-chain code
- **Consolidated Context**: Single execution scope rather than split between multiple components
- **Flexibility**: Implementations may still leverage Sink/Source connectors in callback scope, but they're not required

### Component Composition

<!-- TODO: This section needs some work - add in VaultSink/VaultSource, SwapSink/SwapSource, MultiSwapper implementations -->

Components are designed to connect seamlessly where compatible:

```cadence
// Example: Source -> Swapper -> Sink pipeline
let tokens <- source.withdrawAvailable(maxAmount: 100.0)
let swappedTokens <- swapper.swap(quote: nil, inVault: <-tokens)  
sink.depositCapacity(from: &swappedTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

Compositions include:
- **SwapSink**: Combines Swapper + Sink for automatic token conversion before deposit (e.g. deposit to SwapSink as TokenA, swap to TokenB and deposit TokenB to inner Sink)
- **SwapSource**: Combines Source + Swapper for automatic token conversion after withdrawal (e.g. initiate withdrawal of TokenA, withdraw from inner Source as TokenB, swap to TokenA and return the swapped result)
- **MultiSwapper**: Aggregates multiple Swappers to find optimal pricing

### Identification & Traceability

All DFA components implement the `Identifiable` interface, which includes an optional `UniqueIdentifier` resource for operation tracing:

```cadence
access(all) resource interface Identifiable {
    /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
    /// specific Identifier to associated connectors on construction
    access(contract) var uniqueID: @UniqueIdentifier?
    /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
    ///
    /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
    /// for critical identification unless the implementation itself is known and trusted
    access(all) view fun id(): UInt64? {
        return self.uniqueID?.id
    }
    /// Returns a list of ComponentInfo for each component in the stack. This list should be ordered from the outer
    /// to the inner components, traceable by the innerComponents map.
    access(all) fun getStackInfo(): [ComponentInfo]
    /// Aligns the UniqueIdentifier of this component with the provided component, destroying the old
    /// UniqueIdentifier
    access(Extend) fun alignID(with: auth(Extend) &{Identifiable}) {
        post {
            self.uniqueID?.id == with.uniqueID?.id:
            "UniqueIdentifier of \(self.getType().identifier) was not successfully aligned with \(with.getType().identifier)"
        }
        if self.uniqueID?.id == with.uniqueID?.id {
            return // already share the same ID value
        }

        let old <- self.uniqueID <- with.uniqueID?.copy()
        emit Aligned(
            oldID: old?.id,
            newID: self.uniqueID?.id,
            component: self.getType().identifier,
            with: with.getType().identifier,
            uuid: self.uuid
        )
        Burner.burn(<-old)
    }
}
```

This enables:
- **Event Correlation**: All component operations emit events tagged with the same ID
- **Stack Tracing**: Understanding the complete component chain
- **Analytics**: Tracking complex workflow performance and usage patterns

> :information_source: Note that core components are proposed as resources. This is largely influenced by event traceability requirement. If the `UniqueIdentifier` was a struct, then one could forge another value by passing a `UniqueIdentifier` with arbitrary `id` value into a transaction, thus spoofing another stack's event operations and making the `id` value untrustworthy. Resources are the ideal construct type for this use case, since resources are inherently unforgeable. Subsequently, as structs cannot capture resources, the choice to make `UniqueIdentifier` a resource also introduces a design constraint that forces all identified DFA components to also be resources.

### Stack Introspection

Components can be inspected to understand their composition via `Identifiable.getStackInfo(): [ComponentInfo]`:

```cadence
access(all) struct ComponentInfo {
    /// The type of the component
    access(all) let type: Type
    /// The unique identifier of the component
    access(all) let uuid: UInt64
    /// The identifier of the component
    access(all) let id: UInt64?
    /// A map of inner component types keyed on their their resource.uuid, creating a link between the outer and
    /// inner components
    access(all) let innerComponents: {UInt64: Type}
}
```

This allows:
- **Dynamic Workflow Analysis**: Understanding component relationships programmatically
- **Debugging Support**: Identifying which components are involved in complex operations

> :information_source: Due to the implementation-specific nature of DFA connectors, it's not possible to provide a default implementation at the interface level that would satisfy all connectors nor guarantee through pre-post conditions that `ComponentInfo.innerComponents` preserves correct and/or standard formatting. Similar to NFT metadata, it's therefore the responsibility of the developer to ensure the method is implemented correctly, requiring trust on the part of the consumer.

#### Simple Stack Introspection Example

The FungibleTokenStack VaultSink is a simple sink just direct deposited funds to a Vault via Capability, so it has not inner commponents.

```cadence
access(all) resource VaultSink : DeFiActions.Sink {
    // ...
    /// Simply returns info about itself
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        return [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {}
        )]
    }
    // ...
}
```

#### Complex Stack Introspection Example

The AutoBalancer contains at minimum a PriceOracle, but can also optionally include a Sink (to direct excess value) and Source (to top up deficient value). Introspection results should then include not only the AutoBalancer's `ComponentInfo`, but also the `ComponentInfo` of each contained connector and any connectors those may also contain. The hierarchy of each element can be inferred from the `innerComponents` mapping, identified by the UUID of each.

```cadence
access(all) resource AutoBalancer : DeFiActions.Sink {
    // ...
    ///
    access(all) fun getStackInfo(): [ComponentInfo] {
        let inner: {UInt64: Type} = {}

        // add the PriceOracle to inner components
        let oracle = self._borrowOracle()
        inner[oracle.uuid] = oracle.getType()

        // get the info for the optional inner components if they exist
        let res: [ComponentInfo] = oracle.getStackInfo()
        let maybeSink = self._borrowSink()
        let maybeSource = self._borrowSource()
        if let sink = maybeSink {
            inner[sink.uuid] = sink.getType()
            res.appendAll(sink.getStackInfo())
        }
        if let source = maybeSource {
            inner[source.uuid] = source.getType()
            res.appendAll(source.getStackInfo())
        }

        // create the ComponentInfo for the AutoBalancer and insert it at the beginning of the list as root
        res.insert(at: 0, ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: inner
        ))

        return res
    }
    // ...
}
```

## Implementation Details

### Core Interfaces

The complete DeFiActions interface specification includes:

<details>
<summary>Full Interface Code</summary>

```cadence
access(all) contract DeFiActions {
    
    // Core identification system
    access(all) resource UniqueIdentifier {
        access(all) let id: UInt64
        access(all) fun copy(): @UniqueIdentifier
    }
    
    access(all) resource interface Identifiable {
        access(contract) var uniqueID: @UniqueIdentifier?
        access(all) view fun id(): UInt64?
        access(all) fun getStackInfo(): [ComponentInfo]
    }
    
    // Component metadata
    access(all) struct ComponentInfo {
        access(all) let type: Type
        access(all) let uuid: UInt64
        access(all) let id: UInt64?
        access(all) let innerComponents: {UInt64: Type}
    }
    
    // Core DeFi interfaces
    access(all) resource interface Source : Identifiable {
        access(all) view fun getSourceType(): Type
        access(all) fun minimumAvailable(): UFix64
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}
    }
    
    access(all) resource interface Sink : Identifiable {
        access(all) view fun getSinkType(): Type
        access(all) fun minimumCapacity(): UFix64
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
    }
    /// An interface for an estimate to be returned by a Swapper when asking for a swap estimate. This may be helpful
    /// for passing additional parameters to a Swapper relevant to the use case. Implementations may choose to add
    /// fields relevant to their Swapper implementation and downcast in swap() and/or swapBack() scope.
    access(all) struct interface Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64
    }
    /// A basic interface for a struct that swaps between tokens. Implementations may choose to adapt this interface
    /// to fit any given swap protocol or set of protocols.
    access(all) resource interface Swapper : Identifiable {
        access(all) view fun inType(): Type
        access(all) view fun outType(): Type
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {Quote}
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {Quote}
        access(all) fun swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault}
        access(all) fun swapBack(quote: {Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault}
    }
    /// An interface for a price oracle adapter. Implementations should adapt this interface to various price feed
    /// oracles deployed on Flow
    access(all) resource interface PriceOracle : Identifiable {
        access(all) view fun unitOfAccount(): Type
        access(all) fun price(ofToken: Type): UFix64?
    }
    /// An interface for a flash loan adapter. Implementations should adapt this interface to various flash loan
    /// protocols deployed on Flow
    access(all) resource interface Flasher : Identifiable {
        access(all) view fun borrowType(): Type
        access(all) fun calculateFee(loanAmount: UFix64): UFix64
        access(all) fun flashLoan(
            amount: UFix64,
            data: {String: AnyStruct},
            callback: fun(UFix64, @{FungibleToken.Vault}, {String: AnyStruct}): @{FungibleToken.Vault} // fee, loan, data
        )
    }
    /// A DeFiActions Sink enabling the deposit of funds to an underlying AutoBalancer resource. As written, this Source
    /// may be used with externally defined AutoBalancer implementations
    access(all) resource AutoBalancerSink {
        // Concrete Sink implementation directing funds to an underlying AutoBalancer
    }
    /// A DeFiActions Source targeting an underlying AutoBalancer resource. As written, this Source may be used with
    /// externally defined AutoBalancer implementations
    access(all) resource AutoBalancerSource {
        // Concrete Source implementation directing funds from an underlying AutoBalancer
    }
    /// A resource designed to enable permissionless rebalancing of value around a wrapped Vault. An
    /// AutoBalancer can be a critical component of DeFiActions stacks by allowing for strategies to compound, repay
    /// loans or direct accumulated value to other sub-systems and/or user Vaults.
    access(all) resource AutoBalancer : Identifiable, FungibleToken.Receiver, FungibleToken.Provider, ViewResolver.Resolver, Burner.Burnable {
        /// The value in deposits & withdrawals over time denominated in oracle.unitOfAccount()
        access(self) var _valueOfDeposits: UFix64
        /// The percentage low and high thresholds defining when a rebalance executes
        /// Index 0 is low, index 1 is high
        access(self) var _rebalanceRange: [UFix64; 2]
        /// Oracle used to track the baseValue for deposits & withdrawals over time
        access(self) let _oracle: @{PriceOracle}
        /// The inner Vault's Type captured for the ResourceDestroyed event
        access(self) let _vaultType: Type
        /// Vault used to deposit & withdraw from made optional only so the Vault can be burned via Burner.burn() if the
        /// AutoBalancer is burned and the Vault's burnCallback() can be called in the process
        access(self) var _vault: @{FungibleToken.Vault}?
        /// An optional Sink used to deposit excess funds from the inner Vault once the converted value exceeds the
        /// rebalance range. This Sink may be used to compound yield into a position or direct excess value to an
        /// external Vault
        access(self) var _rebalanceSink: @{Sink}?
        /// An optional Source used to deposit excess funds to the inner Vault once the converted value is below the
        /// rebalance range
        access(self) var _rebalanceSource: @{Source}?
        /// Capability on this AutoBalancer instance
        access(self) var _selfCap: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>?
        /// An optional UniqueIdentifier tying this AutoBalancer to a given stack
        access(contract) var uniqueID: @UniqueIdentifier?

        /// Emitted when the AutoBalancer is destroyed
        access(all) event ResourceDestroyed(
            uuid: UInt64 = self.uuid,
            vaultType: String = self._vaultType.identifier,
            balance: UFix64? = self._vault?.balance,
            uniqueID: UInt64? = self.uniqueID?.id
        )

        /* Core AutoBalancer Functionality */

        /// Returns the balance of the inner Vault
        access(all) view fun vaultBalance(): UFix64
        /// Returns the Type of the inner Vault
        access(all) view fun vaultType(): Type
        /// Returns the low and high rebalance thresholds as a fixed length UFix64 containing [low, high]
        access(all) view fun rebalanceThresholds(): [UFix64; 2]
        /// Returns the value of all accounted deposits/withdraws as they have occurred denominated in unitOfAccount.
        /// The returned value is the value as tracked historically, not necessarily the current value of the inner
        /// Vault's balance.
        access(all) view fun valueOfDeposits(): UFix64
        /// Returns the token Type serving as the price basis of this AutoBalancer
        access(all) view fun unitOfAccount(): Type
        /// Returns the current value of the inner Vault's balance. If a price is not available from the AutoBalancer's
        /// PriceOracle, `nil` is returned
        access(all) fun currentValue(): UFix64?
        /// Returns a list of ComponentInfo for each component in the stack
        access(all) fun getStackInfo(): [ComponentInfo]
        /// Convenience method issuing a Sink allowing for deposits to this AutoBalancer. If the AutoBalancer's
        /// Capability on itself is not set or is invalid, `nil` is returned.
        access(all) fun createBalancerSink(): @{Sink}?
        /// Convenience method issuing a Source enabling withdrawals from this AutoBalancer. If the AutoBalancer's
        /// Capability on itself is not set or is invalid, `nil` is returned.
        access(Get) fun createBalancerSource(): @{Source}?
        /// A setter enabling an AutoBalancer to set a Sink to which overflow value should be deposited
        access(Set) fun setSink(_ sink: @{Sink}?, align: Bool)
        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn
        access(Set) fun setSource(_ source: @{Source}?, align: Bool)
        /// Enables the setting of a Capability on the AutoBalancer for the distribution of Sinks & Sources targeting
        /// the AutoBalancer instance. Due to the mechanisms of Capabilities, this must be done after the AutoBalancer
        /// has been saved to account storage and an authorized Capability has been issued. Setting the self Capability
        /// also enables the AutoBalancer to schedule callbacks, enabling auto-rebalance functionality.
        access(Set) fun setSelfCapability(_ cap: Capability<auth(FungibleToken.Withdraw) &AutoBalancer>)
        /// Sets the rebalance range of this AutoBalancer
        access(Set) fun setRebalanceRange(_ range: [UFix64; 2])
        /// Allows for external parties to call on the AutoBalancer and execute a rebalance according to it's rebalance
        /// parameters. This method must be called by external party regularly in order for rebalancing to occur.
        access(Auto) fun rebalance(force: Bool)

        /* ViewResolver.Resolver conformance */

        /// Passthrough to inner Vault's view Types
        access(all) view fun getViews(): [Type]
        /// Passthrough to inner Vault's view resolution
        access(all) fun resolveView(_ view: Type): AnyStruct? 

        /* FungibleToken.Receiver & .Provider conformance */

        /// Only the nested Vault type is supported by this AutoBalancer for deposits & withdrawal for the sake of
        /// single asset accounting
        access(all) view fun getSupportedVaultTypes(): {Type: Bool}
        /// True if the provided Type is the nested Vault Type, false otherwise
        access(all) view fun isSupportedVaultType(type: Type): Bool
        /// Passthrough to the inner Vault's isAvailableToWithdraw() method
        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool
        /// Deposits the provided Vault to the nested Vault if it is of the same Type, reverting otherwise. In the
        /// process, the current value of the deposited amount (denominated in unitOfAccount) increments the
        /// AutoBalancer's baseValue. If a price is not available via the internal PriceOracle, an average price is
        /// calculated base on the inner vault balance & valueOfDeposits and valueOfDeposits is incremented by the
        /// value of the deposited vault on the basis of that average
        access(all) fun deposit(from: @{FungibleToken.Vault})
        /// Returns the requested amount of the nested Vault type, reducing the baseValue by the current value
        /// (denominated in unitOfAccount) of the token amount. The AutoBalancer's valueOfDeposits is decremented
        /// in proportion to the amount withdrawn relative to the inner Vault's balance
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault}

        /* Burnable.Burner conformance */

        /// Executed in Burner.burn(). Passes along the inner vault to be burned, executing the inner Vault's
        /// burnCallback() logic
        access(contract) fun burnCallback()

        /* Internal */

        /// Returns a reference to the inner Vault
        access(self) view fun _borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        /// Returns a reference to the inner Vault
        access(self) view fun _borrowOracle(): &{PriceOracle}
        /// Returns a reference to the inner Vault
        access(self) view fun _borrowSink(): &{Sink}?
        /// Returns a reference to the inner Source
        access(self) view fun _borrowSource(): auth(FungibleToken.Withdraw) &{Source}?
    }
}
```

</details>

### Connector Examples

#### FungibleToken Connectors

Basic connectors for interacting with standard FungibleToken Vaults:

<details>

<summary>VaultSink & VaultSource implementations</summary>

```cadence
access(all) resource VaultSink : DeFiActions.Sink {
    /// The Vault Type accepted by the Sink
    access(all) let depositVaultType: Type
    /// The maximum balance of the linked Vault, checked before executing a deposit
    access(all) let maximumBalance: UFix64
    /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
    /// specific Identifier to associated connectors on construction
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?
    /// An unentitled Capability on the Vault to which deposits are distributed
    access(self) let depositVault: Capability<&{FungibleToken.Vault}>

    init(
        max: UFix64?,
        depositVault: Capability<&{FungibleToken.Vault}>,
        uniqueID: @DeFiActions.UniqueIdentifier?
    ) {
        pre {
            depositVault.check(): "Provided invalid Capability"
            DeFiActionsUtils.definingContractIsFungibleToken(depositVault.borrow()!.getType()):
            "The contract defining Vault \(depositVault.borrow()!.getType().identifier) does not conform to FungibleToken contract interface"
        }
        self.maximumBalance = max ?? UFix64.max // assume no maximum if none provided
        self.uniqueID <- uniqueID
        self.depositVaultType = depositVault.borrow()!.getType()
        self.depositVault = depositVault
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        return [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {}
        )]
    }
    /// Returns the Vault type accepted by this Sink
    access(all) view fun getSinkType(): Type {
        return self.depositVaultType
    }
    /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
    access(all) fun minimumCapacity(): UFix64 {
        if let vault = self.depositVault.borrow() {
            return vault.balance < self.maximumBalance ? self.maximumBalance - vault.balance : 0.0
        }
        return 0.0
    }
    /// Deposits up to the Sink's capacity from the provided Vault
    access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
        let minimumCapacity = self.minimumCapacity()
        if !self.depositVault.check() || minimumCapacity == 0.0 {
            return
        }
        // deposit the lesser of the originating vault balance and minimum capacity
        let capacity = minimumCapacity <= from.balance ? minimumCapacity : from.balance
        self.depositVault.borrow()!.deposit(from: <-from.withdraw(amount: capacity))
    }
}

access(all) resource VaultSource : DeFiActions.Source {
    /// Returns the Vault type provided by this Source
    access(all) let withdrawVaultType: Type
    /// The minimum balance of the linked Vault
    access(all) let minimumBalance: UFix64
    /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
    /// specific Identifier to associated connectors on construction
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?
    /// An entitled Capability on the Vault from which withdrawals are sourced
    access(self) let withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>

    init(
        min: UFix64?,
        withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
        uniqueID: @DeFiActions.UniqueIdentifier?
    ) {
        pre {
            withdrawVault.check(): "Provided invalid Capability"
            DeFiActionsUtils.definingContractIsFungibleToken(withdrawVault.borrow()!.getType()):
            "The contract defining Vault \(withdrawVault.borrow()!.getType().identifier) does not conform to FungibleToken contract interface"
        }
        self.minimumBalance = min ?? 0.0 // assume no minimum if none provided
        self.withdrawVault = withdrawVault
        self.uniqueID <- uniqueID
        self.withdrawVaultType = withdrawVault.borrow()!.getType()
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        return [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {}
        )]
    }
    /// Returns the Vault type provided by this Source
    access(all) view fun getSourceType(): Type {
        return self.withdrawVaultType
    }
    /// Returns an estimate of how much of the associated Vault can be provided by this Source
    access(all) fun minimumAvailable(): UFix64 {
        if let vault = self.withdrawVault.borrow() {
            return self.minimumBalance < vault.balance ? vault.balance - self.minimumBalance : 0.0
        }
        return 0.0
    }
    /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
    /// returned
    access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
        let available = self.minimumAvailable()
        if !self.withdrawVault.check() || available == 0.0 || maxAmount == 0.0 {
            return <- DeFiActionsUtils.getEmptyVault(self.withdrawVaultType)
        }
        // take the lesser between the available and maximum requested amount
        let withdrawalAmount = available <= maxAmount ? available : maxAmount
        return <- self.withdrawVault.borrow()!.withdraw(amount: withdrawalAmount)
    }
}
```
</details>

#### Swap Connectors

Connectors that combine swapping with other actions:

<details>
<summary>SwapSink & SwapSource implementations</summary>

```cadence
/// SwapSink DeFiActions connector that deposits the resulting post-conversion currency of a token swap to an inner
/// DeFiActions Sink, sourcing funds from a deposited Vault of a pre-set Type.
access(all) resource SwapSink : DeFiActions.Sink {
    access(self) let swapper: @{DeFiActions.Swapper}
    access(self) let sink: @{DeFiActions.Sink}
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?

    init(swapper: @{DeFiActions.Swapper}, sink: @{DeFiActions.Sink}, uniqueID: @DeFiActions.UniqueIdentifier?) {
        pre {
            swapper.outType() == sink.getSinkType():
            "Swapper outputs \(swapper.outType().identifier) but Sink takes \(sink.getSinkType().identifier) - "
                .concat("Ensure the provided Swapper outputs a Vault Type compatible with the provided Sink")
        }
        self.swapper <- swapper
        self.sink <- sink
        self.uniqueID <- uniqueID
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        let res = [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {
                self.swapper.uuid: self.swapper.getType(),
                self.sink.uuid: self.sink.getType()
            }
        )]
        res.appendAll(self.swapper.getStackInfo())
        res.appendAll(self.sink.getStackInfo())
        return res
    }
    access(all) view fun getSinkType(): Type {
        return self.swapper.inType()
    }
    access(all) fun minimumCapacity(): UFix64 {
        return self.swapper.quoteIn(forDesired: self.sink.minimumCapacity(), reverse: false).inAmount
    }
    access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
        let limit = self.sink.minimumCapacity()
        if from.balance == 0.0 || limit == 0.0 || from.getType() != self.getSinkType() {
            return // nothing to swap from, no capacity to ingest, invalid Vault type - do nothing
        }

        let quote = self.swapper.quoteIn(forDesired: limit, reverse: false)
        let swapVault <- from.createEmptyVault()
        if from.balance <= quote.inAmount  {
            // sink can accept all of the available tokens, so we swap everything
            swapVault.deposit(from: <-from.withdraw(amount: from.balance))
        } else {
            // sink is limited to fewer tokens than we have available - swap the amount we need to meet the limit
            swapVault.deposit(from: <-from.withdraw(amount: quote.inAmount))
        }

        // swap then deposit to the inner sink
        let swappedTokens <- self.swapper.swap(quote: quote, inVault: <-swapVault)
        self.sink.depositCapacity(from: &swappedTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

        if swappedTokens.balance > 0.0 {
            // swap back any residual to the originating vault
            let residual <- self.swapper.swapBack(quote: nil, residual: <-swappedTokens)
            from.deposit(from: <-residual)
        } else {
            Burner.burn(<-swappedTokens) // nothing left - burn & execute vault's burnCallback()
        }
    }
}

/// SwapSource DeFiActions connector that returns post-conversion currency, sourcing pre-converted funds from an inner
/// DeFiActions Source
access(all) resource SwapSource : DeFiActions.Source {
    access(self) let swapper: @{DeFiActions.Swapper}
    access(self) let source: @{DeFiActions.Source}
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?

    init(swapper: @{DeFiActions.Swapper}, source: @{DeFiActions.Source}, uniqueID: @DeFiActions.UniqueIdentifier?) {
        pre {
            source.getSourceType() == swapper.inType():
            "Source outputs \(source.getSourceType().identifier) but Swapper takes \(swapper.inType().identifier) - "
                .concat("Ensure the provided Source outputs a Vault Type compatible with the provided Swapper")
        }
        self.swapper <- swapper
        self.source <- source
        self.uniqueID <- uniqueID
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        let res = [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {
                self.swapper.uuid: self.swapper.getType(),
                self.source.uuid: self.source.getType()
            }
        )]
        res.appendAll(self.swapper.getStackInfo())
        res.appendAll(self.source.getStackInfo())
        return res
    }
    access(all) view fun getSourceType(): Type {
        return self.swapper.outType()
    }
    access(all) fun minimumAvailable(): UFix64 {
        // estimate post-conversion currency based on the source's pre-conversion balance available
        let availableIn = self.source.minimumAvailable()
        return availableIn > 0.0
            ? self.swapper.quoteOut(forProvided: availableIn, reverse: false).outAmount
            : 0.0
    }
    access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
        let minimumAvail = self.minimumAvailable()
        if minimumAvail == 0.0 || maxAmount == 0.0 {
            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }

        // expect output amount as the lesser between the amount available and the maximum amount
        var amountOut = minimumAvail < maxAmount ? minimumAvail : maxAmount

        // find out how much liquidity to gather from the inner Source
        let availableIn = self.source.minimumAvailable()
        let quote = self.swapper.quoteIn(forDesired: amountOut, reverse: false)
        let quoteIn = availableIn < quote.inAmount ? availableIn : quote.inAmount

        let sourceLiquidity <- self.source.withdrawAvailable(maxAmount: quoteIn)
        if sourceLiquidity.balance == 0.0 {
            Burner.burn(<-sourceLiquidity)
            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }
        let outVault <- self.swapper.swap(quote: quote, inVault: <-sourceLiquidity)
        return <- outVault
    }
}
```
</details>

#### DEX Adapters

Since DFA acts as an abstraction layer above DeFi protocols on Flow across both Cadence and EVM, protocols may be adapted for use in DFA workflows. Below are two examples - one specific to IncrementFi, the largest Cadence-based DeFi protocol, and another generically suited for UniswapV2 EVM-based protocols.

<details>
<summary>IncrementFi Swapper implementation</summary>

```cadence
/// An implementation of DeFiActions.Swapper connector that swaps between tokens using IncrementFi's
/// SwapRouter contract
access(all) resource Swapper : DeFiActions.Swapper {
    /// A swap path as defined by IncrementFi's SwapRouter
    ///  e.g. [A.f8d6e0586b0a20c7.FUSD, A.f8d6e0586b0a20c7.FlowToken, A.f8d6e0586b0a20c7.USDC]
    access(all) let path: [String]
    /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
    /// specific Identifier to associated connectors on construction
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?
    /// The pre-conversion currency accepted for a swap
    access(self) let inVault: Type
    /// The post-conversion currency returned by a swap
    access(self) let outVault: Type

    init(
        path: [String],
        inVault: Type,
        outVault: Type,
        uniqueID: @DeFiActions.UniqueIdentifier?
    ) {
        pre {
            path.length >= 2:
            "Provided path must have a length of at least 2 - provided path has \(path.length) elements"
        }
        IncrementFiAdapters._validateSwapperInitArgs(path: path, inVault: inVault, outVault: outVault)

        self.path = path
        self.inVault = inVault
        self.outVault = outVault
        self.uniqueID <- uniqueID
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        return [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {}
        )]
    }
    /// The type of Vault this Swapper accepts when performing a swap
    access(all) view fun inType(): Type {
        return self.inVault
    }
    /// The type of Vault this Swapper provides when performing a swap
    access(all) view fun outType(): Type {
        return self.outVault
    }
    /// The estimated amount required to provide a Vault with the desired output balance
    access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
        let amountsIn = SwapRouter.getAmountsIn(amountOut: forDesired, tokenKeyPath: reverse ? self.path.reverse() : self.path)
        return SwapStack.BasicQuote(
            inType: reverse ? self.outType() : self.inType(),
            outType: reverse ? self.inType() : self.outType(),
            inAmount: amountsIn.length == 0 ? 0.0 : amountsIn[0],
            outAmount: forDesired
        )
    }
    /// The estimated amount delivered out for a provided input balance
    access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
        let amountsOut = SwapRouter.getAmountsOut(amountIn: forProvided, tokenKeyPath: reverse ? self.path.reverse() : self.path)
        return SwapStack.BasicQuote(
            inType: reverse ? self.outType() : self.inType(),
            outType: reverse ? self.inType() : self.outType(),
            inAmount: forProvided,
            outAmount: amountsOut.length == 0 ? 0.0 : amountsOut[amountsOut.length - 1]
        )
    }
    /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
    /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
    /// to use multiple Flow swap protocols.
    access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
        let amountOut = self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
        return <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-inVault,
            amountOutMin: amountOut,
            tokenKeyPath: self.path,
            deadline: getCurrentBlock().timestamp
        )
    }
    /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
    /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
    /// to use multiple Flow swap protocols.
    access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
        let amountOut = self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
        return <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-residual,
            amountOutMin: amountOut,
            tokenKeyPath: self.path.reverse(),
            deadline: getCurrentBlock().timestamp
        )
    }
}
```
</details>

<details>

<summary>UniswapV2 Swapper implementation</summary>

```cadence
/// Adapts an EVM-based UniswapV2Router contract's primary functionality to DeFiActions.Swapper adapter interface
access(all) resource UniswapV2EVMSwapper : DeFiActions.Swapper {
    /// UniswapV2Router contract's EVM address
    access(all) let routerAddress: EVM.EVMAddress
    /// A swap path defining the route followed for facilitated swaps. Each element should be a valid token address
    /// for which there is a pool available with the previous and subsequent token address via the defined Router
    access(all) let addressPath: [EVM.EVMAddress]
    /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
    /// specific Identifier to associated connectors on construction
    access(contract) var uniqueID: @DeFiActions.UniqueIdentifier?
    /// The pre-conversion currency accepted for a swap
    access(self) let inVault: Type
    /// The post-conversion currency returned by a swap
    access(self) let outVault: Type
    /// An authorized Capability on the CadenceOwnedAccount which this Swapper executes swaps on behalf of
    access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

    init(
        routerAddress: EVM.EVMAddress,
        path: [EVM.EVMAddress],
        inVault: Type,
        outVault: Type,
        coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
        uniqueID: @DeFiActions.UniqueIdentifier?
    ) {
        pre {
            path.length >= 2: "Provided path with length of \(path.length) - path must contain at least two EVM addresses)"
            FlowEVMBridgeConfig.getTypeAssociated(with: path[0]) == inVault:
            "Provided inVault \(inVault.identifier) is not associated with ERC20 at path[0] \(path[0].toString()) - "
                .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
            FlowEVMBridgeConfig.getTypeAssociated(with: path[path.length - 1]) == outVault: 
            "Provided outVault \(outVault.identifier) is not associated with ERC20 at path[\(path.length - 1)] \(path[path.length - 1].toString()) - "
                .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
            coaCapability.check():
            "Provided COA Capability is invalid - provided an active, unrevoked Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>"
        }
        self.routerAddress = routerAddress
        self.addressPath = path
        self.uniqueID <- uniqueID
        self.inVault = inVault
        self.outVault = outVault
        self.coaCapability = coaCapability
    }

    /// Returns a list of ComponentInfo for each component in the stack
    access(all) fun getStackInfo(): [DeFiActions.ComponentInfo] {
        return [DeFiActions.ComponentInfo(
            type: self.getType(),
            uuid: self.uuid,
            id: self.id() ?? nil,
            innerComponents: {}
        )]
    }
    /// The type of Vault this Swapper accepts when performing a swap
    access(all) view fun inType(): Type {
        return self.inVault
    }
    /// The type of Vault this Swapper provides when performing a swap
    access(all) view fun outType(): Type {
        return self.outVault
    }
    /// The estimated amount required to provide a Vault with the desired output balance returned as a BasicQuote
    /// struct containing the in and out Vault types and quoted in and out amounts
    /// NOTE: Cadence only supports decimal precision of 8
    access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
        let amountIn = self.getAmount(out: false, amount: forDesired, path: reverse ? self.addressPath.reverse() : self.addressPath)
        return SwapStack.BasicQuote(
            inType: reverse ? self.outType() : self.inType(),
            outType: reverse ? self.inType() : self.outType(),
            inAmount: amountIn != nil ? amountIn! : 0.0,
            outAmount: amountIn != nil ? forDesired : 0.0
        )
    }
    /// The estimated amount delivered out for a provided input balance returned as a BasicQuote returned as a
    /// BasicQuote struct containing the in and out Vault types and quoted in and out amounts
    /// NOTE: Cadence only supports decimal precision of 8
    access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
        let amountOut = self.getAmount(out: true, amount: forProvided, path: reverse ? self.addressPath.reverse() : self.addressPath)
        return SwapStack.BasicQuote(
            inType: reverse ? self.outType() : self.inType(),
            outType: reverse ? self.inType() : self.outType(),
            inAmount: amountOut != nil ? forProvided : 0.0,
            outAmount: amountOut != nil ? amountOut! : 0.0
        )
    }
    /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. This implementation swaps
    /// along a path defined on init routing the swap to the pre-defined UniswapV2Router implementation on Flow EVM.
    /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
    /// used.
    /// NOTE: Cadence only supports decimal precision of 8
    access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
        let amountOutMin = quote?.outAmount ?? self.quoteOut(forProvided: inVault.balance, reverse: true).outAmount
        return <-self.swapExactTokensForTokens(exactVaultIn: <-inVault, amountOutMin: amountOutMin, reverse: false)
    }
    /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
    /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
    /// to use multiple Flow swap protocols.
    /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
    /// used.
    /// NOTE: Cadence only supports decimal precision of 8
    access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
        let amountOutMin = quote?.outAmount ?? self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
        return <-self.swapExactTokensForTokens(
            exactVaultIn: <-residual,
            amountOutMin: amountOutMin,
            reverse: true
        )
    }
    /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
    /// returning the final output Vault
    access(self) fun swapExactTokensForTokens(
        exactVaultIn: @{FungibleToken.Vault},
        amountOutMin: UFix64,
        reverse: Bool
    ): @{FungibleToken.Vault} {
        let id = self.uniqueID?.id?.toString() ?? "UNASSIGNED"
        let idType = self.uniqueID?.getType()?.identifier ?? "UNASSIGNED"
        let coa = self.borrowCOA()
            ?? panic("The COA Capability contained by Swapper \(self.getType().identifier) with UniqueIdentifier "
                .concat("\(idType) ID \(id) is invalid - cannot perform an EVM swap without a valid COA Capability"))

        // withdraw FLOW from the COA to cover the VM bridge fee
        let bridgeFeeBalance = EVM.Balance(attoflow: 0)
        bridgeFeeBalance.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 128)) // bridging to EVM then from EVM, hence factor of 2
        let feeVault <- coa.withdraw(balance: bridgeFeeBalance)
        let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        // bridge the provided to the COA's EVM address
        let inTokenAddress = reverse ? self.addressPath[self.addressPath.length - 1] : self.addressPath[0]
        let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
            exactVaultIn.balance,
            erc20Address: inTokenAddress
        )
        coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeVaultRef)

        // approve the router to swap tokens
        var res = self.call(to: inTokenAddress,
            signature: "approve(address,uint256)",
            args: [self.routerAddress, evmAmountIn],
            gasLimit: 15_000_000,
            value: 0,
            dryCall: false
        )!
        if res.status != EVM.Status.successful {
            DeFiActionsEVMAdapters._callError("approve(address,uint256)",
                res, inTokenAddress, idType, id, self.getType())
        }
        // perform the swap
        res = self.call(to: self.routerAddress,
            signature: "swapExactTokensForTokens(uint,uint,address[],address,uint)", // amountIn, amountOutMin, path, to, deadline (timestamp)
            args: [evmAmountIn, UInt256(0), (reverse ? self.addressPath.reverse() : self.addressPath), coa.address(), UInt256(getCurrentBlock().timestamp)],
            gasLimit: 15_000_000,
            value: 0,
            dryCall: false
        )!
        if res.status != EVM.Status.successful {
            // revert because the funds have already been deposited to the COA - a no-op would leave the funds in EVM
            DeFiActionsEVMAdapters._callError("swapExactTokensForTokens(uint,uint,address[],address,uint)",
                res, self.routerAddress, idType, id, self.getType())
        }
        let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)
        let amountsOut = decoded[0] as! [UInt256]

        // withdraw tokens from EVM
        let outVault <- coa.withdrawTokens(type: self.outType(),
                amount: amountsOut[amountsOut.length - 1],
                feeProvider: feeVaultRef
            )

        // clean up the remaining feeVault & return the swap output Vault
        self.handleRemainingFeeVault(<-feeVault)
        return <- outVault
    }

    /* --- Internal --- */

    /// Internal method used to retrieve router.getAmountsIn and .getAmountsOut estimates. The returned array is the
    /// estimate returned from the router where each value is a swapped amount corresponding to the swap along the
    /// provided path.
    access(self) fun getAmount(out: Bool, amount: UFix64, path: [EVM.EVMAddress]): UFix64? {
        let callRes = self.call(to: self.routerAddress,
            signature: out ? "getAmountsOut(uint,address[])" : "getAmountsIn(uint,address[])",
            args: [amount],
            gasLimit: 5_000_000,
            value: UInt(0),
            dryCall: true
        )
        if callRes == nil || callRes!.status != EVM.Status.successful {
            return nil
        }
        let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: callRes!.data) // can revert if the type cannot be decoded
        let uintAmounts: [UInt256] = decoded.length > 0 ? decoded[0] as! [UInt256] : []
        if uintAmounts.length == 0 {
            return nil
        } else if out {
            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmounts[uintAmounts.length - 1], erc20Address: path[path.length - 1])
        } else {
            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmounts[0], erc20Address: path[0])
        }
    }
    /// Deposits any remainder in the provided Vault or burns if it it's empty
    access(self) fun handleRemainingFeeVault(_ vault: @FlowToken.Vault) {
        if vault.balance > 0.0 {
            self.borrowCOA()!.deposit(from: <-vault)
        } else {
            Burner.burn(<-vault)
        }
    }
    /// Returns a reference to the Swapper's COA or `nil` if the contained Capability is invalid
    access(self) view fun borrowCOA(): auth(EVM.Owner) &EVM.CadenceOwnedAccount? {
        return self.coaCapability.borrow()
    }
    /// Makes a call to the Swapper's routerEVMAddress via the contained COA Capability with the provided signature,
    /// args, and value. If flagged as dryCall, the more efficient and non-mutating COA.dryCall is used. A result is
    /// returned as long as the COA Capability is valid, otherwise `nil` is returned.
    access(self) fun call(
        to: EVM.EVMAddress,
        signature: String,
        args: [AnyStruct],
        gasLimit: UInt64,
        value: UInt,
        dryCall: Bool
    ): EVM.Result? {
        let calldata = EVM.encodeABIWithSignature(signature, args)
        let valueBalance = EVM.Balance(attoflow: value)
        if let coa = self.borrowCOA() {
            let res: EVM.Result = dryCall
                ? coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
                : coa.call(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
            return res
        }
        return nil
    }
}
```
</details>

#### Flash Loan Adapters

Since a flash loan must be executed atomically, protocols often include generic calldata and callback patterns to ensure the loan is repaid in full plus a fee within their contract call scope. The Flasher interface design allows for that callback to be defined in either contract or transaction context. In the example Flasher below, an externally defined function can be passed into the the `flashloan()` method, but other implementations may also decide to pass in contract-defined methods conditionally directing flashloan callbacks to pre-defined contract logic depending on the conditions and optional parameters.

<details>

<summary>IncrementFi Flasher implementation</summary>

```cadence
/// DeFiActions Flasher adapter for use with IncrementFi's flash loan protocol
access(all) resource Flasher : DeFiActions.Flasher, SwapInterfaces.FlashLoanExecutor  {
    access(all) let pairAddress: Address
    access(all) let type: Type

    init(pairAddress: Address, type: Type) {
        let pair = getAccount(pairAddress).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not reference SwapPair public capability at address \(pairAddress)")
        let pairInfo = pair.getPairInfoStruct()
        let pairTokenKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: type.identifier)
        assert(pairInfo.token0Key == pairTokenKey || pairInfo.token1Key == pairTokenKey,
            message: "Provided type \(type.identifier) is not supported by the SwapPair at address \(pairAddress) - "
                .concat("valid types for this SwapPair are \(pairInfo.token0Key).Vault and \(pairInfo.token1Key).Vault"))
        self.pairAddress = pairAddress
        self.type = type
    }

    /* SwapInterfaces.FlashLoanExecutor conformance */
    //
    /// Returns the type this Flasher borrows
    access(all) view fun borrowType(): Type {
        return self.type
    }
    /// Calculates the IncrementFi flashloan fee - see SwapPair for protocol details
    access(all) fun calculateFee(loanAmount: UFix64): UFix64 {
        return UFix64(SwapFactory.getFlashloanRateBps()) * loanAmount / 10000.0
    }
    /// Executes a flashloan using the configured IncrementFi SwapPair's flashloan protocol, passing `callback` via
    /// params to be called within the `executeAndRepay` which is called within SwapPair.flashloan(). The `callback`
    /// implementation should ensure the fee is paid back and execute the logic which leverages the loaned capital.
    access(all) fun flashLoan(
        amount: UFix64,
        data: {String: AnyStruct},
        callback: fun(UFix64, @{FungibleToken.Vault}, {String: AnyStruct}
    ): @{FungibleToken.Vault}) {
        let pair = getAccount(self.pairAddress).capabilities.borrow<&{SwapInterfaces.PairPublic}>(
                SwapConfig.PairPublicPath
            ) ?? panic("Could not reference SwapPair public capability at address \(self.pairAddress)")
        let params: {String: AnyStruct} = {
            "fee": self.calculateFee(loanAmount: amount),
            "callback": callback
        }
        pair.flashloan(
            executor: &self as &{SwapInterfaces.FlashLoanExecutor},
            requestedTokenVaultType: self.type,
            requestedAmount: amount,
            params: params
        )
    }

    /* SwapInterfaces.FlashLoanExecutor conformance */
    //
    /// Called by SwapPair.flashloan, this method pulls the callback method passed in via the `params` value. The
    /// `callback` implementation should ensure the fee is paid back and execute the logic which leverages the loaned
    /// capital.
    access(all)
    fun executeAndRepay(loanedToken: @{FungibleToken.Vault}, params: {String: AnyStruct}): @{FungibleToken.Vault} {
        let fee = params["fee"] as! UFix64
        let executor = params["executor"] as! fun(UFix64, @{FungibleToken.Vault}, {String: AnyStruct}): @{FungibleToken.Vault}
        let data = params["data"] as! {String: AnyStruct}? ?? {}
        let repaidToken <- executor(fee, <-loanedToken, data)
        return <- repaidToken
    }
}
```
</details>

### AutoBalancer Component

The AutoBalancer is a sophisticated component that demonstrates advanced DFA composition, leveraging a PriceOracle and optional rebalance Sink and/or Source. An AutoBalancer's `rebalance()` method is designed for use with Scheduled Callbacks, allowing for automated management of the contained balance.

```cadence
access(all) resource AutoBalancer : Identifiable, FungibleToken.Receiver, FungibleToken.Provider {
    // Rebalancing triggers
    access(self) var _rebalanceRange: [UFix64; 2]  // [lower, upper] thresholds
    
    // Core dependencies  
    access(self) let _oracle: @{PriceOracle}
    access(self) var _vault: @{FungibleToken.Vault}?
    access(self) var _rebalanceSink: @{Sink}?      // Where excess value goes
    access(self) var _rebalanceSource: @{Source}?  // Where deficit value comes from
    
    // Automatic rebalancing based on value thresholds
    access(Auto) fun rebalance(force: Bool) {
        let currentValue = self.currentValue() ?? return
        let valueOfDeposits = self.valueOfDeposits()
        
        // Determine if rebalancing is needed
        let ratio = currentValue / valueOfDeposits
        let needsRebalance = ratio < self._rebalanceRange[0] || ratio > self._rebalanceRange[1]
        
        if needsRebalance || force {
            if ratio > self._rebalanceRange[1] && self._rebalanceSink != nil {
                // Excess value - deposit to sink
                let excessValue = currentValue - valueOfDeposits
                let excessTokens <- self._vault.withdraw(amount: excessValue / currentPrice)
                self._rebalanceSink.depositCapacity(from: &excessTokens)
                // Handle any remainder...
            } else if ratio < self._rebalanceRange[0] && self._rebalanceSource != nil {
                // Deficit value - withdraw from source
                let deficitValue = valueOfDeposits - currentValue
                let deficitTokens <- self._rebalanceSource.withdrawAvailable(maxAmount: deficitValue / currentPrice)
                self._vault.deposit(from: <-deficitTokens)
            }
        }
    }
}
```

### Event System

DFA components emit standardized events for operation tracing:

```cadence
// Core DFA events
access(all) event Deposited(type: String, amount: UFix64, fromUUID: UInt64, uniqueID: UInt64?, sinkType: String, uuid: UInt64)
access(all) event Withdrawn(type: String, amount: UFix64, withdrawnUUID: UInt64, uniqueID: UInt64?, sourceType: String, uuid: UInt64)  
access(all) event Swapped(inVault: String, outVault: String, inAmount: UFix64, outAmount: UFix64, inUUID: UInt64, outUUID: UInt64, uniqueID: UInt64?, swapperType: String, uuid: UInt64)
access(all) event Flashed(requestedAmount: UFix64, borrowType: String, uniqueID: UInt64?, flasherType: String, uuid: UInt64)
access(all) event Rebalanced(amount: UFix64, value: UFix64, unitOfAccount: String, isSurplus: Bool, vaultType: String, vaultUUID: UInt64, balancerUUID: UInt64, address: Address?, uniqueID: UInt64?, uuid: UInt64)
```

Component actions are associated by their `uniqueID` event values.

## Use Cases

### Automated Token Transmission

This strategy can be used to simply move tokens, as in the case of an autopay subscription, dollar-cost average into a token, or auto-claim & restake staking rewards - which one depends on the token DFA connectors configured on initialization.

A VaultSink would simply receive the deposited tokens, transferring from the source to the sink. Configured with a SwapSink, the deposited tokens would be swapped before depositing to an inner SwapSink's inner Sink. Or provided a Source tied to staking rewards and a Sink directing funds to protocol staking, this object could be used to optimize staking rewards by auto-claiming & re-staking.

```cadence
/// Example auto token transmission using DFA connectors for use in DCA strategies, onchain subscriptions, and staking 
/// rewards claim + restake
///
/// Usage of Scheduled Callbacks based on current state of FLIP #331
access(all) contract AutoTokenTransmitter {

    access(all) entitlement Set
    access(all) entitlement Schedule

    /// Moves tokens from a source to a target in conformance with CallbackHandler
    access(all) resource Transmitter : UnsafeCallbackScheduler.CallbackHandler {
        /// Provides tokens to move
        access(self) let tokenSource: @{DeFiActions.Sink, DeFiActions.Source}
        /// Sink to which source tokens are deposited - a SwapSink would swap into a target denomination
        access(self) let tokenSink: @{DeFiActions.Sink}
        /// Provides FLOW to pay for scheduled callbacks
        access(self) let callbackFeeSource: @{DeFiActions.Source}
        /// The amount of tokens to withdraw from tokenSource when executed. If `nil`, transmission amount is whatever
        /// the tokenSource reports as available
        access(self) let maxAmount: UFix64?
        /// When the strategy was last executed
        access(self) let lastExecuted: UFix64
        /// The amount of time to elapse before auto-executing
        access(self) var interval: UFix64
        /// An authorized Capability enabling scheduled callbacks
        access(self) let selfCapability: Capability<auth(UnsafeCallbackScheduler.mayExecuteCallback) &DCAHandler>
        /// Callbacks that have been scheduled
        access(self) let scheduledCallbacks: {UInt64: UnsafeCallbackScheduler.ScheduledCallback}

        // init( ... ) { ... }

        /// Calculates the timestamp of when the next execution should be scheduled
        access(all) view fun getNextTransmissionTime(): UFix64 {
            let now = getCurrentBlock().timestamp
            let slated = self.lastExecuted + self.interval
            return slated <= now ? now : slated
        }
        /// Sets the Capability of the Strategy on itself so it can be self-managed via Scheduled Callbacks
        access(Set)
        fun setSelfCapability(_ cap: Capability<auth(UnsafeCallbackScheduler.mayExecuteCallback) &DCAHandler>) {
            // pre { ... }
            self.selfCapability = cap
        }
        /// CallbackHandler conformance - enables execution of Scheduled Callbacks
        access(UnsafeCallbackScheduler.mayExecuteCallback) fun executeCallback(data: AnyStruct?) {
            let now = getCurrentBlock().timestamp
            if now < self.lastExecuted + self.interval {
                return self.scheduleNextTransmission()
            }
            self.lastExecuted = now

            // withdraw tokens from source
            let sourceVault <- self.tokenSource.withdrawAvailable(maxAmount: self._getTransmissionAmount())
            if sourceVault.balance == 0.0 {
                return self.scheduleNextTransmission()
            }
            
            // deposit to inner sink
            let sourceVaultRef = &sourceVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
            self.tokenSink.depositCapacity(from: sourceVaultRef)
            self._handleRemainingVault(<-sourceVault)
            
            // schedule next transmission before closing
            self.scheduleNextTransmission()
        }
        /// Schedules the next scheduled callback
        access(Schedule) fun scheduleNextTransmission() {
            let prio = UnsafeCallbackScheduler.Priority.Low
            let effort = 2000 // could be configured - varies based on complexity of source & sink
            let timestamp = self.getNextExecutionTime()
            let estimate = UnsafeCallbackScheduler.estimate(
                    data: nil,
                    timestamp: timestamp,
                    priority: prio,
                    executionEffort: effort,
                )!
            let fees <- self.callbackFeeSource.withdrawAvailable(maxAmount: estimate.flowFee)
            let scheduledCallback = UnsafeCallbackScheduler.schedule(
                callback: self.selfCapability,
                data: nil,
                timestamp: timestamp,
                priority: prio,
                executionEffort: effort,
                fees: <-feesVault
            )
            self.scheduledCallbacks[scheduledCallback.ID] = scheduledCallback
        }
        /// Calculates the amount to transmit on execution based on the 
        access(self) view fun _getTransmissionAmount(): UFix64 {
            let capacity = self.tokenSink.minimumCapacity()
            var amount = self.tokenSource.minimumAvailable()
            if self.maxAmount != nil {
                amount = amount <= self.maxAmount! ? amount : self.maxAmount! 
            }
            amount = amount <= capacity ? amount : capacity
            return amount
        }
        /// Handles any remaining vault that was withdrawn in excess of what could be handled by the Sink
        access(self) fun _handleRemainingVault(_ remainder: @{FungibleToken.Vault}) {
            if sourceVault.balance > 0.0 {
                self.tokenSource.depositCapacity(from: sourceVaultRef)
            }
            assert(sourceVault.balance == 0.0, message: "Could not handle remaining withdrawal amount \(sourceVault.balance)")
            Burner.burn(<-sourceVault)
        }
    }
}
```

## Considerations

### Security Model

DFA's design philosophy prioritizes graceful failure over strict guarantees, which creates both benefits and security considerations:

**Weak Behavioral Guarantees:**
- Sources may return less than requested without reverting
- Sinks may accept less than provided without warning
- No guarantee on exact Vault types returned by components

**Security Implications:**
- **Consumer Responsibility**: Applications must validate component outputs rather than assuming behavior
- **Type Safety**: Multiple connectors can make type tracking complex; developers should implement explicit type checks
- **Reentrancy Risk**: Open component definitions and weak guarantees may increase reentrancy attack surface
- **Flash Loan Risks**: Flasher implementations must validate full repayment (loan + fee) to prevent exploitation; consumer logic must execute entirely within the callback function scope

**Recommended Practices:**
- Always validate returned Vault types and amounts
- Implement slippage protection for Swapper operations
- Use UniqueIdentifier for comprehensive operation tracing
- Consider implementing circuit breakers for automated strategies
- For Flasher implementations: validate exact repayment amounts before transaction completion
- For flash loan consumers: ensure all loan-related logic executes within the callback function

### Performance Implications

**Computational Complexity:**
- **Aggregation Overhead**: MultiSwapper components querying many protocols can be expensive
- **Deep Call Stacks**: Complex compositions may hit computation limits
- **Event Volume**: DFA stacks emit extensive events, increasing transaction costs
- **Cross-Runtime Operations**: Future EVM bridge connectors will add significant computational overhead

**Optimization Strategies:**
- Limit aggregation scope for performance-critical applications
- Cache price quotes when possible to reduce oracle calls
- Monitor stack depth in complex compositions
- Consider gas costs when designing autonomous strategies

### Testing Challenges

**Environment Complexity:**
- Multi-protocol dependencies require complex test setups
- Protocol state dependencies make unit testing difficult
- Limited testnet protocol maintenance affects testing reliability

**Recommendations:**
- Develop protocol-specific testing frameworks and starter repositories
- Partner with major protocols to improve testnet infrastructure
- Consider mainnet forking for realistic integration testing
- Implement comprehensive component validation in CI/CD pipelines

### Drawbacks

**Learning Curve:**
- Component composition patterns require new mental models
- Debugging complex stacks can be challenging
- Performance characteristics are not yet well-understood

**Protocol Maturity:**
- Standards are new and may evolve based on developer feedback
- Limited ecosystem tooling and documentation
- No backwards compatibility guarantees during beta period

**Complexity Trade-offs:**
- May be overkill for simple single-protocol integrations
- Abstraction overhead for performance-critical applications
- Additional event costs for operation tracing

## Compatibility

DeFiActions is a completely new standard that maintains full compatibility with existing Flow infrastructure:

**No Migration Required:**
- Existing DeFi protocols continue operating unchanged
- Current applications can gradually adopt DFA components
- No modifications needed to deployed contracts

**Integration Approach:**  
- Protocols can add DFA support via adapter contracts
- Applications can mix DFA components with direct protocol calls
- Developers can choose adoption level based on use case complexity

**Forward Compatibility:**
- Interface evolution will be managed through versioning
- Breaking changes will be announced well in advance during beta period
- Production release will commit to backwards compatibility standards

## Future Extensions

**Planned Enhancements:**
- **EVM Bridge Connectors**: Native support for Flow EVM DeFi protocols
- **Cross-Chain Components**: Standardized interfaces for multi-chain operations  
- **Advanced Analytics**: Enhanced component performance tracking and optimization
- **Visual Composition Tools**: GUI-based component composition for non-technical users
- **Formal Verification**: Mathematical proofs for component behavior guarantees

**Ecosystem Development:**
- **Protocol Partner Program**: Collaboration framework for adapter development
- **Developer Tooling**: IDE plugins, testing frameworks, and debugging tools
- **Educational Resources**: Comprehensive guides, tutorials, and best practices
- **Community Components**: Registry of community-developed connectors and patterns

**Research Areas:**
- **MEV Protection**: Standards for protecting composed operations from MEV
- **Privacy Components**: Private computation integration for sensitive operations
- **Governance Integration**: DAO-controlled parameter management for automated strategies
- **Machine Learning**: AI-driven component optimization and strategy generation

---

DeFiActions represents a foundational shift toward truly composable DeFi on Flow, enabling developers to build sophisticated financial applications through simple, reusable components. By standardizing the interfaces between DeFi operations, DFA creates a platform for innovation that can grow with the ecosystem while maintaining the security and performance characteristics developers expect. 