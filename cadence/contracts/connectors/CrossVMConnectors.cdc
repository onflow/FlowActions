import "FungibleToken"
import "FlowToken"
import "EVM"
import "FlowEVMBridge"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "ScopedFTProviders"

import "DeFiActions"
import "DeFiActionsUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// CrossVMConnectors
///
/// This contract defines DeFi Actions Source connector implementations for unified cross-VM balance operations. These
/// connectors can be used alone or in conjunction with other DeFi Actions connectors to create complex DeFi workflows
/// that span both Cadence vaults and EVM Cadence Owned Accounts (COA).
///
access(all) contract CrossVMConnectors {

    /// UnifiedBalanceSource
    ///
    /// A DeFiActions.Source connector that provides unified balance sourcing across Cadence and EVM.
    /// 
    /// Withdrawal Priority:
    /// 1. Cadence vault balance (no fees)
    /// 2. COA native FLOW balance - for FlowToken only (no bridge fees)
    /// 3. COA ERC-20 balance via bridge (incurs bridge fees)
    ///
    /// This ordering minimizes bridge fees by preferring Cadence and native FLOW withdrawals.
    ///
    /// Usage:
    /// ```cadence
    /// let source = CrossVMConnectors.UnifiedBalanceSource(
    ///     vaultType: Type<@FlowToken.Vault>(),
    ///     cadenceVault: vaultCap,
    ///     coa: coaCap,
    ///     feeProvider: feeProviderCap,
    ///     availableCadenceBalance: signer.availableBalance,
    ///     uniqueID: DeFiActions.createUniqueIdentifier()
    /// )
    /// let vault <- source.withdrawAvailable(maxAmount: 100.0)
    /// ```
    ///
    access(all) struct UnifiedBalanceSource: DeFiActions.Source {
        /// The FungibleToken vault type this source provides (e.g., Type<@FlowToken.Vault>())
        access(all) let vaultType: Type
        /// Whether this source handles FlowToken (enables native FLOW optimization)
        access(all) let isFlowToken: Bool
        /// The EVM contract address of the bridged token
        access(all) let evmAddress: EVM.EVMAddress
        /// Available Cadence balance at initialization. For FlowToken, pass signer.availableBalance to account for
        /// storage reservation. For other tokens, pass vault.balance.
        access(all) let availableCadenceBalance: UFix64
        /// Capability to withdraw from the Cadence vault
        access(self) let cadenceVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        /// Capability to the COA for native withdrawals and bridging
        access(self) let coa: Capability<auth(EVM.Withdraw, EVM.Bridge) &EVM.CadenceOwnedAccount>
        /// Capability to provide FLOW for bridge fees
        access(self) let feeProvider: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>
        /// Optional identifier for DeFiActions tracing
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Creates a new UnifiedBalanceSource
        ///
        /// @param vaultType: The FungibleToken vault type to withdraw
        /// @param cadenceVault: Capability to the user's Cadence vault (must be valid)
        /// @param coa: Capability to the user's COA (must be valid)
        /// @param feeProvider: Capability for bridge fee payment (must be valid)
        /// @param availableCadenceBalance: Pre-computed available balance from Cadence. For FlowToken, use
        ///     signer.availableBalance to account for storage reservation. For other tokens, use vault.balance.
        /// @param uniqueID: Optional identifier for Flow Actions tracing
        ///
        init(
            vaultType: Type,
            cadenceVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            coa: Capability<auth(EVM.Withdraw, EVM.Bridge) &EVM.CadenceOwnedAccount>,
            feeProvider: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>,
            availableCadenceBalance: UFix64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                cadenceVault.check():
                "Provided invalid Cadence vault Capability"
                coa.check():
                "Provided invalid COA Capability"
                feeProvider.check():
                "Provided invalid fee provider Capability"
                DeFiActionsUtils.definingContractIsFungibleToken(vaultType):
                "The contract defining Vault \(vaultType.identifier) does not conform to FungibleToken contract interface"
            }
            let evmAddr = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("Token type \(vaultType.identifier) is not bridgeable - ensure the token is onboarded to the VM bridge")

            self.vaultType = vaultType
            self.isFlowToken = vaultType == Type<@FlowToken.Vault>()
            self.evmAddress = evmAddr
            self.availableCadenceBalance = availableCadenceBalance
            self.cadenceVault = cadenceVault
            self.coa = coa
            self.feeProvider = feeProvider
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this UnifiedBalanceSource and its inner DFA
        /// components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }

        /// Returns the Vault type provided by this Source
        ///
        /// @return the type of the Vault this Source provides
        ///
        access(all) view fun getSourceType(): Type {
            return self.vaultType
        }

        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        /// Returns an estimate of how much of the associated Vault can be provided by this Source
        ///
        /// @return the total available balance across Cadence vault and COA
        ///
        access(all) fun minimumAvailable(): UFix64 {
            return self._getCadenceBalance() + self._getCOABalance()
        }

        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault is returned.
        /// Withdrawal priority: Cadence vault → COA native FLOW (for FlowToken) → COA ERC-20 via bridge.
        ///
        /// @param maxAmount: the maximum amount to withdraw
        ///
        /// @return a Vault containing the withdrawn funds (may be less than maxAmount if insufficient balance)
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let available = self.minimumAvailable()
            if available == 0.0 || maxAmount == 0.0 {
                return <-DeFiActionsUtils.getEmptyVault(self.vaultType)
            }

            let withdrawAmount = available <= maxAmount ? available : maxAmount
            let cadenceBalance = self._getCadenceBalance()

            // Calculate amounts from each source
            let amountFromCadence = cadenceBalance < withdrawAmount ? cadenceBalance : withdrawAmount
            var amountFromCOA = withdrawAmount - amountFromCadence

            // Withdraw from Cadence vault
            let vault = self.cadenceVault.borrow()!
            let result <- vault.withdraw(amount: amountFromCadence)

            // Bridge from COA if Cadence balance was insufficient
            if amountFromCOA > 0.0 {
                let coaRef = self.coa.borrow()!
                var remaining = amountFromCOA

                // For FlowToken: withdraw native FLOW first (no bridge fees)
                if self.isFlowToken {
                    let nativeFlowBalance = coaRef.balance().inFLOW()
                    if nativeFlowBalance > 0.0 {
                        let nativeWithdraw = nativeFlowBalance < remaining ? nativeFlowBalance : remaining
                        let withdrawBal = EVM.Balance(attoflow: 0)
                        withdrawBal.setFLOW(flow: nativeWithdraw)
                        result.deposit(from: <-coaRef.withdraw(balance: withdrawBal))
                        remaining = remaining - nativeWithdraw
                    }
                }

                // Bridge ERC-20 if still needed
                if remaining > 0.0 {
                    let scopedProvider <- ScopedFTProviders.createScopedFTProvider(
                        provider: self.feeProvider,
                        filters: [ScopedFTProviders.AllowanceFilter(FlowEVMBridgeUtils.calculateBridgeFee(bytes: 400_000))],
                        expiration: getCurrentBlock().timestamp + 1.0
                    )

                    let bridged <- coaRef.withdrawTokens(
                        type: self.vaultType,
                        amount: FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(remaining, erc20Address: self.evmAddress),
                        feeProvider: &scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
                    )
                    result.deposit(from: <-bridged)
                    destroy scopedProvider
                }
            }

            return <-result
        }

        /// Returns the available Cadence balance (passed at initialization)
        access(self) fun _getCadenceBalance(): UFix64 {
            return self.availableCadenceBalance
        }

        /// Returns the total COA balance (native FLOW for FlowToken + ERC-20)
        access(self) fun _getCOABalance(): UFix64 {
            if let coaRef = self.coa.borrow() {
                var balance: UFix64 = 0.0

                // Add native FLOW balance for FlowToken
                if self.isFlowToken {
                    balance = balance + coaRef.balance().inFLOW()
                }

                // Add ERC-20 balance
                let erc20Balance = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    FlowEVMBridgeUtils.balanceOf(owner: coaRef.address(), evmContractAddress: self.evmAddress),
                    erc20Address: self.evmAddress
                )
                balance = balance + erc20Balance

                return balance
            }
            return 0.0
        }
    }
}
