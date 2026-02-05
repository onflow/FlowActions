import "Burner"
import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "FlowToken"
import "DeFiActions"
import "DeFiActionsUtils"
import "MorphoERC4626SinkConnectors"
import "SwapConnectors"
import "EVMTokenConnectors"
import "ERC4626Utils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// MorphoERC4626SwapConnectors
///
/// Implements the DeFiActions.Swapper interface to swap asset tokens to 4626 shares, integrating the connector with an
/// EVM Morpho ERC4626 Vault.
///
access(all) contract MorphoERC4626SwapConnectors {

    /// Swapper
    ///
    /// An implementation of the DeFiActions.Swapper interface to swap assets to 4626 shares where the input token is
    /// underlying asset in the 4626 vault. Both the asset & the 4626 shares must be onboarded to the VM bridge in order
    /// for liquidity to flow between Cadence & EVM. These "swaps" are performed by depositing the input asset into the
    /// ERC4626 vault and withdrawing the resulting shares from the ERC4626 vault.
    ///
    access(all) struct Swapper : DeFiActions.Swapper {
        /// The asset type serving as the price basis in the ERC4626 vault
        access(self) let assetType: Type
        /// The EVM address of the asset ERC20 asset underlying the ERC4626 vault
        access(self) let assetEVMAddress: EVM.EVMAddress
        /// The address of the ERC4626 vault
        access(self) let vaultEVMAddress: EVM.EVMAddress
        /// The type of the bridged ERC4626 vault
        access(self) let vaultType: Type
        /// The token sink to use for the ERC4626 vault
        access(self) let assetSink: MorphoERC4626SinkConnectors.AssetSink
        /// The token source to use for the ERC4626 vault
        access(self) let shareSource: EVMTokenConnectors.Source
        /// The token sink to bridge ERC4626 shares into the COA/EVM
        access(self) let shareSink: MorphoERC4626SinkConnectors.ShareSink
        /// The token source to withdraw underlying assets back from the COA/EVM
        access(self) let assetSource: EVMTokenConnectors.Source
        /// The optional UniqueIdentifier of the ERC4626 vault
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// If true, the Swapper is configured "reversed":
        ///   inType = vaultType (shares), outType = assetType (assets)
        access(self) let isReversed: Bool

        init(
            vaultEVMAddress: EVM.EVMAddress,
            coa: Capability<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?,
            isReversed: Bool
        ) {
            pre {
                coa.check():
                "Provided COA Capability is invalid - need Capability<&EVM.CadenceOwnedAccount>"

                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
            }

            self.uniqueID = uniqueID
            self.isReversed = isReversed

            self.vaultEVMAddress = vaultEVMAddress
            self.vaultType = FlowEVMBridgeConfig.getTypeAssociated(with: self.vaultEVMAddress)
                ?? panic("Provided ERC4626 Vault \(self.vaultEVMAddress.toString()) is not associated with a Cadence FungibleToken - ensure the type & ERC4626 contracts are associated via the VM bridge")
            assert(
                DeFiActionsUtils.definingContractIsFungibleToken(self.vaultType),
                message: "Derived vault type \(self.vaultType.identifier) not FungibleToken type"
            )

            self.assetEVMAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: self.vaultEVMAddress)
                ?? panic("Cannot get an underlying asset EVM address from the vault")
            self.assetType = FlowEVMBridgeConfig.getTypeAssociated(with: self.assetEVMAddress)
                ?? panic("Underlying asset for vault \(self.vaultEVMAddress.toString()) (asset \(self.assetEVMAddress.toString())) is not associated with a Cadence FungibleToken - ensure the type & underlying asset contracts are associated via the VM bridge")
            assert(
                DeFiActionsUtils.definingContractIsFungibleToken(self.assetType),
                message: "Derived asset type \(self.assetType.identifier) not FungibleToken type"
            )

            self.assetSink = MorphoERC4626SinkConnectors.AssetSink(
                vaultEVMAddress: self.vaultEVMAddress,
                coa: coa,
                feeSource: feeSource,
                uniqueID: self.uniqueID
            )
            self.shareSource = EVMTokenConnectors.Source(
                min: nil,
                withdrawVaultType: self.vaultType,
                coa: coa,
                feeSource: feeSource,
                uniqueID: self.uniqueID
            )

            self.shareSink = MorphoERC4626SinkConnectors.ShareSink(
                vaultEVMAddress: self.vaultEVMAddress,
                coa: coa,
                feeSource: feeSource,
                uniqueID: self.uniqueID
            )

            self.assetSource = EVMTokenConnectors.Source(
                min: nil,
                withdrawVaultType: self.assetType,
                coa: coa,
                feeSource: feeSource,
                uniqueID: self.uniqueID
            )
        }

        // -------------------------
        // Direction-aware in/out
        // -------------------------

        access(all) view fun inType(): Type {
            return self.isReversed ? self.vaultType : self.assetType
        }

        access(all) view fun outType(): Type {
            return self.isReversed ? self.assetType : self.vaultType
        }

        access(self) fun quoteRequiredAssetsForShares(desiredShares: UFix64): {DeFiActions.Quote} {
            let desiredSharesEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                desiredShares,
                erc20Address: self.vaultEVMAddress
            )

            if let requiredAssetsEVM = ERC4626Utils.previewMint(vault: self.vaultEVMAddress, shares: desiredSharesEVM) {
                let maxAssetsEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                    UFix64.max,
                    erc20Address: self.assetEVMAddress
                )
                let requiredAssetsEVMSafe = requiredAssetsEVM < maxAssetsEVM ? requiredAssetsEVM : maxAssetsEVM
                let requiredAssets = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    requiredAssetsEVMSafe,
                    erc20Address: self.assetEVMAddress
                )

                return SwapConnectors.BasicQuote(
                    inType: self.assetType,
                    outType: self.vaultType,
                    inAmount: requiredAssets,
                    outAmount: desiredShares
                )
            }

            return SwapConnectors.BasicQuote(
                inType: self.assetType,
                outType: self.vaultType,
                inAmount: 0.0,
                outAmount: 0.0
            )
        }

        access(self) fun quoteRequiredSharesForAssets(desiredAssets: UFix64): {DeFiActions.Quote} {
            let desiredAssetsEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                desiredAssets,
                erc20Address: self.assetEVMAddress
            )

            if let requiredSharesEVM = ERC4626Utils.previewWithdraw(vault: self.vaultEVMAddress, assets: desiredAssetsEVM) {
                let maxSharesEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                    UFix64.max,
                    erc20Address: self.vaultEVMAddress
                )
                let requiredSharesEVMSafe = requiredSharesEVM < maxSharesEVM ? requiredSharesEVM : maxSharesEVM
                let requiredShares = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    requiredSharesEVMSafe,
                    erc20Address: self.vaultEVMAddress
                )

                return SwapConnectors.BasicQuote(
                    inType: self.vaultType,
                    outType: self.assetType,
                    inAmount: requiredShares,
                    outAmount: desiredAssets
                )
            }

            return SwapConnectors.BasicQuote(
                inType: self.vaultType,
                outType: self.assetType,
                inAmount: 0.0,
                outAmount: 0.0
            )
        }

        // --------------------------------------------------------------------
        // Direction model
        //
        // Canonical "forward" direction for this connector is:
        //     assets (underlying ERC20) -> shares (ERC4626 vault token)
        //
        // The effective swap / quote direction is determined by TWO flags:
        //
        // 1. self.isReversed
        //    - false: connector is configured in canonical forward mode
        //    - true:  connector is configured reversed (shares -> assets)
        //
        // 2. reverse (method parameter)
        //    - false: quote/swap in the connector's configured direction
        //    - true:  quote/swap in the opposite direction
        //
        // The resulting direction is:
        //
        //     assetsToShares = (self.isReversed == reverse)
        //
        // Truth table:
        //
        //   isReversed | reverse | effective direction
        //   -----------+---------+--------------------
        //     false    |  false  | assets  -> shares
        //     false    |  true   | shares  -> assets
        //     true     |  false  | shares  -> assets
        //     true     |  true   | assets  -> shares
        //
        // This same rule is used consistently for:
        //   - quoteIn / quoteOut
        //   - swap / swapBack (with different fallbacks)
        // --------------------------------------------------------------------

        /// desired OUT amount -> required IN amount
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            // canonical forward = assets -> shares
            // effective assets->shares when isReversed == reverse
            let assetsToShares = (self.isReversed == reverse)

            return assetsToShares
                ? self.quoteRequiredAssetsForShares(desiredShares: forDesired)
                : self.quoteRequiredSharesForAssets(desiredAssets: forDesired)
        }
        access(self) fun quoteSharesOutForAssetsIn(providedAssets: UFix64): {DeFiActions.Quote} {
            let providedAssetsEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                providedAssets,
                erc20Address: self.assetEVMAddress
            )

            if let sharesOutEVM = ERC4626Utils.previewDeposit(vault: self.vaultEVMAddress, assets: providedAssetsEVM) {
                let sharesOut = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    sharesOutEVM,
                    erc20Address: self.vaultEVMAddress
                )

                return SwapConnectors.BasicQuote(
                    inType: self.assetType,
                    outType: self.vaultType,
                    inAmount: providedAssets,
                    outAmount: sharesOut
                )
            }

            return SwapConnectors.BasicQuote(
                inType: self.assetType,
                outType: self.vaultType,
                inAmount: 0.0,
                outAmount: 0.0
            )
        }

        access(self) fun quoteAssetsOutForSharesIn(providedShares: UFix64): {DeFiActions.Quote} {
            let providedSharesEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                providedShares,
                erc20Address: self.vaultEVMAddress
            )

            if let assetsOutEVM = ERC4626Utils.previewRedeem(vault: self.vaultEVMAddress, shares: providedSharesEVM) {
                let assetsOut = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                    assetsOutEVM,
                    erc20Address: self.assetEVMAddress
                )

                return SwapConnectors.BasicQuote(
                    inType: self.vaultType,
                    outType: self.assetType,
                    inAmount: providedShares,
                    outAmount: assetsOut
                )
            }

            return SwapConnectors.BasicQuote(
                inType: self.vaultType,
                outType: self.assetType,
                inAmount: 0.0,
                outAmount: 0.0
            )
        }

        /// provided IN amount -> estimated OUT amount
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            // canonical forward = assets -> shares
            // effective assets->shares when isReversed == reverse
            let assetsToShares = (self.isReversed == reverse)

            return assetsToShares
                ? self.quoteSharesOutForAssetsIn(providedAssets: forProvided)
                : self.quoteAssetsOutForSharesIn(providedShares: forProvided)
        }

        // -------------------------
        // Swap internals
        // -------------------------

        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(self) fun swapAssetsToShares(
            quote: {DeFiActions.Quote}?,
            inVault: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault} {
            if inVault.balance == 0.0 {
                Burner.burn(<-inVault)
                return <- DeFiActionsUtils.getEmptyVault(self.vaultType)
            }

            // assign or get the quote for the swap
            let _quote = quote ?? self.quoteSharesOutForAssetsIn(providedAssets: inVault.balance)
            let outAmount = _quote.outAmount

            assert(_quote.inType == self.assetType, message: "Swap: Quote inType mismatch (expected asset)")
            assert(_quote.outType == self.vaultType, message: "Swap: Quote outType mismatch (expected shares)")
            assert(_quote.inAmount > 0.0, message: "Invalid quote: inAmount must be > 0")
            assert(outAmount > 0.0, message: "Invalid quote: outAmount must be > 0")

            // --- Slippage protection: don't allow spending more than quoted ---
            let beforeInBalance = inVault.balance
            assert(
                beforeInBalance <= _quote.inAmount,
                message: "Swap input (\(beforeInBalance)) exceeds quote.inAmount (\(_quote.inAmount)). Provide an updated quote or reduce inVault balance."
            )

            // Track shares available before/after to determine received shares
            let beforeAvailable = self.shareSource.minimumAvailable()

            // Deposit the inVault into the asset sink (should consume all of it)
            self.assetSink.depositCapacity(from: &inVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            let remainder = inVault.balance
            let consumedIn = beforeInBalance - remainder

            // We expect full consumption in this connector's semantics.
            // If this ever becomes "partial fill" in the future, this check + price check below
            // ensures it still can't be worse than quoted.
            assert(consumedIn > 0.0, message: "Asset sink did not consume any input.")
            assert(remainder == 0.0, message: "Asset sink did not consume full input; remainder: \(remainder.toString()).")

            Burner.burn(<-inVault)

            // get the after available shares
            let afterAvailable = self.shareSource.minimumAvailable()
            assert(afterAvailable > beforeAvailable, message: "Expected ERC4626 Vault \(self.vaultEVMAddress.toString()) to have more shares after depositing")

            // withdraw the available difference in shares
            let receivedShares = afterAvailable - beforeAvailable

            // --- Slippage protection: ensure minimum out ---
            assert(
                receivedShares >= outAmount,
                message: "Slippage: received \(receivedShares) < quote.outAmount (\(outAmount))."
            )

            let sharesVault <- self.shareSource.withdrawAvailable(maxAmount: receivedShares)

            // Extra safety: ensure the vault we’re returning matches the computed delta
            // (withdrawAvailable could theoretically return less if liquidity changed)
            assert(
                sharesVault.balance >= outAmount,
                message: "Slippage: withdrawn shares \(sharesVault.balance) < outAmount (\(outAmount))."
            )

            return <- sharesVault
        }

        access(self) fun swapSharesToAssets(
            quote: {DeFiActions.Quote}?,
            inVault: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault} {
            if inVault.balance == 0.0 {
                Burner.burn(<-inVault)
                return <- DeFiActionsUtils.getEmptyVault(self.assetType)
            }

            // assign or get a quote from the swap
            let _quote = quote ?? self.quoteAssetsOutForSharesIn(providedShares: inVault.balance)
            let outAmount = _quote.outAmount

            // Ensure the quote represents the inverse of this connector’s forward swap:
            // swapback must take this connector’s outType and return its inType.
            // These checks prevent executing a quote meant for a different connector
            // or accidentally performing a forward swap instead of a reversal.
            assert(_quote.inType == self.vaultType, message: "Swap: Quote inType mismatch (expected shares)")
            assert(_quote.outType == self.assetType, message: "Swap: Quote outType mismatch (expected asset)")
            assert(_quote.inAmount > 0.0, message: "Invalid quote: inAmount must be > 0")
            assert(outAmount > 0.0, message: "Invalid quote: outAmount must be > 0")

            // Track assets available before/after to determine received assets
            let beforeInBalance = inVault.balance
            assert(
                beforeInBalance <= _quote.inAmount,
                message: "Swap input (\(beforeInBalance)) exceeds quote.inAmount (\(_quote.inAmount)). Provide an updated quote or reduce inVault balance."
            )

            let beforeAvailable = self.assetSource.minimumAvailable()

            self.shareSink.depositCapacity(from: &inVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            let remainder = inVault.balance
            let consumedIn = beforeInBalance - remainder

            assert(consumedIn > 0.0, message: "Share sink did not consume any input.")
            assert(remainder == 0.0, message: "Share sink did not consume full input; remainder: \(remainder.toString()).")

            Burner.burn(<-inVault)

            let afterAvailable = self.assetSource.minimumAvailable()
            assert(afterAvailable > beforeAvailable, message: "Expected more assets after depositing")

            let receivedAssets = afterAvailable - beforeAvailable

            assert(receivedAssets >= outAmount, message: "Slippage: received < quote.outAmount")

            let assetsVault <- self.assetSource.withdrawAvailable(maxAmount: receivedAssets)
            assert(assetsVault.balance >= outAmount, message: "Slippage: withdrawn assets < outAmount")

            return <- assetsVault
        }

        // -------------------------
        // Direction-aware swap entrypoints
        // -------------------------

        access(self) fun quoteIndicatesAssetsToShares(_ q: {DeFiActions.Quote}): Bool {
            return q.inType == self.assetType && q.outType == self.vaultType
        }

        access(self) fun quoteIndicatesSharesToAssets(_ q: {DeFiActions.Quote}): Bool {
            return q.inType == self.vaultType && q.outType == self.assetType
        }

        access(self) fun decideAssetsToShares(
            quote: {DeFiActions.Quote}?,
            fallbackAssetsToShares: Bool
        ): Bool {
            if quote == nil {
                return fallbackAssetsToShares
            }
            assert(
                self.quoteIndicatesAssetsToShares(quote!) || self.quoteIndicatesSharesToAssets(quote!),
                message: "Quote types not recognized for this connector"
            )
            return self.quoteIndicatesAssetsToShares(quote!)
        }

        access(self) fun assertInputVaultType(
            _ vault: &{FungibleToken.Vault},
            assetsToShares: Bool,
            context: String
        ) {
            let expectedType = assetsToShares ? self.assetType : self.vaultType
            assert(
                vault.getType() == expectedType,
                message: "\(context): input vault type mismatch. Expected \(expectedType.identifier), got \(vault.getType().identifier)"
            )
        }

        access(all) fun swap(
            quote: {DeFiActions.Quote}?,
            inVault: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault} {
            // Decide direction:
            // - if quote provided, trust its type pair
            // - else fall back to configured direction (isReversed)
            let assetsToShares = self.decideAssetsToShares(quote: quote, fallbackAssetsToShares: !self.isReversed)

            self.assertInputVaultType(
                &inVault as &{FungibleToken.Vault},
                assetsToShares: assetsToShares,
                context: "Swap"
            )

            if assetsToShares {
                return <- self.swapAssetsToShares(quote: quote, inVault: <-inVault)
            }
            return <- self.swapSharesToAssets(quote: quote, inVault: <-inVault)
        }

        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(
            quote: {DeFiActions.Quote}?,
            residual: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault} {
            // Decide direction:
            // - if quote provided, trust its type pair
            // - else fall back to configured direction (isReversed)
            let assetsToShares = self.decideAssetsToShares(quote: quote, fallbackAssetsToShares: self.isReversed)

            self.assertInputVaultType(
                &residual as &{FungibleToken.Vault},
                assetsToShares: assetsToShares,
                context: "SwapBack"
            )

            if assetsToShares {
                return <- self.swapAssetsToShares(quote: quote, inVault: <-residual)
            }
            return <- self.swapSharesToAssets(quote: quote, inVault: <-residual)
        }

        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.assetSink.getComponentInfo(),
                    self.shareSource.getComponentInfo(),
                    self.shareSink.getComponentInfo(),
                    self.assetSource.getComponentInfo()
                ]
            )
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
    }
}
