import "FungibleToken"
import "FungibleTokenMetadataViews"
import "ViewResolver"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"
import "EVMAmountUtils"

/// Tests actual V3 swap execution with tokenIn provisioning from holder.
///
/// Since forked emulator doesn't verify signatures, we can transfer tokens
/// from any address (like a liquidity pool) to provision tokens for testing.
///
/// Result: [desiredOut, quoteInAmount, quoteOutAmount, vaultBalance, coaDustBefore, coaDustAfter]
///
transaction(
    factoryAddr: String,
    routerAddr: String,
    quoterAddr: String,
    tokenInAddr: String,
    tokenOutAddr: String,
    fee: UInt32,
    provisionAmount: UFix64,
    holderAddr: String,  // Address holding tokens to transfer from
    desiredOut: UFix64
) {
    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue, SaveValue) &Account) {
        // --- Setup ---
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
        let coa = coaCap.borrow()!
        let coaAddr = coa.address()

        let factory = EVM.addressFromString(factoryAddr)
        let router  = EVM.addressFromString(routerAddr)
        let quoter  = EVM.addressFromString(quoterAddr)
        let tokenIn = EVM.addressFromString(tokenInAddr)
        let tokenOut = EVM.addressFromString(tokenOutAddr)

        let inVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenIn)
            ?? panic("tokenIn not in bridge config: \(tokenInAddr)")
        let outVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenOut)
            ?? panic("tokenOut not in bridge config: \(tokenOutAddr)")

        // --- Fee vault (for bridge operations) ---
        let bridgeFee = FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256)
        let feeBalance = EVM.Balance(attoflow: 0)
        feeBalance.setFLOW(flow: 20.0 * bridgeFee)
        let feeVault <- coa.withdraw(balance: feeBalance)
        let feeRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        // --- Provision tokenIn by transferring from holder (only if needed) ---
        // Check if we already have tokenIn in storage from a previous call
        if signer.storage.type(at: /storage/testTokenInVault) == nil && provisionAmount > 0.0 {
            // In forked emulator, signatures aren't verified, so we can call transfer
            let holder = EVM.addressFromString(holderAddr)
            let provisionAmountEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                provisionAmount,
                erc20Address: tokenIn
            )

            log("Transferring \(provisionAmount.toString()) tokens from holder")
            let provisionRes = coa.call(
                to: tokenIn,
                data: EVM.encodeABIWithSignature("transfer(address,uint256)", [coaAddr, provisionAmountEVM]),
                gasLimit: 500_000,
                value: EVM.Balance(attoflow: 0)
            )

            assert(provisionRes.status == EVM.Status.successful,
                message: "Failed to transfer tokenIn from holder: \(provisionRes.errorMessage)")

            log("Transferred \(provisionAmount.toString()) tokenIn to COA")

            // --- Bridge tokenIn from COA to Cadence ---
            let tokenInEVMBalance = FlowEVMBridgeUtils.balanceOf(
                owner: coaAddr, evmContractAddress: tokenIn
            )
            assert(tokenInEVMBalance > 0, message: "No tokenIn balance after transfer")

            let tokenInVault <- coa.withdrawTokens(
                type: inVaultType,
                amount: tokenInEVMBalance,
                feeProvider: feeRef
            )
            log("Bridged \(tokenInVault.balance.toString()) tokenIn to Cadence")

            // Store for subsequent calls
            signer.storage.save(<-tokenInVault, to: /storage/testTokenInVault)
        }

        // Borrow the tokenIn vault (either just created or from previous call)
        let tokenInRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/testTokenInVault
        ) ?? panic("Could not borrow tokenIn vault")

        // --- Create V3 Swapper ---
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

        // --- Run single swap test ---
        let quoteIn = swapper.quoteIn(forDesired: desiredOut, reverse: false)

        // COA output-token ERC20 balance before swap
        let outBefore = FlowEVMBridgeUtils.balanceOf(
            owner: coaAddr, evmContractAddress: tokenOut
        )
        let outBeforeCadence = EVMAmountUtils.toCadenceOutForToken(
            outBefore, erc20Address: tokenOut
        )

        // Check if we can perform the swap
        let canSwap = quoteIn.inAmount > 0.0
            && quoteIn.outAmount > 0.0
            && tokenInRef.balance >= quoteIn.inAmount

        var vaultBalance = 0.0
        var outAfterCadence = outBeforeCadence

        if canSwap {
            // Withdraw exact quoteIn.inAmount and swap
            let inVault <- tokenInRef.withdraw(amount: quoteIn.inAmount)
            let outVault <- swapper.swap(quote: quoteIn, inVault: <-inVault)
            vaultBalance = outVault.balance

            // COA output-token ERC20 balance after swap
            let outAfter = FlowEVMBridgeUtils.balanceOf(
                owner: coaAddr, evmContractAddress: tokenOut
            )
            outAfterCadence = EVMAmountUtils.toCadenceOutForToken(
                outAfter, erc20Address: tokenOut
            )

            destroy outVault
        }

        let result = [
            desiredOut,
            quoteIn.inAmount,
            quoteIn.outAmount,
            vaultBalance,
            outBeforeCadence,
            outAfterCadence
        ]

        // --- Store result for the test to read ---
        let _ = signer.storage.load<[UFix64]>(from: /storage/swapDustResult)
        signer.storage.save(result, to: /storage/swapDustResult)

        // --- Cleanup ---
        if feeVault.balance > 0.0 {
            coa.deposit(from: <-feeVault)
        } else {
            destroy feeVault
        }
    }
}
