import "EVM"
import "FlowToken"
import "TokenA"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Creates a UniswapV3SwapperProvider with only WFLOW <-> TokenA routes
/// Used for testing unconfigured pair scenarios
///
access(all) fun main(
    deployerAddress: Address,
    factoryHex: String,
    routerHex: String,
    quoterHex: String,
    tokenHexes: [String]
): Bool {
    // Get COA capability
    let account = getAuthAccount<auth(Storage, Capabilities) &Account>(deployerAddress)
    let coaCap = account.capabilities.get<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/public/evm)
        ?? panic("Missing COA capability")

    // Build token configs - only WFLOW and TokenA
    let tokens: [UniswapV3SwapperProvider.TokenConfig] = [
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@FlowToken.Vault>(),
            evmAddress: EVM.addressFromString(tokenHexes[0])
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenA.Vault>(),
            evmAddress: EVM.addressFromString(tokenHexes[1])
        )
    ]

    // Build route configs - only WFLOW -> TokenA
    let routes: [UniswapV3SwapperProvider.RouteConfig] = [
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [EVM.addressFromString(tokenHexes[0]), EVM.addressFromString(tokenHexes[1])],
            feePath: [3000]
        )
    ]

    // Create provider
    let provider = UniswapV3SwapperProvider.SwapperProvider(
        factoryAddress: EVM.addressFromString(factoryHex),
        routerAddress: EVM.addressFromString(routerHex),
        quoterAddress: EVM.addressFromString(quoterHex),
        tokens: tokens,
        routes: routes,
        coaCapability: coaCap,
        uniqueID: nil
    )

    return true
}
