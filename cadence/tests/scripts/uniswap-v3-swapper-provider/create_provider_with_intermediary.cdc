import "EVM"
import "FlowToken"
import "TokenA"
import "TokenB"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Creates a UniswapV3SwapperProvider with an intermediary token (WFLOW)
/// Only explicit routes are WFLOW<->TokenA and WFLOW<->TokenB.
/// TokenA<->TokenB should be auto-generated via the intermediary.
///
/// @param deployerAddress - Address of account with COA capability
/// @param factoryHex - Uniswap V3 factory address
/// @param routerHex - Uniswap V3 router address
/// @param quoterHex - Uniswap V3 quoter address
/// @param tokenHexes - Array of token EVM addresses [wflow, tokenA, tokenB]
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

    let wflowAddr = EVM.addressFromString(tokenHexes[0])
    let tokenAAddr = EVM.addressFromString(tokenHexes[1])
    let tokenBAddr = EVM.addressFromString(tokenHexes[2])

    // Build token configs
    let tokens: [UniswapV3SwapperProvider.TokenConfig] = [
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@FlowToken.Vault>(),
            evmAddress: wflowAddr
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenA.Vault>(),
            evmAddress: tokenAAddr
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenB.Vault>(),
            evmAddress: tokenBAddr
        )
    ]

    // Only explicit routes: WFLOW<->TokenA and WFLOW<->TokenB
    let routes: [UniswapV3SwapperProvider.RouteConfig] = [
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [wflowAddr, tokenAAddr],
            feePath: [3000]
        ),
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenB.Vault>(),
            tokenPath: [wflowAddr, tokenBAddr],
            feePath: [500]
        )
    ]

    // Intermediary is WFLOW
    let intermediary = UniswapV3SwapperProvider.TokenConfig(
        flowType: Type<@FlowToken.Vault>(),
        evmAddress: wflowAddr
    )

    // Create provider - should auto-generate TokenA<->TokenB routes via WFLOW
    let provider = UniswapV3SwapperProvider.SwapperProvider(
        factoryAddress: EVM.addressFromString(factoryHex),
        routerAddress: EVM.addressFromString(routerHex),
        quoterAddress: EVM.addressFromString(quoterHex),
        tokens: tokens,
        routes: routes,
        coaCapability: coaCap,
        uniqueID: nil,
        intermediaryToken: intermediary
    )

    return true
}
