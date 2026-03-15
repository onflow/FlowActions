import "DeFiActions"
import "IncrementFiSwapConnectors"

access(all)
fun main(
    unitOfAccountIdentifier: String,
    baseTokenIdentifier: String,
    path: [String],
    ofTokenIdentifier: String
): UFix64? {
    let oracle = IncrementFiSwapConnectors.PriceOracle(
        unitOfAccount: CompositeType(unitOfAccountIdentifier) ?? panic("Invalid unitOfAccount \(unitOfAccountIdentifier)"),
        baseToken: CompositeType(baseTokenIdentifier) ?? panic("Invalid baseToken \(baseTokenIdentifier)"),
        path: path,
        uniqueID: nil
    )
    let ofToken = CompositeType(ofTokenIdentifier) ?? panic("Invalid ofToken \(ofTokenIdentifier)")
    return oracle.price(ofToken: ofToken)
}
