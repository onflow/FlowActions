import "FungibleToken"
import "FungibleTokenMetadataViews"
import "SwapConfig"
import "SwapFactory"
import "DeFiActions"
import "IncrementFiPoolLiquidityConnectors"

transaction(
    amountIn: UFix64,
    token0Identifier: String,
    token1Identifier: String,
    stableMode: Bool,
) {
    prepare(acct: auth(BorrowValue) &Account) {
            let inVaultData = getFTVaultData(vaultIdentifier: token0Identifier)

        let inVault = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(from: inVaultData.storagePath)
            ?? panic("Could not borrow reference to inVault \(inVaultData.storagePath)")

        let inTokens <- inVault.withdraw(amount: amountIn)

        let swapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: CompositeType(token0Identifier) ?? panic("Invalid token0 \(token0Identifier)"),
            token1Type: CompositeType(token1Identifier) ?? panic("Invalid token1 \(token1Identifier)"),
            stableMode: stableMode,
            uniqueID: nil
        )
        let outLPTokens <- swapper.swap(quote: nil, inVault: <-inTokens)

        let lpTokenCollection = acct.storage.borrow<&SwapFactory.LpTokenCollection>(from: SwapConfig.LpTokenCollectionStoragePath)
            ?? panic("Could not borrow reference to LpTokenCollection \(SwapConfig.LpTokenCollectionStoragePath)")
        lpTokenCollection.deposit(pairAddr: swapper.pairAddress, lpTokenVault: <-outLPTokens)

    }

}

access(all) fun getFTVaultData(vaultIdentifier: String): FungibleTokenMetadataViews.FTVaultData {
    let tokenType = CompositeType(vaultIdentifier) ?? panic("Invalid vaultIdentifier \(vaultIdentifier)")
    let contractAddress = tokenType.address ?? panic("Could not derive contract address from vaultIdentifier \(vaultIdentifier)")
    let contractName = tokenType.contractName ?? panic("Could not derive contract name from vaultIdentifier \(vaultIdentifier)")
    let tokenContract = getAccount(contractAddress).contracts.borrow<&{FungibleToken}>(name: contractName)
        ?? panic("Could not borrow Vault's contract \(contractName) from address \(contractAddress) - does not appear to be FungibleToken conformance")
    let vaultData = tokenContract.resolveContractView(resourceType: tokenType, viewType: Type<FungibleTokenMetadataViews.FTVaultData>())
        as! FungibleTokenMetadataViews.FTVaultData?
        ?? panic("Could not resolve FTVaultData for vaultIdentifier \(vaultIdentifier)")
    return vaultData
}
