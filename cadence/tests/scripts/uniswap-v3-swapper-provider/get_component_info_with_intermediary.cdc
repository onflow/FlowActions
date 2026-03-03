import "EVM"
import "FlowToken"
import "TokenA"
import "TokenB"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Creates a provider with intermediary and returns the number of inner components.
/// With 3 tokens (WFLOW, TokenA, TokenB) and WFLOW as intermediary:
/// - Explicit: WFLOW->TokenA, WFLOW->TokenB (2)
/// - Auto-generated: TokenA->TokenB, TokenB->TokenA (2 multi-hop)
/// - Auto-generated reverses: TokenA->WFLOW, TokenB->WFLOW (2 reverses of explicit)
/// Total: 6 swappers
///
access(all) fun main(deployerAddress: Address): Int {
    // Get COA capability
    let account = getAuthAccount<auth(Storage, Capabilities) &Account>(deployerAddress)
    let coaCap = account.capabilities.get<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/public/evm)
        ?? panic("Missing COA capability")

    let wflowAddress = EVM.addressFromString("0x1234567890123456789012345678901234567890")
    let tokenAAddress = EVM.addressFromString("0x2234567890123456789012345678901234567890")
    let tokenBAddress = EVM.addressFromString("0x3234567890123456789012345678901234567890")
    let factoryAddress = EVM.addressFromString("0x4234567890123456789012345678901234567890")
    let routerAddress = EVM.addressFromString("0x5234567890123456789012345678901234567890")
    let quoterAddress = EVM.addressFromString("0x6234567890123456789012345678901234567890")

    let tokens: [UniswapV3SwapperProvider.TokenConfig] = [
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@FlowToken.Vault>(),
            evmAddress: wflowAddress
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenA.Vault>(),
            evmAddress: tokenAAddress
        ),
        UniswapV3SwapperProvider.TokenConfig(
            flowType: Type<@TokenB.Vault>(),
            evmAddress: tokenBAddress
        )
    ]

    // Only explicit routes through WFLOW
    let routes: [UniswapV3SwapperProvider.RouteConfig] = [
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [wflowAddress, tokenAAddress],
            feePath: [3000]
        ),
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenB.Vault>(),
            tokenPath: [wflowAddress, tokenBAddress],
            feePath: [500]
        )
    ]

    let intermediary = UniswapV3SwapperProvider.TokenConfig(
        flowType: Type<@FlowToken.Vault>(),
        evmAddress: wflowAddress
    )

    let provider = UniswapV3SwapperProvider.SwapperProvider(
        factoryAddress: factoryAddress,
        routerAddress: routerAddress,
        quoterAddress: quoterAddress,
        tokens: tokens,
        routes: routes,
        coaCapability: coaCap,
        uniqueID: nil,
        intermediaryToken: intermediary
    )

    let info = provider.getComponentInfo()
    return info.innerComponents.length
}
