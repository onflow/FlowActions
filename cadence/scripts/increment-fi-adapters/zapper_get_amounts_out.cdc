import "DeFiActions"
import "IncrementFiPoolLiquidityConnectors"

access(all)
fun main(forProvided: UFix64, inVaultIdentifier: String, outVaultIdentifier: String): {DeFiActions.Quote} {
    let swapper = IncrementFiPoolLiquidityConnectors.Zapper(
        token0Type: CompositeType(inVaultIdentifier) ?? panic("Invalid inVault \(inVaultIdentifier)"),
        token1Type: CompositeType(outVaultIdentifier) ?? panic("Invalid outVault \(outVaultIdentifier)"),
        stableMode: true,
        uniqueID: nil
    )
    return swapper.quoteOut(forProvided: forProvided, reverse: false)
}
