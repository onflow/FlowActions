import "Burner"
import "FungibleToken"
import "FlowToken"
import "BandOracle"

import "DFB"

/// BandOracleAdapters
///
/// This contract adapts BandOracle's price data oracle contracts for use as a DeFiBlocks PriceOracle connector
///
access(all) contract BandOracleAdapters {

    /// Mapping of asset Types to BandOracle symbols
    access(all) let assetSymbols: {Type: String}
    /// StoragePath for the SymbolUpdater tasked with adding Type:SYMBOL pairs
    access(self) let SymbolUpdaterStoragePath: StoragePath

    /* EVENTS */
    /// Emitted when a Type:SYMBOL pair is added via the SymbolUpdater resource
    access(all) event SymbolAdded(symbol: String, asset: String)

    /* CONSTRUCTS */

    // PriceOracle
    //
    /// An adapter for BandOracle as an implementation of the DeFiBlocks PriceOracle interface
    access(all) struct PriceOracle : DFB.PriceOracle {
        /// The token type serving as the price basis - e.g. USD in FLOW/USD
        access(self) let quote: Type
        /// A Source providing the FlowToken necessary for BandOracle price data requests
        access(self) let feeSource: {DFB.Source}
        /// The amount of seconds beyond which a price is considered stale and a price() call reverts
        access(self) let staleThreshold: UInt64?

        init(unitOfAccount: Type, staleThreshold: UInt64?, feeSource: {DFB.Source}) {
            pre {
                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
                unitOfAccount.getType().isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Invalid unitOfAccount - \(unitOfAccount.identifier) is not a FungibleToken.Vault implementation"
                BandOracleAdapters.assetSymbols[unitOfAccount] != nil:
                "Could not find a BandOracle symbol assigned to unitOfAccount \(unitOfAccount.identifier)"
            }
            self.feeSource = feeSource
            self.quote = unitOfAccount
            self.staleThreshold = staleThreshold
        }

        /// Returns the asset type serving as the price basis - e.g. USD in FLOW/USD
        access(all) view fun unitOfAccount(): Type {
            return self.quote
        }

        /// Returns the latest price data for a given asset denominated in unitOfAccount(). Since BandOracle requests
        /// are paid, this implementation reverts if price data has gone stale
        access(all) fun price(ofToken: Type): UFix64? {
            // lookup the symbols
            let baseSymbol = BandOracleAdapters.assetSymbols[ofToken]
                ?? panic("Base asset type \(ofToken.identifier) does not have an assigned symbol")
            let quoteSymbol = BandOracleAdapters.assetSymbols[self.unitOfAccount()]!
            // withdraw the oracle fee & get the price data from BandOracle
            let fee <- self.feeSource.withdrawAvailable(maxAmount: BandOracle.getFee())
            let priceData = BandOracle.getReferenceData(baseSymbol: baseSymbol, quoteSymbol: quoteSymbol, payment: <-fee)

            // check price data has not gone stale based on last updated timestamp
            let now = UInt64(getCurrentBlock().timestamp)
            if self.staleThreshold != nil {
                assert(now < priceData.baseTimestamp + self.staleThreshold!, 
                    message: "Price data's base timestamp \(priceData.baseTimestamp) exceeds the staleThreshold "
                        .concat("\(priceData.baseTimestamp + self.staleThreshold!) at current timestamp \(now)"))
                assert(now < priceData.quoteTimestamp + self.staleThreshold!,
                    message: "Price data's quote timestamp \(priceData.quoteTimestamp) exceeds the staleThreshold "
                        .concat("\(priceData.quoteTimestamp + self.staleThreshold!) at current timestamp \(now)"))
            }

            return priceData.fixedPointRate
        }
    }

    // SymbolUpdater
    //
    /// Resource enabling the addition of new Type:SYMBOL pairings as they are supported by BandOracle's price oracle
    access(all) resource SymbolUpdater {
        /// Adds a Type:SYMBOL pairing to the contract's mapping. Reverts if the asset Type is already assigned a symbol
        access(all) fun addSymbol(_ symbol: String, forAsset: Type) {
            pre {
                BandOracleAdapters.assetSymbols[forAsset] == nil:
                "Asset \(forAsset.identifier) is already assigned symbol \(BandOracleAdapters.assetSymbols[forAsset]!)"
            }
            BandOracleAdapters.assetSymbols[forAsset] = symbol

            emit SymbolAdded(symbol: symbol, asset: forAsset.identifier)
        }
    }

    init() {
        self.assetSymbols = {
            Type<@FlowToken.Vault>(): "FLOW"
        }
        self.SymbolUpdaterStoragePath = StoragePath(identifier: "BandOracleAdapterSymbolUpdater_\(self.account.address)")!
        self.account.storage.save(<-create SymbolUpdater(), to: self.SymbolUpdaterStoragePath)
    }
}
