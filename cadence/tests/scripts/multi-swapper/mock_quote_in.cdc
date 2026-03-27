import "FungibleToken"

import "DeFiActions"
import "SwapConnectors"
import "MockSwapper"

/// Constructs a MultiSwapper from CapLimitedSwapper instances and calls quoteIn.
///
/// Each config must have:
///   inVault: Type, outVault: Type, inVaultPath: StoragePath, outVaultPath: StoragePath,
///   priceRatio: UFix64, maxOut: UFix64
///
access(all) fun main(
    vaultHost: Address,
    configs: [{String: AnyStruct}],
    inVault: Type,
    outVault: Type,
    forDesired: UFix64,
    reverse: Bool
): SwapConnectors.MultiSwapperQuote {
    pre {
        configs.length >= 1: "Must provide at least one swapper config"
    }
    let acct = getAuthAccount<auth(Storage, Capabilities) &Account>(vaultHost)
    let swappers: [{DeFiActions.Swapper}] = []
    for config in configs {
        let inVaultType  = config["inVault"]     as! Type
        let outVaultType = config["outVault"]    as! Type
        let inVaultPath  = config["inVaultPath"] as! StoragePath
        let outVaultPath = config["outVaultPath"] as! StoragePath
        let priceRatio   = config["priceRatio"]  as! UFix64
        let maxOut       = config["maxOut"]      as! UFix64

        let inCap  = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(inVaultPath)
        let outCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(outVaultPath)

        swappers.append(MockSwapper.CapLimitedSwapper(
            inVault: inVaultType,
            outVault: outVaultType,
            inVaultSource: inCap,
            outVaultSource: outCap,
            priceRatio: priceRatio,
            maxOut: maxOut,
            uniqueID: nil
        ))
    }
    let multiSwapper = SwapConnectors.MultiSwapper(
        inVault: inVault,
        outVault: outVault,
        swappers: swappers,
        uniqueID: nil
    )
    return multiSwapper.quoteIn(forDesired: forDesired, reverse: reverse) as! SwapConnectors.MultiSwapperQuote
}
