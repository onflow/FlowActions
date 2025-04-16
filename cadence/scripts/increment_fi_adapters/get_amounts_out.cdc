import "IncrementFiAdapters"

access(all)
fun main(amountIn: UFix64, path: [String]): [UFix64] {
    return IncrementFiAdapters.SwapRouterAdapter().getAmountsOut(amountIn: amountIn, path: path)
}
