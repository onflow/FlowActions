import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"

/// Generic Uniswap V3 swap transaction
///
/// Accepts Cadence token Types and resolves EVM addresses via FlowEVMBridgeConfig.
/// Currently supports FlowToken as input token (hardcoded vault path).
/// Output token is fully generic - any bridged token Type works.
///
/// @param amount: Amount of input token to swap
/// @param factoryAddress: Uniswap V3 Factory EVM address
/// @param routerAddress: Uniswap V3 SwapRouter02 EVM address
/// @param quoterAddress: Uniswap V3 QuoterV2 EVM address
/// @param tokenInType: Cadence Type of input token (must be bridged)
/// @param tokenOutType: Cadence Type of output token (must be bridged)
/// @param feeTier: Fee tier in basis points (e.g. 500, 3000, 10000)
///
transaction(
    amount: UFix64,
    factoryAddress: String,
    routerAddress: String,
    quoterAddress: String,
    tokenInType: Type,
    tokenOutType: Type,
    feeTier: UInt32
) {
    let swapper: UniswapV3SwapConnectors.Swapper
    let tokenInVault: @{FungibleToken.Vault}
    let quote: {DeFiActions.Quote}
    var tokenOut: UFix64

    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account) {
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
            feePath: [feeTier],
            inVault: tokenInType,
            outVault: tokenOutType,
            coaCapability: coaCap,
            uniqueID: nil
        )

        self.quote = self.swapper.quoteOut(forProvided: amount, reverse: false)

        self.tokenInVault <- signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/flowTokenVault
        )!.withdraw(amount: amount)
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
        log("Swapped ".concat(amount.toString()).concat(" → ").concat(tokenOutVault.balance.toString()))
        destroy tokenOutVault
    }

    post {
        self.tokenOut > 0.0:
            "Swap output must be greater than 0"
        self.quote.outAmount == 0.0 || self.tokenOut >= self.quote.outAmount:
            "Swap output (\(self.tokenOut)) must be at least quote amount (\(self.quote.outAmount))"
    }
}
