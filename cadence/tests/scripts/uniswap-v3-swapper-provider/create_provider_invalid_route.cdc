import "EVM"
import "FlowToken"
import "TokenA"
import "TokenB"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Creates a UniswapV3SwapperProvider with an invalid route
/// The route references a token (TokenB) that's not in the configured tokens
/// This should fail during provider initialization
///
access(all) fun main(
    deployerAddress: Address,
    factoryHex: String,
    routerHex: String,
    quoterHex: String,
    tokenHexes: [String],
    unconfiguredTokenType: String
): Bool {
    // Get COA capability
    let account = getAuthAccount<auth(Storage, Capabilities) &Account>(deployerAddress)
    let coaCap = account.capabilities.get<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/public/evm)
        ?? panic("Missing COA capability")

    // Build token configs - only WFLOW and TokenA (NOT TokenB)
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

    // Try to create a route that uses TokenB (which is not configured)
    // This should panic during provider initialization
    let routes: [UniswapV3SwapperProvider.RouteConfig] = [
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenB.Vault>(),  // TokenB is not in tokens config!
            tokenPath: [
                EVM.addressFromString(tokenHexes[0]),
                EVM.addressFromString("0x9999999999999999999999999999999999999999")
            ],
            feePath: [3000]
        )
    ]

    // This should fail with "Route outToken not in configured tokens"
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
