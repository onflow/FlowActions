import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"

/// Reverse swap (swapBack) via Uniswap V3 multi-hop path.
///
/// Given a swapper configured with tokenPath [A, B, C] (forward: A→B→C),
/// this transaction executes the reverse direction: C→B→A.
///   - tokenPath: [A, B, C] (Cadence Types resolved to EVM addresses)
///   - feePath: [3000, 500] (fee tiers in basis points: 500=0.05%, 3000=0.3%, 10000=1%)
///
/// The tokenPath and feePath arguments define the FORWARD path.
/// The swapper internally reverses them when reverse=true.
///
/// @param amount: Amount of the reverse-input token to swap (the LAST token in tokenPath).
/// @param factoryAddress: Uniswap V3 Factory contract address.
/// @param routerAddress: Uniswap V3 SwapRouter contract address.
/// @param quoterAddress: Uniswap V3 Quoter contract address.
/// @param tokenPath: Ordered array of Cadence Types defining the FORWARD path (same order as forward swap).
/// @param feePath: Fee tiers for each hop (length = tokenPath.length - 1).
/// @param tokenInStoragePath: Storage path for the forward-input vault (first token in forward path).
/// @param tokenOutStoragePath: Storage path for the forward-output vault (last token in forward path).
///
/// Example: If forward path is WBTC→WETH→USDF, this swaps USDF→WETH→WBTC.
///   tokenPath: [WBTC, WETH, USDF]  (same as forward)
///   tokenInStoragePath: USDF vault  (reverse input)
///   tokenOutStoragePath: WBTC vault (reverse output)
///
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
    let tokenOutReceiver: &{FungibleToken.Receiver}
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

        var tokenEVMPath: [EVM.EVMAddress] = []
        for tokenType in tokenPath {
            let tokenEVMAddr = FlowEVMBridgeConfig.getEVMAddressAssociated(with: tokenType)
                ?? panic("Token type not bridged: \(tokenType.identifier)")
            tokenEVMPath.append(tokenEVMAddr)
        }

        // inVault/outVault are defined in FORWARD terms (tokenPath[0] and tokenPath[last])
        // The swapper handles reversal internally via the reverse flag
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

        // Quote in reverse direction: outType (last in forward) is now the input
        self.quote = self.swapper.quoteOut(forProvided: amount, reverse: true)
        log("Quote out (reverse) for provided: \(amount.toString()) -> \(self.quote.outAmount.toString())")

        // Withdraw from the reverse-input vault (last token in forward path)
        self.withdrawRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: tokenOutStoragePath)
            ?? panic("Missing reverse-input vault at \(tokenOutStoragePath.toString())")

        // Deposit into the reverse-output vault (first token in forward path)
        self.tokenOutReceiver = signer.storage.borrow<&{FungibleToken.Receiver}>(from: tokenInStoragePath)
            ?? panic("Missing reverse-output vault at \(tokenInStoragePath.toString())")
    }
        
    pre {
        self.swapper.inType() == self.tokenInType:
            "Invalid swapper inType of \(self.swapper.inType().identifier) - expected \(self.tokenInType.identifier)"
        self.swapper.outType() == self.tokenOutType:
            "Invalid swapper outType of \(self.swapper.outType().identifier) - expected \(self.tokenOutType.identifier)"
    }

    execute {
        let vaultIn <- self.withdrawRef.withdraw(amount: amount)

        // swapBack executes the reverse direction internally
        let tokenOutVault <- self.swapper.swapBack(quote: self.quote, residual: <-vaultIn)
        self.tokenOut = tokenOutVault.balance
        log("SwapBack \(amount.toString()) -> \(self.tokenOut.toString())")

        self.tokenOutReceiver.deposit(from: <-tokenOutVault)
    }

    post {
        self.tokenOut > 0.0:
            "SwapBack output must be greater than 0"
        self.quote.outAmount == 0.0 || self.tokenOut >= self.quote.outAmount:
            "SwapBack output (\(self.tokenOut)) must be at least quote amount (\(self.quote.outAmount))"
    }
}