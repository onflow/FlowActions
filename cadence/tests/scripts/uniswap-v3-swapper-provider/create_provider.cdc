import "EVM"
import "FlowToken"
import "TokenA"
import "TokenB"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Creates a UniswapV3SwapperProvider with specified tokens and routes
///
/// @param deployerAddress - Address of account with COA capability
/// @param factoryHex - Uniswap V3 factory address
/// @param routerHex - Uniswap V3 router address
/// @param quoterHex - Uniswap V3 quoter address
/// @param tokenHexes - Array of token EVM addresses [wflow, tokenA, tokenB, ...]
/// @param numRoutes - Number of routes to create (3 = WFLOW<->TokenA, WFLOW<->TokenB, TokenA<->TokenB)
///
access(all) fun main(
    deployerAddress: Address,
    factoryHex: String,
    routerHex: String,
    quoterHex: String,
    tokenHexes: [String],
    numRoutes: Int
): Bool {
    // Get COA capability
    let account = getAuthAccount<auth(Storage, Capabilities) &Account>(deployerAddress)
    let coaCap = account.capabilities.get<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/public/evm)
        ?? panic("Missing COA capability")

    // Build token configs
    let tokens: [UniswapV3SwapperProvider.TokenConfig] = []

    // WFLOW
    if tokenHexes.length > 0 {
        tokens.append(UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@FlowToken.Vault>(),
            evmAddress: EVM.addressFromString(tokenHexes[0])
        ))
    }

    // TokenA
    if tokenHexes.length > 1 {
        tokens.append(UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenA.Vault>(),
            evmAddress: EVM.addressFromString(tokenHexes[1])
        ))
    }

    // TokenB
    if tokenHexes.length > 2 {
        tokens.append(UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenB.Vault>(),
            evmAddress: EVM.addressFromString(tokenHexes[2])
        ))
    }

    // Build route configs based on numRoutes
    let routes: [UniswapV3SwapperProvider.RouteConfig] = []

    if numRoutes >= 1 && tokenHexes.length >= 2 {
        // Route 1: WFLOW -> TokenA
        routes.append(UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [EVM.addressFromString(tokenHexes[0]), EVM.addressFromString(tokenHexes[1])],
            feePath: [3000]
        ))
    }

    if numRoutes >= 2 && tokenHexes.length >= 3 {
        // Route 2: WFLOW -> TokenB
        routes.append(UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenB.Vault>(),
            tokenPath: [EVM.addressFromString(tokenHexes[0]), EVM.addressFromString(tokenHexes[2])],
            feePath: [3000]
        ))
    }

    if numRoutes >= 3 && tokenHexes.length >= 3 {
        // Route 3: TokenA -> TokenB
        routes.append(UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@TokenA.Vault>(),
            outToken: Type<@TokenB.Vault>(),
            tokenPath: [EVM.addressFromString(tokenHexes[1]), EVM.addressFromString(tokenHexes[2])],
            feePath: [500]
        ))
    }

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
