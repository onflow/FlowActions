import "DeFiActions"
import "IncrementFiPoolLiquidityConnectors"

access(all)
fun main(
    forProvided: UFix64,
    inVaultIdentifier: String,
    outVaultIdentifier: String,
    stableMode: Bool,
    reverse: Bool,
): {DeFiActions.Quote} {
    let swapper = IncrementFiPoolLiquidityConnectors.Zapper(
        token0Type: CompositeType(inVaultIdentifier) ?? panic("Invalid inVault \(inVaultIdentifier)"),
        token1Type: CompositeType(outVaultIdentifier) ?? panic("Invalid outVault \(outVaultIdentifier)"),
        stableMode: stableMode,
        uniqueID: nil
    )
    return swapper.quoteOut(forProvided: forProvided, reverse: reverse)
}
