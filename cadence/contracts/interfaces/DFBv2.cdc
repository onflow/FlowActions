import "Burner"
import "ViewResolver"
import "FungibleToken"

import "DFBUtils"
import "DFBMathUtils"
import "DFB"

/// DeFiBlocks V2 Interfaces
///
/// This contract extends DeFiBlocks with high-precision UInt256-based calculations
/// for improved accuracy in DeFi operations.
///
access(all) contract DFBv2 {

    /// Events
    access(all) event CreatedAutoBalancerV2(
        lowerThreshold: UFix64,
        upperThreshold: UFix64,
        balancerUUID: UInt64,
        vaultType: String,
        vaultUUID: UInt64,
        uniqueID: UInt64?
    )

    access(all) event RebalancedV2(
        amount: UFix64,
        value: UFix64,
        unitOfAccount: String,
        isSurplus: Bool,
        vaultType: String,
        vaultUUID: UInt64,
        balancerUUID: UInt64,
        address: Address?,
        uniqueID: UInt64?
    )

    /// AutoBalancerV2 - High-precision version using UInt256 calculations
    ///
    /// This resource maintains the same interface as the original AutoBalancer
    /// but uses UInt256 internally for all calculations to improve precision.
    ///
    access(all) resource AutoBalancerV2 : 
        DFB.IdentifiableResource,
        FungibleToken.Receiver,
        FungibleToken.Provider,
        ViewResolver.Resolver,
        Burner.Burnable
    {
        /// UniqueIdentifier allowing identification of stacked connectors
        access(contract) let uniqueID: DFB.UniqueIdentifier?
        
        /// Internal state - now using UInt256 for precision
        access(self) var _valueOfDeposits: UInt256  // 18 decimal precision
        access(self) let _rebalanceRange: [UFix64; 2]
        access(self) let _oracle: {DFB.PriceOracle}
        access(self) var _vault: @{FungibleToken.Vault}
        access(self) let _vaultType: Type
        access(self) var _rebalanceSink: {DFB.Sink}?
        access(self) var _rebalanceSource: {DFB.Source}?
        access(self) var _selfCap: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>?

        init(
            oracle: {DFB.PriceOracle},
            vaultType: Type,
            lowerThreshold lower: UFix64,
            upperThreshold upper: UFix64,
            rebalanceSink outSink: {DFB.Sink}?,
            rebalanceSource inSource: {DFB.Source}?,
            uniqueID: DFB.UniqueIdentifier?
        ) {
            pre {
                lower < upper && 0.01 <= lower && lower < 1.0 && 1.0 < upper && upper < 2.0:
                "Invalid rebalanceRange [lower, upper]: [\(lower), \(upper)] - thresholds must be set such that 0.01 <= lower < 1.0 and 1.0 < upper < 2.0 relative to value of deposits"
                DFBUtils.definingContractIsFungibleToken(vaultType):
                "The contract defining Vault \(vaultType.identifier) does not conform to FungibleToken contract interface"
            }
            assert(oracle.price(ofToken: vaultType) != nil,
                message: "Provided Oracle \(oracle.getType().identifier) could not provide a price for vault \(vaultType.identifier)")
            
            self._valueOfDeposits = 0
            self._rebalanceRange = [lower, upper]
            self._oracle = oracle
            self._vault <- DFBUtils.getEmptyVault(vaultType)
            self._vaultType = vaultType
            self._rebalanceSink = outSink
            self._rebalanceSource = inSource
            self._selfCap = nil
            self.uniqueID = uniqueID

            emit CreatedAutoBalancerV2(
                lowerThreshold: lower,
                upperThreshold: upper,
                balancerUUID: self.uuid,
                vaultType: vaultType.identifier,
                vaultUUID: self._borrowVault().uuid,
                uniqueID: self.id()
            )
        }

        /* Core AutoBalancer Functionality */

        /// Returns the balance of the inner Vault
        access(all) view fun vaultBalance(): UFix64 {
            return self._borrowVault().balance
        }

        /// Returns the Type of the inner Vault
        access(all) view fun vaultType(): Type {
            return self._borrowVault().getType()
        }

        /// Returns the rebalance thresholds
        access(all) view fun rebalanceThresholds(): [UFix64; 2] {
            return self._rebalanceRange
        }

        /// Returns the value of deposits as UFix64 (converted from internal UInt256)
        access(all) view fun valueOfDeposits(): UFix64 {
            return DFBMathUtils.toUFix64(self._valueOfDeposits)
        }

        /// Returns the unit of account
        access(all) view fun unitOfAccount(): Type {
            return self._oracle.unitOfAccount()
        }

        /// Returns the current value of the inner Vault's balance
        access(all) fun currentValue(): UFix64? {
            if let price = self._oracle.price(ofToken: self.vaultType()) {
                // Use UInt256 for calculation
                let uintPrice = DFBMathUtils.toUInt256(price)
                let uintBalance = DFBMathUtils.toUInt256(self._borrowVault().balance)
                let uintValue = DFBMathUtils.mul(uintPrice, uintBalance)
                return DFBMathUtils.toUFix64(uintValue)
            }
            return nil
        }

        /// Creates a Sink for deposits
        access(all) fun createBalancerSink(): {DFB.Sink}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return AutoBalancerSinkV2(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }

        /// Creates a Source for withdrawals
        access(DFB.Get) fun createBalancerSource(): {DFB.Source}? {
            if self._selfCap == nil || !self._selfCap!.check() {
                return nil
            }
            return AutoBalancerSourceV2(autoBalancer: self._selfCap!, uniqueID: self.uniqueID)
        }

        /// Sets the rebalance sink
        access(DFB.Set) fun setSink(_ sink: {DFB.Sink}?) {
            self._rebalanceSink = sink
        }

        /// Sets the rebalance source
        access(DFB.Set) fun setSource(_ source: {DFB.Source}?) {
            self._rebalanceSource = source
        }

        /// Sets the self capability
        access(DFB.Set) fun setSelfCapability(_ cap: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>) {
            pre {
                self._selfCap == nil || self._selfCap!.check() != true:
                "Internal AutoBalancer Capability has been set and is still valid - cannot be re-assigned"
                cap.check(): "Invalid AutoBalancer Capability provided"
                self.getType() == cap.borrow()!.getType() && self.uuid == cap.borrow()!.uuid:
                "Provided Capability does not target this AutoBalancer"
            }
            self._selfCap = cap
        }

        /// Sets the rebalance range
        access(DFB.Set) fun setRebalanceRange(_ range: [UFix64; 2]) {
            pre {
                range[0] < range[1] && 0.01 <= range[0] && range[0] < 1.0 && 1.0 < range[1] && range[1] < 2.0:
                "Invalid rebalanceRange"
            }
            self._rebalanceRange = range
        }

        /// Rebalances the AutoBalancer using high-precision UInt256 calculations
        access(DFB.Auto) fun rebalance(force: Bool) {
            let currentPrice = self._oracle.price(ofToken: self._vaultType)
            if currentPrice == nil {
                return // no price available -> do nothing
            }
            
            // Convert current value to UInt256 for precision
            let uintPrice = DFBMathUtils.toUInt256(currentPrice!)
            let uintBalance = DFBMathUtils.toUInt256(self._borrowVault().balance)
            let uintCurrentValue = DFBMathUtils.mul(uintPrice, uintBalance)
            
            // Calculate value difference using UInt256
            var uintValueDiff: UInt256 = 0
            let isDeficit = uintCurrentValue < self._valueOfDeposits
            if isDeficit {
                uintValueDiff = self._valueOfDeposits - uintCurrentValue
            } else {
                uintValueDiff = uintCurrentValue - self._valueOfDeposits
            }
            
            // Check if rebalance is needed
            if uintPrice == 0 || uintValueDiff == 0 {
                return
            }
            
            // Calculate threshold using UInt256
            let threshold = isDeficit ? (1.0 - self._rebalanceRange[0]) : (self._rebalanceRange[1] - 1.0)
            let uintThreshold = DFBMathUtils.toUInt256(threshold)
            
            // Check if difference exceeds threshold
            let ratio = DFBMathUtils.div(uintValueDiff, self._valueOfDeposits)
            if DFBMathUtils.toUFix64(ratio) < threshold && !force {
                return
            }
            
            // Calculate rebalance amount
            let uintAmount = DFBMathUtils.div(uintValueDiff, uintPrice)
            var amount = DFBMathUtils.toUFix64(uintAmount)
            
            let vault = self._borrowVault()
            var executed = false
            
            if isDeficit && self._rebalanceSource != nil {
                // Pull funds from source
                vault.deposit(from: <- self._rebalanceSource!.withdrawAvailable(maxAmount: amount))
                executed = true
            } else if !isDeficit && self._rebalanceSink != nil {
                // Push excess to sink
                if amount > vault.balance {
                    amount = vault.balance
                }
                let surplus <- vault.withdraw(amount: amount)
                self._rebalanceSink!.depositCapacity(from: &surplus as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                executed = true
                
                if surplus.balance == 0.0 {
                    Burner.burn(<-surplus)
                } else {
                    // Update amounts based on what was actually rebalanced
                    amount = amount - surplus.balance
                    let remainingUintValue = DFBMathUtils.mul(
                        DFBMathUtils.toUInt256(surplus.balance),
                        uintPrice
                    )
                    uintValueDiff = uintValueDiff - remainingUintValue
                    vault.deposit(from: <-surplus)
                }
            }
            
            // Emit event if rebalance was executed
            if executed {
                emit RebalancedV2(
                    amount: amount,
                    value: DFBMathUtils.toUFix64(uintValueDiff),
                    unitOfAccount: self.unitOfAccount().identifier,
                    isSurplus: !isDeficit,
                    vaultType: self.vaultType().identifier,
                    vaultUUID: self._borrowVault().uuid,
                    balancerUUID: self.uuid,
                    address: self.owner?.address,
                    uniqueID: self.id()
                )
            }
        }

        /* ViewResolver.Resolver conformance */
        access(all) view fun getViews(): [Type] {
            return self._borrowVault().getViews()
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            return self._borrowVault().resolveView(view)
        }

        /* FungibleToken.Receiver & Provider conformance */
        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            return { self.vaultType(): true }
        }

        access(all) view fun isSupportedVaultType(type: Type): Bool {
            return self.getSupportedVaultTypes()[type] == true
        }

        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
            return self._borrowVault().isAvailableToWithdraw(amount: amount)
        }

        /// Deposits using high-precision calculations
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            pre {
                from.getType() == self.vaultType():
                "Invalid Vault type deposited"
            }
            
            // Get price or calculate average
            var price = self._oracle.price(ofToken: from.getType())
            if price == nil && self.vaultBalance() > 0.0 {
                // Calculate average price from current holdings
                price = DFBMathUtils.toUFix64(self._valueOfDeposits) / self.vaultBalance()
            }
            
            if price != nil {
                // Update value of deposits using UInt256
                let uintPrice = DFBMathUtils.toUInt256(price!)
                let uintAmount = DFBMathUtils.toUInt256(from.balance)
                let uintValue = DFBMathUtils.mul(uintPrice, uintAmount)
                self._valueOfDeposits = self._valueOfDeposits + uintValue
            }
            
            self._borrowVault().deposit(from: <-from)
        }

        /// Withdraws using high-precision calculations
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            pre {
                amount <= self.vaultBalance(): "Withdraw amount exceeds balance"
            }
            
            if amount == 0.0 {
                return <- self._borrowVault().createEmptyVault()
            }
            
            // Calculate new value of deposits proportionally
            let withdrawRatio = 1.0 - (amount / self.vaultBalance())
            let uintRatio = DFBMathUtils.toUInt256(withdrawRatio)
            self._valueOfDeposits = DFBMathUtils.mul(self._valueOfDeposits, uintRatio)
            
            return <- self._borrowVault().withdraw(amount: amount)
        }

        /* Burnable.Burner conformance */
        access(contract) fun burnCallback() {
            let vault <- self._vault <- nil
            Burner.burn(<-vault)
        }

        /* Internal */
        access(self) view fun _borrowVault(): auth(FungibleToken.Withdraw) &{FungibleToken.Vault} {
            return (&self._vault)!
        }
    }

    /// Sink connector for AutoBalancerV2
    access(all) struct AutoBalancerSinkV2 : DFB.Sink {
        access(self) let autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>
        access(contract) let uniqueID: DFB.UniqueIdentifier?

        init(autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>, uniqueID: DFB.UniqueIdentifier?) {
            self.autoBalancer = autoBalancer
            self.uniqueID = uniqueID
        }

        access(all) view fun getSinkType(): Type {
            return self.autoBalancer.borrow()!.vaultType()
        }

        access(all) fun minimumCapacity(): UFix64 {
            return UFix64.max
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            if from.balance > 0.0 && from.getType() == self.getSinkType() {
                self.autoBalancer.borrow()!.deposit(from: <-from.withdraw(amount: from.balance))
            }
        }
    }

    /// Source connector for AutoBalancerV2
    access(all) struct AutoBalancerSourceV2 : DFB.Source {
        access(self) let autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>
        access(contract) let uniqueID: DFB.UniqueIdentifier?

        init(autoBalancer: Capability<auth(FungibleToken.Withdraw) &AutoBalancerV2>, uniqueID: DFB.UniqueIdentifier?) {
            self.autoBalancer = autoBalancer
            self.uniqueID = uniqueID
        }

        access(all) view fun getSourceType(): Type {
            return self.autoBalancer.borrow()!.vaultType()
        }

        access(all) fun minimumAvailable(): UFix64 {
            return self.autoBalancer.borrow()!.vaultBalance()
        }

        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let available = self.minimumAvailable()
            let amount = available < maxAmount ? available : maxAmount
            return <- self.autoBalancer.borrow()!.withdraw(amount: amount)
        }
    }

    /// Factory function to create AutoBalancerV2
    access(all) fun createAutoBalancerV2(
        oracle: {DFB.PriceOracle},
        vault: @{FungibleToken.Vault},
        rebalanceRange: [UFix64; 2],
        rebalanceSink: {DFB.Sink}?,
        rebalanceSource: {DFB.Source}?,
        uniqueID: DFB.UniqueIdentifier?
    ): @AutoBalancerV2 {
        let vaultType = vault.getType()
        let balancer <- create AutoBalancerV2(
            oracle: oracle,
            vaultType: vaultType,
            lowerThreshold: rebalanceRange[0],
            upperThreshold: rebalanceRange[1],
            rebalanceSink: rebalanceSink,
            rebalanceSource: rebalanceSource,
            uniqueID: uniqueID
        )
        balancer.deposit(from: <-vault)
        return <- balancer
    }
} 