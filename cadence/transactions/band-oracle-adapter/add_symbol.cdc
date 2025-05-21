import "BandOracleAdapters"

/// Adds the asset Type's symbol designation to the BandOracleAdapters contract making its price available for query
/// via the PriceOracle
///
/// @param symbol: The symbol of the asset type as known by the BandOracle contract
/// @param assetTypeIdentifier: The Type identifier of the asset type - e.g. A.0ae53cb6e3f42a79.FlowToken.Vault
///
transaction(symbol: String, assetTypeIdentifier: String) {
    let assetType: Type
    let updater: &BandOracleAdapters.SymbolUpdater
    prepare(signer: auth(BorrowValue) &Account) {
        self.updater = signer.storage.borrow<&BandOracleAdapters.SymbolUpdater>(from: BandOracleAdapters.SymbolUpdaterStoragePath)
            ?? panic("Could not borrow reference to BandOracleAdapaters.SymbolUpdater from \(BandOracleAdapters.SymbolUpdaterStoragePath)")
        self.assetType = CompositeType(assetTypeIdentifier) ?? panic("Invalid assetTypeIdentifier \(assetTypeIdentifier)")
    }

    execute {
        self.updater.addSymbol(symbol, forAsset: self.assetType)
    }
}
