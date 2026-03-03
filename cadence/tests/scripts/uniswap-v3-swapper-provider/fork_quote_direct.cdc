import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapperProvider"
import "UniswapV3SwapConnectors"
import "DeFiActions"

/// Creates a SwapperProvider with a direct route and returns the quoteOut amount.
/// Used by fork tests against real Uniswap V3 on Flow EVM.
///
access(all) fun main(
    signerAddress: Address,
    factoryHex: String,
    routerHex: String,
    quoterHex: String,
    wflowHex: String,
    wbtcHex: String,
    tokenInType: Type,
    tokenOutType: Type
): UFix64 {
    let account = getAuthAccount<auth(Storage, IssueStorageCapabilityController) &Account>(signerAddress)
    let coaCap = account.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
    assert(coaCap.check(), message: "Invalid COA capability")

    let wflowAddr = EVM.addressFromString(wflowHex)
    let wbtcAddr = EVM.addressFromString(wbtcHex)

    let tokens: [UniswapV3SwapperProvider.TokenConfig] = [
        UniswapV3SwapperProvider.TokenConfig(
            flowType: tokenInType,
            evmAddress: wflowAddr
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: tokenOutType,
            evmAddress: wbtcAddr
        )
    ]

    let routes: [UniswapV3SwapperProvider.RouteConfig] = [
        UniswapV3SwapperProvider.RouteConfig(
            inToken: tokenInType,
            outToken: tokenOutType,
            tokenPath: [wflowAddr, wbtcAddr],
            feePath: [10000]
        )
    ]

    let provider = UniswapV3SwapperProvider.SwapperProvider(
        factoryAddress: EVM.addressFromString(factoryHex),
        routerAddress: EVM.addressFromString(routerHex),
        quoterAddress: EVM.addressFromString(quoterHex),
        tokens: tokens,
        routes: routes,
        coaCapability: coaCap,
        uniqueID: nil,
        intermediaryToken: nil
    )

    let swapper = provider.getSwapper(inType: tokenInType, outType: tokenOutType)
        ?? panic("No swapper found for pair")

    let quote = swapper.quoteOut(forProvided: 1.0, reverse: false)
    return quote.outAmount
}
