import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "UniswapV3SwapConnectors"
import "DeFiActions"
import "EVMAmountUtils"

/// Runs quoteIn + quoteOut for each test amount and returns structured results.
///
/// Each row in the returned array is:
///   [desiredOut, quoteIn.inAmount, quoteIn.outAmount, quoteOut.inAmount, quoteOut.outAmount]
///
/// Rows where the quoter returned 0 (insufficient liquidity) have all values except
/// desiredOut set to 0.
///
access(all)
fun main(
    signerAddr: Address,
    factoryAddr: String,
    routerAddr: String,
    quoterAddr: String,
    tokenInAddr: String,
    tokenOutAddr: String,
    fee: UInt32,
    testAmounts: [UFix64]
): [[UFix64]] {
    let account = getAuthAccount<auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account>(signerAddr)
    let coaCap = account.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
    assert(coaCap.check(), message: "COA capability is invalid - ensure signer has a COA at /storage/evm")

    let factory = EVM.addressFromString(factoryAddr)
    let router  = EVM.addressFromString(routerAddr)
    let quoter  = EVM.addressFromString(quoterAddr)
    let tokenIn = EVM.addressFromString(tokenInAddr)
    let tokenOut = EVM.addressFromString(tokenOutAddr)

    let inVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenIn)
        ?? panic("Token-in EVM address not associated with a Cadence type via FlowEVMBridgeConfig: \(tokenInAddr)")
    let outVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenOut)
        ?? panic("Token-out EVM address not associated with a Cadence type via FlowEVMBridgeConfig: \(tokenOutAddr)")

    let swapper = UniswapV3SwapConnectors.Swapper(
        factoryAddress: factory,
        routerAddress: router,
        quoterAddress: quoter,
        tokenPath: [tokenIn, tokenOut],
        feePath: [fee],
        inVault: inVaultType,
        outVault: outVaultType,
        coaCapability: coaCap,
        uniqueID: nil
    )

    var results: [[UFix64]] = []

    for desiredOut in testAmounts {
        let quoteIn = swapper.quoteIn(forDesired: desiredOut, reverse: false)

        if quoteIn.inAmount == 0.0 || quoteIn.outAmount == 0.0 {
            results.append([desiredOut, 0.0, 0.0, 0.0, 0.0])
            continue
        }

        let quoteOut = swapper.quoteOut(forProvided: quoteIn.inAmount, reverse: false)

        results.append([
            desiredOut,
            quoteIn.inAmount,
            quoteIn.outAmount,
            quoteOut.inAmount,
            quoteOut.outAmount
        ])
    }

    return results
}
