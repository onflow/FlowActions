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

    // PriceData
    //
    /// A data structure containing data relevant to PriceOracle requests serving data about onchain assets
    access(all) struct PriceData : DFB.PriceData {
        /// The fixed point rate between the BASE/QUOTE pair limited to UFix64 decimal precision of 8 places
        access(all) let rate: UFix64
        /// The integer rate between the BASE/QUOTE pair enabling greater decimal precision
        access(all) let integerRate: UInt256
        /// The integerRate decimal places
        access(all) let integerDecimals: UInt8
        /// The base asset type in the BASE/QUOTE pair
        access(all) let baseType: Type
        /// The quote asset type in the BASE/QUOTE pair
        access(all) let quoteType: Type
        /// Timestamp at which the baseType price data was last updated
        access(all) let baseTimestamp: UFix64
        /// Timestamp at which the quoteType price data was last updated
        access(all) let quoteTimestamp: UFix64
        init(
            rate: UFix64,
            integerRate: UInt256,
            integerDecimals: UInt8,
            baseType: Type,
            quoteType: Type,
            baseTimestamp: UFix64,
            quoteTimestamp: UFix64
        )
        {
            self.rate = rate
            self.integerRate = integerRate
            self.integerDecimals = integerDecimals
            self.baseType = baseType
            self.quoteType = quoteType
            self.baseTimestamp = baseTimestamp
            self.quoteTimestamp = quoteTimestamp
        }
    }

    // PriceOracle
    //
    /// An adapter for BandOracle as an implementation of the DeFiBlocks PriceOracle interface
    access(all) struct PriceOracle : DFB.PriceOracle {
        /// Returns the Vault type denominating any required request fee if one is required
        access(all) fun getRequestFeeType(): Type? {
            return Type<@FlowToken.Vault>()
        }

        /// Returns the fee amount (denominated by `getRequestFeeType()`) due to serve oracle requests if any
        access(all) fun getRequestFee(): UFix64 {
            return BandOracle.getFee()
        }

        /// Returns the timestamp at which the price data was last updated for a given asset type
        access(all) fun getLastUpdateTimestamp(forAsset: Type): UFix64? {
            return getCurrentBlock().timestamp // TODO - tmp
        }

        /// Returns the latest price data for a given BASE/QUOTE pair, allowing for an optional fee to be provided if
        /// one is required by the oracle protocol
        access(all) fun getLatestPrice(base: Type, quote: Type, fee: @{FungibleToken.Vault}?): {DFB.PriceData}? {
            let baseSymbol = BandOracleAdapters.assetSymbols[base]
            let quoteSymbol = BandOracleAdapters.assetSymbols[base]
            if fee == nil {
                Burner.burn(<-fee)
                return nil
            } else if baseSymbol == nil {
                panic("Base asset type \(base.identifier) does not have an assigned symbol")
            } else if quoteSymbol == nil {
                panic("Quote asset type \(quote.identifier) does not have an assigned symbol")
            }
            let refData = BandOracle.getReferenceData(baseSymbol: baseSymbol!, quoteSymbol: quoteSymbol!, payment: <-fee!)
            // TODO
            return PriceData(
                rate: refData.fixedPointRate,
                integerRate: refData.integerE18Rate,
                integerDecimals: 18,
                baseType: base,
                quoteType: quote,
                baseTimestamp: UFix64(refData.baseTimestamp),
                quoteTimestamp: UFix64(refData.quoteTimestamp)
            )
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
