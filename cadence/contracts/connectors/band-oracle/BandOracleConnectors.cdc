import "Burner"
import "FungibleToken"
import "FlowToken"
import "BandOracle"

import "DeFiActions"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// BandOracleConnectors
///
/// This contract adapts BandOracle's price data oracle contracts for use as a DeFiActions PriceOracle connector
///
access(all) contract BandOracleConnectors {

    /// Mapping of asset Types to BandOracle symbols
    access(all) let assetSymbols: {Type: String}
    /// StoragePath for the SymbolUpdater tasked with adding Type:SYMBOL pairs
    access(all) let SymbolUpdaterStoragePath: StoragePath

    /* EVENTS */
    /// Emitted when a Type:SYMBOL pair is added via the SymbolUpdater resource
    access(all) event SymbolAdded(symbol: String, asset: String)

    /* CONSTRUCTS */

    // PriceOracle
    //
    /// A connector for BandOracle as an implementation of the DeFiActions PriceOracle interface
    access(all) struct PriceOracle : DeFiActions.PriceOracle {
        /// The token type serving as the price basis - e.g. USD in FLOW/USD
        access(self) let quote: Type
        /// A Source providing the FlowToken necessary for BandOracle price data requests
        access(self) let feeSource: {DeFiActions.Source}
        /// The amount of seconds beyond which a price is considered stale and a price() call reverts
        access(self) let staleThreshold: UInt64?
        /// The unique ID of the PriceOracle
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(unitOfAccount: Type, staleThreshold: UInt64?, feeSource: {DeFiActions.Source}, uniqueID: DeFiActions.UniqueIdentifier?) {
            pre {
                feeSource.getSourceType() == Type<@FlowToken.Vault>():
                "Invalid feeSource - given Source must provide FlowToken Vault, but provides \(feeSource.getSourceType().identifier)"
                unitOfAccount.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Invalid unitOfAccount - \(unitOfAccount.identifier) is not a FungibleToken.Vault implementation"
                BandOracleConnectors.assetSymbols[unitOfAccount] != nil:
                "Could not find a BandOracle symbol assigned to unitOfAccount \(unitOfAccount.identifier)"
            }
            self.feeSource = feeSource
            self.quote = unitOfAccount
            self.staleThreshold = staleThreshold
            self.uniqueID = uniqueID
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the PriceOracle
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                    innerComponents: [
                        self.feeSource.getComponentInfo()
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
        /// Returns the asset type serving as the price basis - e.g. USD in FLOW/USD
        access(all) view fun unitOfAccount(): Type {
            return self.quote
        }
        /// Returns the latest price data for a given asset denominated in unitOfAccount(). Since BandOracle requests
        /// are paid, this implementation reverts if price data has gone stale
        access(all) fun price(ofToken: Type): UFix64? {
            // lookup the symbols
            let baseSymbol = BandOracleConnectors.assetSymbols[ofToken]
                ?? panic("Base asset type \(ofToken.identifier) does not have an assigned symbol")
            let quoteSymbol = BandOracleConnectors.assetSymbols[self.unitOfAccount()]!
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
                BandOracleConnectors.assetSymbols[forAsset] == nil:
                "Asset \(forAsset.identifier) is already assigned symbol \(BandOracleConnectors.assetSymbols[forAsset]!)"
            }
            BandOracleConnectors.assetSymbols[forAsset] = symbol

            emit SymbolAdded(symbol: symbol, asset: forAsset.identifier)
        }
    }

    init() {
        self.assetSymbols = {
            Type<@FlowToken.Vault>(): "FLOW"
        }
        self.SymbolUpdaterStoragePath = StoragePath(identifier: "BandOracleConnectorSymbolUpdater_\(self.account.address)")!
        self.account.storage.save(<-create SymbolUpdater(), to: self.SymbolUpdaterStoragePath)
    }
}
