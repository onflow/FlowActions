import "FungibleToken"
import "FungibleTokenMetadataViews"
import "SwapConfig"
import "SwapFactory"
import "DeFiActions"
import "IncrementFiPoolLiquidityConnectors"

transaction(
    amountLpToken: UFix64,
    token0Identifier: String,
    token1Identifier: String,
    stableMode: Bool,
) {
    prepare(acct: auth(Capabilities, Storage) &Account) {

        let swapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: CompositeType(token0Identifier) ?? panic("Invalid token0 \(token0Identifier)"),
            token1Type: CompositeType(token1Identifier) ?? panic("Invalid token1 \(token1Identifier)"),
            stableMode: stableMode,
            uniqueID: nil
        )

        let lpTokenCollectionRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &SwapFactory.LpTokenCollection>(from: SwapConfig.LpTokenCollectionStoragePath)
            ?? panic("Cannot borrow reference to LpTokenCollection")
        let inTokens <- lpTokenCollectionRef.withdraw(pairAddr: swapper.pairAddress, amount: amountLpToken)

        let outTokens <- swapper.swapBack(quote: nil, residual: <-inTokens)

        let tokenVaultData = getFTVaultData(vaultIdentifier: token0Identifier)
        let tokenCollection = acct.capabilities.borrow<&{FungibleToken.Receiver}>(tokenVaultData.receiverPath)
            ?? panic("Could not borrow reference to tokenCollection \(tokenVaultData.receiverPath)")
        tokenCollection.deposit(from: <-outTokens)

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
