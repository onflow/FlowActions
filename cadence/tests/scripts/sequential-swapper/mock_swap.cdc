import "FungibleToken"

import "SwapConnectors"
import "MockSwapper"

access(all) fun main(
    vaultHost: Address,
    mockSwapperConfigs: [{String: AnyStruct}],
    amountIn: UFix64
): UFix64 {
    pre {
        mockSwapperConfigs.length > 1: "Provided configs must have a length of at least 3 - provided \(mockSwapperConfigs.length) vaultIdentifiers"
    }
    let acct = getAuthAccount<auth(Storage, Capabilities) &Account>(vaultHost)
    let swappers: [MockSwapper.Swapper] = []
    var inVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}? = nil
    for i, config in mockSwapperConfigs {
        // cast all config data
        let inVaultType = config["inVault"] as! Type
        let outVaultType = config["outVault"] as! Type
        let inVaultPath = config["inVaultPath"] as! StoragePath
        let outVaultPath = config["outVaultPath"] as! StoragePath
        let priceRatio = config["priceRatio"] as! UFix64

        let inVaultCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(inVaultPath)
        let outVaultCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(outVaultPath)

        if i == 0 {
            inVault = inVaultCap.borrow() ?? panic("Invalid inVaultCap for \(inVaultType.identifier)")
        }

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

    // perform swap
    let swapped <- seqSwapper.swap(quote: nil, inVault: <-inVault!.withdraw(amount: amountIn))
    let amountOut = swapped.balance
    destroy swapped

    return amountOut
}