import "EVM"
import "FlowToken"
import "TokenA"
import "TokenB"
import "UniswapV3SwapperProvider"
import "DeFiActions"

/// Tests getComponentInfo() functionality
/// Returns the number of inner components in the provider
///
access(all) fun main(deployerAddress: Address): Int {
    // Get COA capability
    let account = getAuthAccount<auth(Storage, Capabilities) &Account>(deployerAddress)
    let coaCap = account.capabilities.get<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/public/evm)
        ?? panic("Missing COA capability")

    // Create dummy addresses for testing
    let wflowAddress = EVM.addressFromString("0x1234567890123456789012345678901234567890")
    let tokenAAddress = EVM.addressFromString("0x2234567890123456789012345678901234567890")
    let tokenBAddress = EVM.addressFromString("0x3234567890123456789012345678901234567890")
    let factoryAddress = EVM.addressFromString("0x4234567890123456789012345678901234567890")
    let routerAddress = EVM.addressFromString("0x5234567890123456789012345678901234567890")
    let quoterAddress = EVM.addressFromString("0x6234567890123456789012345678901234567890")

    // Create a provider with 3 routes
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
            feePath: [3000]
        ),
        UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@TokenA.Vault>(),
            outToken: Type<@TokenB.Vault>(),
            tokenPath: [tokenAAddress, tokenBAddress],
            feePath: [500]
        )
    ]

    let provider = UniswapV3SwapperProvider.SwapperProvider(
        factoryAddress: factoryAddress,
        routerAddress: routerAddress,
        quoterAddress: quoterAddress,
        tokens: tokens,
        routes: routes,
        coaCapability: coaCap,
        uniqueID: nil
    )

    // Get component info
    let info = provider.getComponentInfo()

    // Return the number of inner components
    return info.innerComponents.length
}
