import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"

/// Uniswap V3 uses packed path encoding: token(20 bytes) | fee(3 bytes) | token(20 bytes) | ...
///
/// For a swap A → B → C with fees [3000, 500]:
///   - tokenPath: [A, B, C] (Cadence Types resolved to EVM addresses)
///   - feePath: [3000, 500] (fee tiers in basis points: 500=0.05%, 3000=0.3%, 10000=1%)
///
/// @param amount: Amount of input token to swap (in Cadence decimal format).
/// @param factoryAddress: Uniswap V3 Factory contract address (e.g., "0x..." for PunchSwap V3). Used to resolve pool addresses for each hop.
/// @param routerAddress: Uniswap V3 SwapRouter contract address. Executes the actual swap via exactInput().
/// @param quoterAddress: Uniswap V3 Quoter contract address. Used for quoteExactInput/quoteExactOutput calls.
/// @param tokenPath:
///     Ordered array of Cadence FungibleToken Types defining the swap path
///     - First element: input token type
///     - Last element: output token type
///     - All tokens must be bridged (have EVM address association)
///     - Minimum 2 tokens required
/// @param feePath: Fee tiers for each hop in the path (length = tokenPath.length - 1).
/// @param tokenInStoragePath: Storage path for the input token vault (e.g., /storage/flowTokenVault).
/// @param tokenOutStoragePath: Storage path for the output token vault. Must already exist - transaction does not create vaults.
/// ## Example Usage
///
/// Swap 100 FLOW → USDC via FLOW/WETH/USDC path:
/// ```
/// flow transactions send uniswap_v3_swap.cdc \
///   100.0 \
///   "0xFactory..." \
///   "0xRouter..." \
///   "0xQuoter..." \
///   '[Type<@FlowToken.Vault>(), Type<@WETH.Vault>(), Type<@USDC.Vault>()]' \
///   '[3000, 500]' \
///   /storage/flowTokenVault \
///   /storage/usdcVault
/// ```
/// Requirements
/// - Signer must have a CadenceOwnedAccount (COA) at /storage/evm
/// - Input vault must have sufficient balance
/// - Output vault must exist at specified path
/// - All tokens in path must be bridged to Flow EVM
/// - Sufficient FLOW for bridge fees for every round-trip
///
/// Post-Conditions
///
/// - Output amount must be > 0
/// - Output amount must be >= quoted amount (protects against excessive slippage)
transaction(
    amount: UFix64,
    factoryAddress: String,
    routerAddress: String,
    quoterAddress: String,
    tokenPath: [Type],
    feePath: [UInt32],
    tokenInStoragePath: StoragePath,
    tokenOutStoragePath: StoragePath
) {
    let swapper: UniswapV3SwapConnectors.Swapper
    let withdrawRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let tokenOutReceiver : &{FungibleToken.Receiver}
    let quote: {DeFiActions.Quote}
    var tokenOut: UFix64
    var tokenInType: Type
    var tokenOutType: Type
    
    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account) {
        self.tokenOut = 0.0
        
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
        assert(coaCap.check(), message: "COA capability is invalid")
        
        let router = EVM.addressFromString(routerAddress)
        let factory = EVM.addressFromString(factoryAddress)
        let quoter = EVM.addressFromString(quoterAddress)

        var tokenEVMPath: [EVM.EVMAddress]= []
        for tokenType in tokenPath {
            let tokenInEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenType) ?? 
                                                 panic("Token in type not bridged: \(tokenType.identifier)")
            tokenEVMPath.append(tokenInEVMAddr)   
        }
        
        self.tokenInType = tokenPath[0]
        self.tokenOutType = tokenPath[tokenPath.length - 1]
        self.swapper = UniswapV3SwapConnectors.Swapper(
            factoryAddress: factory,
            routerAddress: router,
            quoterAddress: quoter,
            tokenPath: tokenEVMPath,
            feePath: feePath,
            inVault: self.tokenInType,
            outVault: self.tokenOutType,
            coaCapability: coaCap,
            uniqueID: nil
        )
        
        self.quote = self.swapper.quoteOut(forProvided: amount, reverse: false)
        log("Quote out for provided: \(amount.toString()) TokenIn -> TokenOut: \(self.quote.outAmount.toString())")

        // Get withdraw ref
        self.withdrawRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: tokenInStoragePath)
        ?? panic("Missing TokenIn vault at \(tokenInStoragePath.toString())")

        // Get receiver ref
        self.tokenOutReceiver = signer.storage.borrow<&{FungibleToken.Receiver}>(from: tokenOutStoragePath)
        ?? panic("Missing TokenOut vault at \(tokenOutStoragePath.toString())")
    }
    
    pre {
        self.swapper.inType() == self.tokenInType:
            "Invalid swapper inType of \(self.swapper.inType().identifier) - expected \(self.tokenInType.identifier)"
        self.swapper.outType() == self.tokenOutType:
            "Invalid swapper outType of \(self.swapper.outType().identifier) - expected \(self.tokenOutType.identifier)"
    }
    
    execute {
        // Withdraw
        let vaultIn <- self.withdrawRef.withdraw(amount: amount)
               
        // Perform the swap
        let tokenOutVault <- self.swapper.swap(quote: self.quote, inVault: <-vaultIn)
        self.tokenOut = tokenOutVault.balance
        log("Swapped \(amount.toString()) -> \(self.tokenOut.toString()))")
        
        // Deposit
        self.tokenOutReceiver.deposit(from: <-tokenOutVault)
    }
    
    post {
        self.tokenOut > 0.0:
            "Swap output must be greater than 0"
        self.quote.outAmount == 0.0 || self.tokenOut >= self.quote.outAmount:
            "Swap output (\(self.tokenOut)) must be at least quote amount (\(self.quote.outAmount))"
    }
}

