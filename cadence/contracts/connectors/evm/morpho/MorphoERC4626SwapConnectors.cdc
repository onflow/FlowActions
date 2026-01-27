import "Burner"
import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
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
/// ERC4626SwapConnectors
///
/// Implements the DeFiActions.Swapper interface to swap asset tokens to 4626 shares, integrating the connector with an
/// EVM ERC4626 Vault.
///
access(all) contract MorphoERC4626SwapConnectors {

    /// Swapper
    ///
    /// An implementation of the DeFiActions.Swapper interface to swap assets to 4626 shares where the input token is
    /// underlying asset in the 4626 vault. Both the asset & the 4626 shares must be onboarded to the VM bridge in order
    /// for liquidity to flow between Cadnece & EVM. These "swaps" are performed by depositing the input asset into the
    /// ERC4626 vault and withdrawing the resulting shares from the ERC4626 vault.
    ///
    /// NOTE: Since ERC4626 vaults typically do not support synchronous withdrawals, this Swapper only supports the
    ///     default inType -> outType path via swap() and reverts on swapBack() since the withdrawal cannot be returned
    ///     synchronously.
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

        init(
            assetType: Type,
            vaultEVMAddress: EVM.EVMAddress,
            coa: Capability<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>,
            feeSource: {DeFiActions.Sink, DeFiActions.Source},
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                DeFiActionsUtils.definingContractIsFungibleToken(asset):
                "Provided asset \(assetType.identifier) is not a Vault type"
                coa.check():
                "Provided COA Capability is invalid - need Capability<&EVM.CadenceOwnedAccount>"
            }
            self.assetType = assetType
            self.assetEVMAddress = FlowEVMBridgeConfig.getEVMAddressAssociated(with: assetType)
                ?? panic("Provided asset \(assetType.identifier) is not associated with ERC20 - ensure the type & ERC20 contracts are associated via the VM bridge")
            self.vaultEVMAddress = vaultEVMAddress
            self.vaultType = FlowEVMBridgeConfig.getTypeAssociated(with: vaultEVMAddress)
                ?? panic("Provided ERC4626 Vault \(vaultEVMAddress.toString()) is not associated with a Cadence FungibleToken - ensure the type & ERC4626 contracts are associated via the VM bridge")

            self.assetSink = MorphoERC4626SinkConnectors.AssetSink(
                assetType: assetType,
                vaultEVMAddress: vaultEVMAddress,
                coa: coa,
                feeSource: feeSource,
                uniqueID: uniqueID
            )
            self.shareSource = EVMTokenConnectors.Source(
                min: nil,
                withdrawVaultType: self.vaultType,
                coa: coa,
                feeSource: feeSource,
                uniqueID: uniqueID
            )

            self.shareSink = MorphoERC4626SinkConnectors.ShareSink(
                assetType: assetType,
                vaultEVMAddress: vaultEVMAddress,
                coa: coa,
                feeSource: feeSource,
                uniqueID: uniqueID
            )

            self.assetSource = EVMTokenConnectors.Source(
                min: nil,
                withdrawVaultType: self.assetType,
                coa: coa,
                feeSource: feeSource,
                uniqueID: uniqueID
            )

            self.uniqueID = uniqueID
        }

        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inType(): Type {
            return self.assetType
        }
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outType(): Type {
            return self.vaultType
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

        /// desired OUT amount -> required IN amount
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            return reverse
                ? self.quoteRequiredSharesForAssets(desiredAssets: forDesired)
                : self.quoteRequiredAssetsForShares(desiredShares: forDesired)
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
            return reverse
                ? self.quoteAssetsOutForSharesIn(providedShares: forProvided)
                : self.quoteSharesOutForAssetsIn(providedAssets: forProvided)
        }

        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            if inVault.balance == 0.0 {
                // nothing to swap - burn the inVault and return an empty outVault
                Burner.burn(<-inVault)
                return <- DeFiActionsUtils.getEmptyVault(self.vaultType)
            }

            // assign or get the quote for the swap
            let _quote = quote ?? self.quoteOut(forProvided: inVault.balance, reverse: false)
            let outAmount = _quote.outAmount

            assert(_quote.inType == self.inType(), message: "Quote inType mismatch")
            assert(_quote.outType == self.outType(), message: "Quote outType mismatch")
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
            assert(
                consumedIn > 0.0,
                message: "Asset sink did not consume any input."
            )
            assert(remainder == 0.0, message: "Asset sink did not consume full input; remainder: \(remainder.toString()). Adjust inVault balance.") 

            assert(self.assetSink.minimumCapacity() > 0.0, message: "Expected ERC4626 Asset Sink to have capacity after depositing")
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
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            if residual.balance == 0.0 {
                Burner.burn(<-residual)
                return <- DeFiActionsUtils.getEmptyVault(self.assetType)
            }

            // assign or get a quote from the swap
            let _quote = quote ?? self.quoteOut(forProvided: residual.balance, reverse: true)
            let outAmount = _quote.outAmount
            
            assert(_quote.inType == self.outType(), message: "Quote inType mismatch")
            assert(_quote.outType == self.inType(), message: "Quote outType mismatch")
            assert(_quote.inAmount > 0.0, message: "Invalid quote: inAmount must be > 0")
            assert(outAmount > 0.0, message: "Invalid quote: outAmount must be > 0")

            // Track assets availbe before/after to determine received assets
            let beforeInBalance = residual.balance
            assert(
                beforeInBalance <= _quote.inAmount,
                message: "SwapBack input (\(beforeInBalance)) exceeds quote.inAmount (\(_quote.inAmount)). Provide an updated quote or reduce inVault balance."
            )

            let beforeAvailable = self.assetSource.minimumAvailable()

            self.shareSink.depositCapacity(from: &residual as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            let remainder = residual.balance
            let consumedIn = beforeInBalance - remainder

            assert(
                consumedIn > 0.0,
                message: "Share sink did not consume any input."
            )
            assert(remainder == 0.0, message: "Share sink did not consume full input; remainder: \(remainder.toString()). Adjust inVault balance.")
            assert(self.shareSink.minimumCapacity() > 0.0, message: "Expected ERC4626 Share Sink to have capacity after depositing")
            Burner.burn(<-residual)

            let afterAvailable = self.assetSource.minimumAvailable()
            assert(afterAvailable > beforeAvailable, message: "Expected asset \(self.assetEVMAddress.toString()) to have more after depositing")

            let receivedAssets = afterAvailable - beforeAvailable

            assert(
                receivedAssets >= outAmount,
                message: "Slippage: received (\(receivedAssets)) < quote.outAmount (\(outAmount))."
            )
            let assetsVault <- self.assetSource.withdrawAvailable(maxAmount: receivedAssets)

            assert(
                assetsVault.balance >= outAmount,
                message: "Slippage: withdrawn assets (\(assetsVault.balance)) < outAmount (\(outAmount))"
            )

            return <- assetsVault
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
