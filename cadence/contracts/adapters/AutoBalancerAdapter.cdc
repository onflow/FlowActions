import "Burner"
import "ViewResolver"
import "FungibleToken"

import "DFB"

access(all) contract AutoBalancerAdapter {

    /// AutoBalancer
    ///
    access(all) resource AutoBalancer : DFB.AutoBalancer {
        /// The value in deposits & withdrawals over time denominated in oracle.unitOfAccount()
        access(self) var _baseValue: UFix64
        /// The percentage range up or down from the base value at which the AutoBalancer will rebalance using the
        /// inner Source and/or Sink
        access(self) let _rebalanceRange: UFix64
        /// Oracle used to track the baseValue for deposits & withdrawals over time
        access(self) let _oracle: {DFB.PriceOracle}
        /// The inner Vault's Type captured for the ResourceDestroyed event
        access(self) let _vaultType: Type
        /// Vault used to deposit & withdraw from made optional only so the Vault can be burned via Burner.burn() if the
        /// AutoBalancer is burned and the Vault's burnCallback() can be called in the process
        access(self) var _vault: @{FungibleToken.Vault}?
        /// An optional Sink used to deposit excess funds from the inner Vault once the converted value exceeds the
        /// rebalance range
        access(self) var _rebalanceSink: {DFB.Sink}?
        /// An optional Source used to deposit excess funds to the inner Vault once the converted value is below the
        /// rebalance range
        access(self) var _rebalanceSource: {DFB.Source}?
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
            baseValue: UFix64,
            rebalanceRange: UFix64,
            oracle: {DFB.PriceOracle},
            vault: @{FungibleToken.Vault},
            rebalanceSink: {DFB.Sink}?,
            rebalanceSource: {DFB.Source}?,
            uniqueID: {DFB.UniqueIdentifier}?
        ) {
            self._baseValue = baseValue
            self._rebalanceRange = rebalanceRange
            self._oracle = oracle
            self._vault <- vault
            self._vaultType = self._vault.getType()
            self._rebalanceSink = rebalanceSink
            self._rebalanceSource = rebalanceSource
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

        /// Returns the percentage range from baseValue at which the AutoBalancer executes a rebalance
        access(all) view fun rebalanceRange(): UFix64 {
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
        /// parameters. Implementations should no-op if a rebalance threshold has not been met
        access(all) fun rebalance() {
            let currentPrice = self._oracle.price(ofToken: self._vaultType)
            let currentValue = self.currentValue()
            let diff = currentValue < self._baseValue ? self._baseValue - currentValue : currentValue - self._baseValue
            if (diff / self._baseValue) < self._rebalanceRange || currentPrice == 0.0 {
                return // does not exceed rebalance percentage or price is below UFix precision - do nothing
            }

            let vault = self._borrowVault()
            var amount = diff / currentPrice
            if currentValue < self._baseValue && self._rebalanceSource != nil {
                // rebalance back up to baseline
                vault.deposit(from:  <- self._rebalanceSource!.withdrawAvailable(maxAmount: amount))
            } else if currentValue > self._baseValue && self._rebalanceSink != nil {
                // rebalance back down to baseline
                if amount > vault.balance {
                    amount = vault.balance // protect underflow
                }
                let excess <- vault.withdraw(amount: amount)
                self._rebalanceSink!.depositCapacity(from: &excess as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
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
                self._rebalanceSink == nil: "AutoBalancer.rebalanceSink has already been set - cannot set again"
            }
            self._rebalanceSink = sink
        }

        /// A setter enabling an AutoBalancer to set a Source from which underflow value should be withdrawn. Implementations
        /// may wish to revert on call if a Source is set on `init`
        access(DFB.Set) fun setSource(_ source: {DFB.Source}) {
            pre {
                self._rebalanceSource == nil: "AutoBalancer.rebalanceSource has already been set - cannot set again"
            }
            self._rebalanceSource = source
        }

        /* ViewResolver.Resolver conformance */

        access(all) view fun getViews(): [Type] {
            return self._borrowVault().getViews()
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            return self._borrowVault().resolveView(view)
        }

        /* FungibleToken.Receiver & .Provider conformance */

        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            return self._borrowVault().getSupportedVaultTypes()
        }

        access(all) view fun isSupportedVaultType(type: Type): Bool {
            return self._borrowVault().isSupportedVaultType(type: type)
        }

        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
            return self._borrowVault().isAvailableToWithdraw(amount: amount)
        }

        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            self._baseValue = self._baseValue + self._oracle.price(ofToken: from.getType())
            self._borrowVault().deposit(from: <-from)
        }

        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            let baseAmount = self._oracle.price(ofToken: self._vaultType)
            self._baseValue = baseAmount <= self._baseValue ? self._baseValue - baseAmount : 0.0 // protect underflow
            return <- self._borrowVault().withdraw(amount: amount)
        }

        /* Burnable.Burner conformance */

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