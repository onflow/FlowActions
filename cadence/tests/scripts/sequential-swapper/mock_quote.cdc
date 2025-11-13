import "FungibleToken"

import "DeFiActions"
import "SwapConnectors"
import "MockSwapper"

access(all) fun main(
    vaultHost: Address,
    mockSwapperConfigs: [{String: AnyStruct}],
    amount: UFix64,
    out: Bool,
    reverse: Bool
): {DeFiActions.Quote} {
    pre {
        mockSwapperConfigs.length > 1: "Provided configs must have a length of at least 3 - provided \(mockSwapperConfigs.length) vaultIdentifiers"
    }
    let acct = getAuthAccount<auth(Storage, Capabilities) &Account>(vaultHost)
    let swappers: [MockSwapper.Swapper] = []
    for i, config in mockSwapperConfigs {
        // cast all config data
        let inVaultType = config["inVault"] as! Type
        let outVaultType = config["outVault"] as! Type
        let inVaultPath = config["inVaultPath"] as! StoragePath
        let outVaultPath = config["outVaultPath"] as! StoragePath
        let priceRatio = config["priceRatio"] as! UFix64

        let inVaultCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(inVaultPath)
        let outVaultCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(outVaultPath)

        swappers.append(MockSwapper.Swapper(
            inVault: inVaultType,
            outVault: outVaultType,
            inVaultSource: inVaultCap,
            outVaultSource: outVaultCap,
            priceRatio: priceRatio,
            uniqueID: nil
        ))
    }
    let seqSwapper = SwapConnectors.SequentialSwapper(swappers: swappers, uniqueID: nil)
    return out
        ? seqSwapper.quoteOut(forProvided: amount, reverse: reverse)
        : seqSwapper.quoteIn(forDesired: amount, reverse: reverse)
}