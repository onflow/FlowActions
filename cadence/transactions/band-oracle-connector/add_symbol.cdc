import "BandOracleConnectors"

/// Adds the asset Type's symbol designation to the BandOracleConnectors contract making its price available for query
/// via the PriceOracle
///
/// @param symbol: The symbol of the asset type as known by the BandOracle contract
/// @param assetTypeIdentifier: The Type identifier of the asset type - e.g. A.0ae53cb6e3f42a79.FlowToken.Vault
///
transaction(symbol: String, assetTypeIdentifier: String) {
    let assetType: Type
    let updater: &BandOracleConnectors.SymbolUpdater
    prepare(signer: auth(BorrowValue) &Account) {
        self.updater = signer.storage.borrow<&BandOracleConnectors.SymbolUpdater>(from: BandOracleConnectors.SymbolUpdaterStoragePath)
            ?? panic("Could not borrow reference to BandOracleAdapaters.SymbolUpdater from \(BandOracleConnectors.SymbolUpdaterStoragePath)")
        self.assetType = CompositeType(assetTypeIdentifier) ?? panic("Invalid assetTypeIdentifier \(assetTypeIdentifier)")
    }

    execute {
        self.updater.addSymbol(symbol, forAsset: self.assetType)
    }
}
