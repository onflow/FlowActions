import "EVM"
import "FlowToken"
import "TokenA"
import "UniswapV3SwapperProvider"

/// Attempts to create invalid RouteConfig instances
/// Supported test cases:
/// - "single_token": tokenPath with only 1 token (should fail)
/// - "mismatched_fee_path": feePath length doesn't match tokenPath.length - 1
/// - "self_swap": inToken equals outToken
///
access(all) fun main(testCase: String): Bool {
    let dummyAddress1 = EVM.addressFromString("0x1234567890123456789012345678901234567890")
    let dummyAddress2 = EVM.addressFromString("0x2234567890123456789012345678901234567890")

    if testCase == "single_token" {
        // Should panic: "tokenPath must have at least 2 tokens"
        let routeConfig = UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [dummyAddress1],  // Only 1 token!
            feePath: []
        )
    } else if testCase == "mismatched_fee_path" {
        // Should panic: "feePath length must be tokenPath.length - 1"
        let routeConfig = UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@TokenA.Vault>(),
            tokenPath: [dummyAddress1, dummyAddress2],  // 2 tokens
            feePath: [3000, 500]  // 2 fees instead of 1!
        )
    } else if testCase == "self_swap" {
        // Should panic: "Cannot swap token to itself"
        let routeConfig = UniswapV3SwapperProvider.RouteConfig(
            inToken: Type<@FlowToken.Vault>(),
            outToken: Type<@FlowToken.Vault>(),  // Same as inToken!
            tokenPath: [dummyAddress1, dummyAddress2],
            feePath: [3000]
        )
    }

    return true
}
