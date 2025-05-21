import "DFB"
import "IncrementFiAdapters"

access(all)
fun main(forProvided: UFix64, inVaultIdentifier: String, outVaultIdentifier: String, path: [String]): {DFB.Quote} {
    let swapper = IncrementFiAdapters.Swapper(
        path: path,
        inVault: CompositeType(inVaultIdentifier) ?? panic("Invalid inVault \(inVaultIdentifier)"),
        outVault: CompositeType(outVaultIdentifier) ?? panic("Invalid outVault \(outVaultIdentifier)"),
        uniqueID: nil
    )
    return swapper.amountOut(forProvided: forProvided, reverse: false)
}
