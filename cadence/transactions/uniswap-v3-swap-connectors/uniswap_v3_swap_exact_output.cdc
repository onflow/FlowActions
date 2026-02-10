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

        let tokenInVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
            resourceTypeIdentifier: tokenInType.identifier,
            viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for ".concat(tokenInType.identifier))

        let tokenInReceiverCap = signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(tokenInVaultData.storagePath)
        assert(tokenInReceiverCap.check(), message: "Could not issue token-in receiver capability")

        self.quote = SwapConnectors.asExactOutQuote(
            quote: SwapConnectors.BasicQuote(
                inType: tokenInType,
                outType: tokenOutType,
                inAmount: maxAmountIn,
                outAmount: desiredAmountOut
            ),
            leftoverInReceiver: tokenInReceiverCap
        )

        let tokenInVaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: tokenInVaultData.storagePath
        )!

        self.tokenInVault <- tokenInVaultRef.withdraw(amount: maxAmountIn)

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
        // exact-out is requested through ModeQuote, while keeping swap() as the call entrypoint
        let tokenOutVault <- self.swapper.swap(quote: self.quote, inVault: <-self.tokenInVault)
        self.tokenOut = tokenOutVault.balance
        log("SwapExactOutput via swap(): requested \(desiredAmountOut), received \(tokenOutVault.balance)")
        self.tokenOutReceiver.deposit(from: <-tokenOutVault)
    }

    // using ">=" instead of "==" because AMM rounding may result in slightly more tokens than requested
    post {
        self.tokenOut >= desiredAmountOut:
            "Swap output (\(self.tokenOut)) must be at least the desired amount (\(desiredAmountOut))"
    }
}
