import "Burner"
import "ViewResolver"
import "FungibleToken"

import "DFB"
import "DFBUtils"

/// AutoBalancerAdapter
///
/// This contract defines an AutoBalancerAdapter
///
access(all) contract AutoBalancerAdapter {

    /// Emitted when an AutoBalancer is created
    access(all) event Created(uuid: UInt64, vaultType: String, uniqueID: UInt64?)

    /// Returns an AutoBalancer wrapping the provided Vault.
    ///
    /// @param oracle: The oracle used to query deposited & withdrawn value and to determine if a rebalance should execute
    /// @param vault: The Vault wrapped by the AutoBalancer
    /// @param rebalanceRange: The percentage range from the AutoBalancer's base value at which a rebalance is executed
    /// @param outSink: An optional DeFiBlocks Sink to which excess value is directed when rebalancing
    /// @param inSource: An optional DeFiBlocks Source from which value is withdrawn to the inner vault when rebalancing
    /// @param uniqueID: An optional DeFiBlocks UniqueIdentifier used for identifying rebalance events
    ///
    access(all) fun createAutoBalancer(
        oracle: {DFB.PriceOracle},
        vault: @{FungibleToken.Vault},
        rebalanceRange: UFix64,
        outSink: {DFB.Sink}?,
        inSource: {DFB.Source}?,
        uniqueID: DFB.UniqueIdentifier?
    ): @AutoBalancer {
        let ab <- create AutoBalancer(
            rebalanceRange: rebalanceRange,
            oracle: oracle,
            vault: <-vault,
            outSink: outSink,
            inSource: inSource,
            uniqueID: uniqueID
        )
        emit Created(uuid: ab.uuid, vaultType: ab.vaultType().identifier, uniqueID: ab.id())
        return <- ab
    }

    /// Sink
    ///
    /// A DeFiBlocks Sink enabling the deposit of funds to an underlying AutoBalancer resource. As written, this Source
    /// may be used with externally defined AutoBalancer implementations
    ///
    access(all) struct Sink : DFB.Sink {
        /// The Type this Sink accepts
        access(self) let type: Type
        /// An authorized Capability on the underlying AutoBalancer where funds are deposited
        access(self) let autoBalancer: Capability<&{DFB.AutoBalancer}>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: DFB.UniqueIdentifier?

        init(autoBalancer: Capability<&{DFB.AutoBalancer}>, uniqueID: DFB.UniqueIdentifier?) {
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
        access(all) fun minimumCapacity(): UFix64 {
            if let ab = self.autoBalancer.borrow() {
                return UFix64.max - ab.vaultBalance()
            }
            return 0.0
        }
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if let ab = self.autoBalancer.borrow() {
                ab.deposit(from: <- from.withdraw(amount: from.balance))
            }
            return
        }
    }

    /// Source
    ///
    /// A DeFiBlocks Source targeting an underlying AutoBalancer resource. As written, this Source may be used with
    /// externally defined AutoBalancer implementations
    ///
    access(all) struct Source : DFB.Source {
        /// The Type this Source provides
        access(self) let type: Type
        /// An authorized Capability on the underlying AutoBalancer where funds are sourced
        access(self) let autoBalancer: Capability<auth(FungibleToken.Withdraw) &{DFB.AutoBalancer}>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: DFB.UniqueIdentifier?

        init(autoBalancer: Capability<auth(FungibleToken.Withdraw) &{DFB.AutoBalancer}>, uniqueID: DFB.UniqueIdentifier?) {
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
            return <- DFBUtils.getEmptyVault(self.type)
        }
    }

    /// AutoBalancer
    ///
    /// A resource designed to enable permissionless rebalancing of value around a wrapped Vault. An AutoBalancer can
    /// be a critical component of DeFiBlocks stacks by allowing for strategies to compound, repay loans or direct
    /// accumulated value to other sub-systems and/or user Vaults.
    ///
    access(all) resource AutoBalancer : DFB.AutoBalancer {
        /// The value in deposits & withdrawals over time denominated in oracle.unitOfAccount()
        access(self) var _baseValue: UFix64 // var _valueOfDeposits
        /// The percentage range up or down from the base value at which the AutoBalancer will rebalance using the
        /// inner Source and/or Sink. Values between 0.01 and 0.1 are recommended
        access(self) let _rebalanceRange: UFix64 // -> change to high/low fields
        /// Oracle used to track the baseValue for deposits & withdrawals over time
        access(self) let _oracle: {DFB.PriceOracle} //
        /// The inner Vault's Type captured for the ResourceDestroyed event
        access(self) let _vaultType: Type
        /// Vault used to deposit & withdraw from made optional only so the Vault can be burned via Burner.burn() if the
        /// AutoBalancer is burned and the Vault's burnCallback() can be called in the process
        access(self) var _vault: @{FungibleToken.Vault}?
        /// An optional Sink used to deposit excess funds from the inner Vault once the converted value exceeds the
        /// rebalance range. This Sink may be used to compound yield into a position or direct excess value to an
        /// external Vault
        access(self) var _outSink: {DFB.Sink}? // var _rebalanceSink
        /// An optional Source used to deposit excess funds to the inner Vault once the converted value is below the
        /// rebalance range
        access(self) var _inSource: {DFB.Source}? // var _rebalanceSource
        /// Capability on this AutoBalancer instance
        access(self) var _selfCap: Capability<auth(FungibleToken.Withdraw) &{DFB.AutoBalancer}>?
        /// An optional UniqueIdentifier tying this AutoBalancer to a given stack
        access(contract) let uniqueID: DFB.UniqueIdentifier?

        /// Emitted when the AutoBalancer is destroyed
        access(all) event ResourceDestroyed(
            uuid: UInt64 = self.uuid,
            vaultType: String = self._vaultType.identifier,
            balance: UFix64? = self._vault?.balance,
            uniqueID: UInt64? = self.uniqueID?.id
        )

        init(
            rebalanceRange: UFix64,
            oracle: {DFB.PriceOracle},
            vault: @{FungibleToken.Vault},
            outSink: {DFB.Sink}?,
            inSource: {DFB.Source}?,
            uniqueID: DFB.UniqueIdentifier?
        ) {
            pre {
                0.01 <= rebalanceRange && rebalanceRange <= 1.0:
                "Invalid rebalanceRange \(rebalanceRange) - relative range over baseValue must be between 0.01 and 1.0"
                vault.balance == 0.0:
                "Vault \(vault.getType().identifier) has a non-zero balance - AutoBalancer must be initialized with an empty Vault"
                DFBUtils.definingContractIsFungibleToken(vault.getType()):
                "The contract defining Vault \(vault.getType().identifier) does not conform to FungibleToken contract interface"
            }
            assert(oracle.price(ofToken: vault.getType()) != nil,
                message: "Provided Oracle \(oracle.getType().identifier) could not provide a price for vault \(vault.getType().identifier)")
            self._baseValue = 0.0
            self._rebalanceRange = rebalanceRange
            self._oracle = oracle
            self._vault <- vault
            self._vaultType = self._vault.getType()
            self._outSink = outSink
            self._inSource = inSource
            self._selfCap = nil
            self.uniqueID = uniqueID
        }

        /* DFB.AutoBalancer conformance */

        /// Returns the balance of the inner Vault
        access(all) view fun vaultBalance(): UFix64 {
            return self._borrowVault().balance
        }

        /// Returns the Type of the inner Vault
        access(all) view fun vaultType(): Type {
            return self._borrowVault().getType()
        }

        /// Returns the percentage difference from baseValue at which the AutoBalancer executes a rebalance
        access(all) view fun rebalanceThreshold(): UFix64 {
            return self._rebalanceRange
        }

        /// Returns the value of all accounted deposits/withdraws as they have occurred denominated in unitOfAccount
        access(all) view fun baseValue(): UFix64 {
            return self._baseValue
        }

        /// Returns the token Type serving as the price basis of this AutoBalancer
        access(all) view fun unitOfAccount(): Type {
            return self._oracle.unitOfAccount()
        }

        /// Returns the current value of the inner Vault's balance
        access(all) fun currentValue(): UFix64? {
            if let price = self._oracle.price(ofToken: self.vaultType()) {
                return price * self._borrowVault().balance
            }
            return nil
        }

        /// Convenience method issuing a Sink allowing for deposits to this AutoBalancer
        access(all) fun createBalancerSink(): {DFB.Sink}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return Sink(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }

        /// Convenience method issuing a Source enabling withdrawals from this AutoBalancer
        access(DFB.Get) fun createBalancerSource(): {DFB.Source}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return Source(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }

        /// A setter enabling an AutoBalancer to set a Sink to which overflow value should be deposited. Implementations
        /// may wish to revert on call if a Sink is set on `init`
        access(DFB.Set) fun setSink(_ sink: {DFB.Sink}?) {
            self._outSink = sink
        }

        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn. Implementations
        /// may wish to revert on call if a Source is set on `init`
        access(DFB.Set) fun setSource(_ source: {DFB.Source}?) {
            self._inSource = source
        }

        /// Enables the setting of a Capability on the AutoBalancer for the distribution of Sinks & Sources targeting
        /// the AutoBalancer instance. Due to the mechanisms of Capabilities, this must be done after the AutoBalancer
        /// has been saved to account storage and an authorized Capability has been issued.
        access(DFB.Set) fun setSelfCapability(_ cap: Capability<auth(FungibleToken.Withdraw) &{DFB.AutoBalancer}>) {
            pre {
                self._selfCap == nil || self._selfCap!.check() != true:
                "Internal AutoBalancer Capability has been set and is still valid - cannot be re-assigned"
            }
            self._selfCap = cap
        }

        /// Allows for external parties to call on the AutoBalancer and execute a rebalance according to it's rebalance
        /// parameters. This method must be called by external party regularly in order for rebalancing to occur, hence
        /// the `access(all)` distinction.
        access(DFB.Auto) fun rebalance(force: Bool) { // TODO: implement force param
            let currentPrice = self._oracle.price(ofToken: self._vaultType)
            if currentPrice == nil {
                return
            }
            let currentValue = self.currentValue()!
            let diff = currentValue < self._baseValue ? self._baseValue - currentValue : currentValue - self._baseValue
            if (diff / self._baseValue) < self._rebalanceRange || currentPrice == 0.0 {
                return // does not exceed rebalance percentage or price is below UFix precision - do nothing
            }

            let vault = self._borrowVault()
            var amount = diff / currentPrice!
            if currentValue < self._baseValue && self._inSource != nil {
                // rebalance back up to baseline sourcing funds from _inSource
                vault.deposit(from:  <- self._inSource!.withdrawAvailable(maxAmount: amount))
            } else if currentValue > self._baseValue && self._outSink != nil {
                // rebalance back down to baseline deposting excess to _outSink
                if amount > vault.balance {
                    amount = vault.balance // protect underflow
                }
                let excess <- vault.withdraw(amount: amount)
                self._outSink!.depositCapacity(from: &excess as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                if excess.balance == 0.0 {
                    Burner.burn(<-excess) // could destroy
                } else {
                    vault.deposit(from: <-excess) // deposit any excess not taken by the Sink
                }
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
        /// AutoBalancer's baseValue. If a price is not available via the internal PriceOracle, base value updates are
        /// bypassed to prevent reversion
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            pre {
                from.getType() == self.vaultType():
                "Invalid Vault type \(from.getType().identifier) deposited - this AutoBalancer only accepts \(self.vaultType().identifier)"
            }
            if let price = self._oracle.price(ofToken: from.getType()) {
                self._baseValue = self._baseValue + price * from.balance
            }
            // TODO: revert without price; (use weighted adjusted cost basis)!; set baseValue to sentinel & recompute next deposit
            self._borrowVault().deposit(from: <-from)
        }

        /// Returns the requested amount of the nested Vault type, reducing the baseValue by the current value
        /// (denominated in unitOfAccount) of the token amount. If a price is not available via the internal
        /// PriceOracle, base value updates are bypassed to prevent reversion
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            // NOTES: won't look at oracle - adjust valueOfDeposits proportionate to balance withdrawn
            if let price = self._oracle.price(ofToken: self._vaultType) {
                let baseAmount = price * amount
                // protect underflow by reassigning _baseValue to the current value post-withdrawal - only encountered if
                // price has increased rapidly and rebalance hasn't executed in a while
                self._baseValue = baseAmount <= self._baseValue ? self._baseValue - baseAmount : self.currentValue()!
            }
            let withdrawn <- self._borrowVault().withdraw(amount: amount)
            return <- withdrawn
        }

        /* Burnable.Burner conformance */

        /// Executed in Burner.burn(). Passes along the inner vault to be burned, executing the inner Vault's
        /// burnCallback() logic
        access(contract) fun burnCallback() {
            let vault <- self._vault <- nil
            Burner.burn(<-vault) // executes the inner Vault's burnCallback()
        }

        /* Internal */

        access(self) view fun _borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault} {
            return (&self._vault)!
        }
    }
}
