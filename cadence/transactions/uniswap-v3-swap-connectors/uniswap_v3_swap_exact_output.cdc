import "FungibleToken"
import "FungibleTokenMetadataViews"
import "MetadataViews"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"
import "SwapConnectors"

/// Uniswap V3 exactOutput swap transaction
///
/// User specifies the exact amount of output tokens desired.
/// The transaction will use up to maxAmountIn of input tokens.
/// Any unused input tokens are returned to the user's vault.
///
/// @param desiredAmountOut: Exact amount of output tokens desired
/// @param maxAmountIn: Maximum amount of input tokens willing to spend
/// @param factoryAddress: Uniswap V3 Factory EVM address
/// @param routerAddress: Uniswap V3 SwapRouter EVM address
/// @param quoterAddress: Uniswap V3 Quoter EVM address
/// @param tokenInType: Cadence Type of input token (must be bridged)
/// @param tokenOutType: Cadence Type of output token (must be bridged)
/// @param fee: Pool fee tier (e.g., 3000 for 0.3%, 500 for 0.05%, 10000 for 1%)
///
transaction(
    desiredAmountOut: UFix64,
    maxAmountIn: UFix64,
    factoryAddress: String,
    routerAddress: String,
    quoterAddress: String,
    tokenInType: Type,
    tokenOutType: Type,
    fee: UInt32
) {
    let swapper: UniswapV3SwapConnectors.Swapper
    let tokenInVault: @{FungibleToken.Vault}
    let tokenInVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let tokenOutReceiver: &{FungibleToken.Receiver}
    let quote: {DeFiActions.Quote}
    var tokenOut: UFix64

    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue, SaveValue, PublishCapability, UnpublishCapability) &Account) {
        self.tokenOut = 0.0

        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
        assert(coaCap.check(), message: "COA capability is invalid")

        let factory = EVM.addressFromString(factoryAddress)
        let router = EVM.addressFromString(routerAddress)
        let quoter = EVM.addressFromString(quoterAddress)

        let tokenInEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenInType)
            ?? panic("Token in type not bridged: ".concat(tokenInType.identifier))
        let tokenOutEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenOutType)
            ?? panic("Token out type not bridged: ".concat(tokenOutType.identifier))

        self.swapper = UniswapV3SwapConnectors.Swapper(
            factoryAddress: factory,
            routerAddress: router,
            quoterAddress: quoter,
            tokenPath: [tokenInEVMAddr, tokenOutEVMAddr],
            feePath: [fee],
            inVault: tokenInType,
            outVault: tokenOutType,
            coaCapability: coaCap,
            uniqueID: nil
        )

        let estimatedQuote = self.swapper.quoteIn(forDesired: desiredAmountOut, reverse: false)

        self.quote = SwapConnectors.BasicQuote(
            inType: tokenInType,
            outType: tokenOutType,
            inAmount: maxAmountIn,
            outAmount: desiredAmountOut
        )

        self.tokenInVaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/flowTokenVault
        )!

        self.tokenInVault <- self.tokenInVaultRef.withdraw(amount: maxAmountIn)

        // set up output token vault if it doesn't exist
        let tokenOutVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
            resourceTypeIdentifier: tokenOutType.identifier,
            viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for ".concat(tokenOutType.identifier))

        if signer.storage.type(at: tokenOutVaultData.storagePath) == nil {
            signer.storage.save(<-tokenOutVaultData.createEmptyVault(), to: tokenOutVaultData.storagePath)
            let receiverCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(tokenOutVaultData.storagePath)
            signer.capabilities.unpublish(tokenOutVaultData.receiverPath)
            signer.capabilities.publish(receiverCap, at: tokenOutVaultData.receiverPath)
        }

        self.tokenOutReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(tokenOutVaultData.receiverPath)
            ?? panic("Could not borrow receiver for ".concat(tokenOutType.identifier))
    }

    pre {
        self.tokenInVault.balance == maxAmountIn:
            "Invalid token balance of \(self.tokenInVault.balance) - expected \(maxAmountIn)"
        self.swapper.inType() == self.tokenInVault.getType():
            "Invalid swapper inType of \(self.swapper.inType().identifier) - expected \(self.tokenInVault.getType().identifier)"
        self.swapper.outType() == tokenOutType:
            "Invalid swapper outType of \(self.swapper.outType().identifier) - expected \(tokenOutType.identifier)"
    }

    execute {
        // swapExactOutput returns array: [0] = output vault, [1] = leftover vault
        let vaults: @[{FungibleToken.Vault}] <- self.swapper.swapExactOutput(quote: self.quote, inVault: <-self.tokenInVault)

        let tokenOutVault <- vaults.remove(at: 0)
        self.tokenOut = tokenOutVault.balance
        log("SwapExactOutput: requested \(desiredAmountOut), received \(tokenOutVault.balance)")

        let leftoverVault <- vaults.remove(at: 0)
        if leftoverVault.balance > 0.0 {
            log("Returning leftover: \(leftoverVault.balance)")
            self.tokenInVaultRef.deposit(from: <- leftoverVault)
        } else {
            destroy leftoverVault
        }

        destroy vaults
        self.tokenOutReceiver.deposit(from: <-tokenOutVault)
    }

    // using ">=" instead of "==" because AMM rounding may result in slightly more tokens than requested
    post {
        self.tokenOut >= desiredAmountOut:
            "Swap output (\(self.tokenOut)) must be at least the desired amount (\(desiredAmountOut))"
    }
}
