import "IncrementFiAdapters"

access(all)
fun main(amountOut: UFix64, path: [String]): [UFix64] {
    return IncrementFiAdapters.SwapRouterAdapter().getAmountsIn(amountOut: amountOut, path: path)
}
