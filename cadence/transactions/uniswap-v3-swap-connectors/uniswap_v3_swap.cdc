import "FungibleToken"
import "FungibleTokenMetadataViews"
import "MetadataViews"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"

/// Generic Uniswap V3 swap transaction (exactInput)
///
/// Accepts Cadence token Types and resolves EVM addresses via FlowEVMBridgeConfig.
/// Uses exactInput swap - user provides exact input amount, receives variable output.
///
/// @param amount: Amount of input token to swap
/// @param factoryAddress: Uniswap V3 Factory EVM address
/// @param routerAddress: Uniswap V3 SwapRouter EVM address
/// @param quoterAddress: Uniswap V3 Quoter EVM address
/// @param tokenInType: Cadence Type of input token (must be bridged)
/// @param tokenOutType: Cadence Type of output token (must be bridged)
/// @param fee: Pool fee tier (e.g., 3000 for 0.3%, 500 for 0.05%, 10000 for 1%)
///
transaction(
    amount: UFix64,
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

        self.quote = self.swapper.quoteOut(forProvided: amount, reverse: false)

        self.tokenInVault <- signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/flowTokenVault
        )!.withdraw(amount: amount)

        // set up output token vault if it doesn't exist
        let tokenOutVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
            resourceTypeIdentifier: tokenOutType.identifier,
            viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(tokenOutType.identifier)")

        if signer.storage.type(at: tokenOutVaultData.storagePath) == nil {
            signer.storage.save(<-tokenOutVaultData.createEmptyVault(), to: tokenOutVaultData.storagePath)
            let receiverCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(tokenOutVaultData.storagePath)
            signer.capabilities.unpublish(tokenOutVaultData.receiverPath)
            signer.capabilities.publish(receiverCap, at: tokenOutVaultData.receiverPath)
        }

        self.tokenOutReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(tokenOutVaultData.receiverPath)
            ?? panic("Could not borrow receiver for \(tokenOutType.identifier)")
    }

    pre {
        self.tokenInVault.balance == amount:
            "Invalid token balance of \(self.tokenInVault.balance) - expected \(amount)"
        self.swapper.inType() == self.tokenInVault.getType():
            "Invalid swapper inType of \(self.swapper.inType().identifier) - expected \(self.tokenInVault.getType().identifier)"
        self.swapper.outType() == tokenOutType:
            "Invalid swapper outType of \(self.swapper.outType().identifier) - expected \(tokenOutType.identifier)"
    }

    execute {
        let tokenOutVault <- self.swapper.swap(quote: self.quote, inVault: <-self.tokenInVault)
        self.tokenOut = tokenOutVault.balance
        log("Swapped \(amount) -> \(tokenOutVault.balance)")
        self.tokenOutReceiver.deposit(from: <-tokenOutVault)
    }

    post {
        self.tokenOut > 0.0:
            "Swap output must be greater than 0"
        self.quote.outAmount == 0.0 || self.tokenOut >= self.quote.outAmount * 0.99:
            "Swap output (\(self.tokenOut)) must be at least 99% of quote amount (\(self.quote.outAmount))"
    }
}
