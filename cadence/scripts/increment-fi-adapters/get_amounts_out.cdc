import "DeFiActions"
import "IncrementFiConnectors"

access(all)
fun main(forProvided: UFix64, inVaultIdentifier: String, outVaultIdentifier: String, path: [String]): {DeFiActions.Quote} {
    let swapper = IncrementFiConnectors.Swapper(
        path: path,
        inVault: CompositeType(inVaultIdentifier) ?? panic("Invalid inVault \(inVaultIdentifier)"),
        outVault: CompositeType(outVaultIdentifier) ?? panic("Invalid outVault \(outVaultIdentifier)"),
        uniqueID: nil
    )
    let quote = swapper.quoteOut(forProvided: forProvided, reverse: false)
    return quote
}
