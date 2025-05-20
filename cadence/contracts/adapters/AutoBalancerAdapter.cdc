import "Burner"
import "ViewResolver"
import "FungibleToken"

import "DFB"

access(all) contract AutoBalancerAdapter {

    access(all) event Created(uuid: UInt64, vaultType: String, uniqueID: UInt64?, uniqueIDType: String?)

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
        uniqueID: {DFB.UniqueIdentifier}?
    ): @AutoBalancer {
        let ab <- create AutoBalancer(
            rebalanceRange: rebalanceRange,
            oracle: oracle,
            vault: <-vault,
            outSink: outSink,
            inSource: inSource,
            uniqueID: uniqueID
        )
        emit Created(uuid: ab.uuid, vaultType: ab.vaultType().identifier, uniqueID: ab.id(), uniqueIDType: ab.idType()?.identifier)
        return <- ab
    }

    /// AutoBalancer
    ///
    /// A resource designed to enable permissionless rebalancing of value around a wrapped Vault. An AutoBalancer can
    /// be a critical component of DeFiBlocks stacks by allowing for strategies to compound, repay loans or direct
    /// accumulated value to other sub-systems and/or user Vaults.
    ///
    access(all) resource AutoBalancer : DFB.AutoBalancer {
        /// The value in deposits & withdrawals over time denominated in oracle.unitOfAccount()
        access(self) var _baseValue: UFix64
        /// The percentage range up or down from the base value at which the AutoBalancer will rebalance using the
        /// inner Source and/or Sink. Values between 0.01 and 0.1 are recommended
        access(self) let _rebalanceRange: UFix64
        /// Oracle used to track the baseValue for deposits & withdrawals over time
        access(self) let _oracle: {DFB.PriceOracle}
        /// The inner Vault's Type captured for the ResourceDestroyed event
        access(self) let _vaultType: Type
        /// Vault used to deposit & withdraw from made optional only so the Vault can be burned via Burner.burn() if the
        /// AutoBalancer is burned and the Vault's burnCallback() can be called in the process
        access(self) var _vault: @{FungibleToken.Vault}?
        /// An optional Sink used to deposit excess funds from the inner Vault once the converted value exceeds the
        /// rebalance range. This Sink may be used to compound yield into a position or direct excess value to an
        /// external Vault
        access(self) var _outSink: {DFB.Sink}?
        /// An optional Source used to deposit excess funds to the inner Vault once the converted value is below the
        /// rebalance range
        access(self) var _inSource: {DFB.Source}?
        /// An optional UniqueIdentifier tying this AutoBalancer to a given stack
        access(contract) let uniqueID: {DFB.UniqueIdentifier}?
        /// The type of a uniqueID (if one is provided on init) captured for the ResourceDestroyed event
        access(self) let uniqueIDType: Type?

        /// Emitted when the AutoBalancer is destroyed
        access(all) event ResourceDestroyed(
            uuid: UInt64 = self.uuid,
            vaultType: String = self._vaultType.identifier,
            balance: UFix64? = self._vault?.balance,
            uniqueIDType: String? = self.uniqueIDType?.identifier,
            uniqueID: UInt64? = self.uniqueID?.id
        )

        init(
            rebalanceRange: UFix64,
            oracle: {DFB.PriceOracle},
            vault: @{FungibleToken.Vault},
            outSink: {DFB.Sink}?,
            inSource: {DFB.Source}?,
            uniqueID: {DFB.UniqueIdentifier}?
        ) {
            pre {
                0.01 <= rebalanceRange && rebalanceRange <= 1.0:
                "Invalid rebalanceRange \(rebalanceRange) - relative range over baseValue must be between 0.01 and 1.0"
                vault.balance == 0.0:
                "Vault \(vault.getType().identifier) has a non-zero balance - AutoBalancer must be initialized with an empty Vault"
            }
            self._baseValue = 0.0
            self._rebalanceRange = rebalanceRange
            self._oracle = oracle
            self._vault <- vault
            self._vaultType = self._vault.getType()
            self._outSink = outSink
            self._inSource = inSource
            self.uniqueID = uniqueID
            self.uniqueIDType = self.uniqueID?.getType()
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
        access(all) fun currentValue(): UFix64 {
            return self._oracle.price(ofToken: self.vaultType()) * self._borrowVault().balance
        }

        /// Allows for external parties to call on the AutoBalancer and execute a rebalance according to it's rebalance
        /// parameters. This method must be called by external party regularly in order for rebalancing to occur, hence
        /// the `access(all)` distinction.
        access(all) fun rebalance() {
            let currentPrice = self._oracle.price(ofToken: self._vaultType)
            let currentValue = self.currentValue()
            let diff = currentValue < self._baseValue ? self._baseValue - currentValue : currentValue - self._baseValue
            if (diff / self._baseValue) < self._rebalanceRange || currentPrice == 0.0 {
                return // does not exceed rebalance percentage or price is below UFix precision - do nothing
            }

            let vault = self._borrowVault()
            var amount = diff / currentPrice
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
                    Burner.burn(<-excess)
                } else {
                    vault.deposit(from: <-excess) // deposit any excess not taken by the Sink
                }
            }
        }

        /// A setter enabling an AutoBalancer to set a Sink to which overflow value should be deposited. Implementations
        /// may wish to revert on call if a Sink is set on `init`
        access(DFB.Set) fun setSink(_ sink: {DFB.Sink}) {
            pre {
                self._outSink == nil: "AutoBalancer.outSink has already been set - cannot set again"
            }
            self._outSink = sink
        }

        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn. Implementations
        /// may wish to revert on call if a Source is set on `init`
        access(DFB.Set) fun setSource(_ source: {DFB.Source}) {
            pre {
                self._inSource == nil: "AutoBalancer.inSource has already been set - cannot set again"
            }
            self._inSource = source
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
        /// AutoBalancer's baseValue
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            pre {
                from.getType() == self.vaultType():
                "Invalid Vault type \(from.getType().identifier) deposited - this AutoBalancer only accepts \(self.vaultType().identifier)"
            }
            self._baseValue = self._baseValue + self._oracle.price(ofToken: from.getType())
            self._borrowVault().deposit(from: <-from)
        }

        /// Returns the requested amount of the nested Vault type, reducing the baseValue by the current value
        /// (denominated in unitOfAccount) of the token amount.
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            let baseAmount = self._oracle.price(ofToken: self._vaultType)
            let withdrawn <- self._borrowVault().withdraw(amount: amount)
            // protect underflow by reassigning _baseValue to the current value post-withdrawal - only encountered if
            // price has increased rapicdly and rebalance hasn't executed in a while
            self._baseValue = baseAmount <= self._baseValue ? self._baseValue - baseAmount : self.currentValue()
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
