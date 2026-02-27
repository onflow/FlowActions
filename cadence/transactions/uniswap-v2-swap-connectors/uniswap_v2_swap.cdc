import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV2SwapConnectors"
import "DeFiActions"

/// Generic Uniswap V2 swap transaction
///
/// Accepts Cadence token Types and resolves EVM addresses via FlowEVMBridgeConfig.
/// Currently supports FlowToken as input token (hardcoded vault path).
/// Output token is fully generic - any bridged token Type works.
///
/// @param amount: Amount of input token to swap
/// @param routerAddress: Uniswap V2 Router EVM address (e.g., PunchSwap V2)
/// @param tokenInType: Cadence Type of input token (must be bridged)
/// @param tokenOutType: Cadence Type of output token (must be bridged)
///
transaction(
    amount: UFix64,
    routerAddress: String,
    tokenInType: Type,
    tokenOutType: Type
) {
    let swapper: UniswapV2SwapConnectors.Swapper
    let tokenInVault: @{FungibleToken.Vault}
    let quote: {DeFiActions.Quote}
    var tokenOut: UFix64
    
    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account) {
        self.tokenOut = 0.0
        
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
        assert(coaCap.check(), message: "COA capability is invalid")
        
        let router = EVM.addressFromString(routerAddress)
        
        let tokenInEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenInType)
            ?? panic("Token in type not bridged: \(tokenInType.identifier)")
        let tokenOutEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenOutType)
            ?? panic("Token out type not bridged: \(tokenOutType.identifier)")
        
        self.swapper = UniswapV2SwapConnectors.Swapper(
            routerAddress: router,
            path: [tokenInEVMAddr, tokenOutEVMAddr],
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
        log("Swapped \(amount.toString()) → \(tokenOutVault.balance.toString())")
        destroy tokenOutVault
    }
    
    post {
        self.tokenOut > 0.0:
            "Swap output must be greater than 0"
        self.quote.outAmount == 0.0 || self.tokenOut >= self.quote.outAmount:
            "Swap output (\(self.tokenOut)) must be at least quote amount (\(self.quote.outAmount))"
    }
}

