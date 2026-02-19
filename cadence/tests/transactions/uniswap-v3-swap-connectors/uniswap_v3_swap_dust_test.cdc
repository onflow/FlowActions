import "FungibleToken"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"
import "DeFiActions"
import "EVMAmountUtils"

/// Tests actual V3 swap execution and records metrics for dust verification.
///
/// Provisions tokenIn by bridging FlowToken -> WFLOW and swapping WFLOW -> tokenIn
/// via PunchSwap V2 router on first call, then runs a single V3 swap test.
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
    v2RouterAddr: String,
    provisionFlowAmount: UFix64,
    desiredOut: UFix64
) {
    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account) {
        // --- Setup ---
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
        let coa = coaCap.borrow()!
        let coaAddr = coa.address()

        let factory = EVM.addressFromString(factoryAddr)
        let router  = EVM.addressFromString(routerAddr)
        let quoter  = EVM.addressFromString(quoterAddr)
        let tokenIn = EVM.addressFromString(tokenInAddr)
        let tokenOut = EVM.addressFromString(tokenOutAddr)
        let v2Router = EVM.addressFromString(v2RouterAddr)

        let wflow = FlowEVMBridgeConfig.getEVMAddressAssociated(with: Type<@FlowToken.Vault>())
            ?? panic("WFLOW not in bridge config")
        let inVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenIn)
            ?? panic("tokenIn not in bridge config: ".concat(tokenInAddr))
        let outVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: tokenOut)
            ?? panic("tokenOut not in bridge config: ".concat(tokenOutAddr))

        // --- Fee vault (for bridge operations outside swap) ---
        let bridgeFee = FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256)
        let feeBalance = EVM.Balance(attoflow: 0)
        feeBalance.setFLOW(flow: 20.0 * bridgeFee)
        let feeVault <- coa.withdraw(balance: feeBalance)
        let feeRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        // --- Provision tokenIn via PunchSwap V2 (only if needed) ---
        // Check if we already have tokenIn in storage from a previous call
        if signer.storage.type(at: /storage/testTokenInVault) == nil && provisionFlowAmount > 0.0 {
            // Bridge FlowToken -> WFLOW on EVM
            let flowVault <- signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            )!.withdraw(amount: provisionFlowAmount)
            let wflowAmount = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                provisionFlowAmount, erc20Address: wflow
            )
            coa.depositTokens(vault: <-flowVault, feeProvider: feeRef)

            // Approve V2 Router for WFLOW
            var callRes = coa.call(
                to: wflow,
                data: EVM.encodeABIWithSignature("approve(address,uint256)", [v2Router, wflowAmount]),
                gasLimit: 100_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(callRes.status == EVM.Status.successful, message: "WFLOW approve for V2 failed")

            // Swap WFLOW -> tokenIn via V2 swapExactTokensForTokens
            let v2Path: [EVM.EVMAddress] = [wflow, tokenIn]
            callRes = coa.call(
                to: v2Router,
                data: EVM.encodeABIWithSignature(
                    "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                    [wflowAmount, UInt256(0), v2Path, coaAddr, UInt256(99999999999)]
                ),
                gasLimit: 1_000_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(callRes.status == EVM.Status.successful,
                message: "V2 provision swap failed: ".concat(callRes.errorMessage))

            // Bridge all tokenIn from COA -> Cadence
            let tokenInEVMBalance = FlowEVMBridgeUtils.balanceOf(
                owner: coaAddr, evmContractAddress: tokenIn
            )
            assert(tokenInEVMBalance > UInt256(0), message: "No tokenIn received from V2 swap")

            let tokenInVault <- coa.withdrawTokens(
                type: inVaultType,
                amount: tokenInEVMBalance,
                feeProvider: feeRef
            )
            log("Provisioned ".concat(tokenInVault.balance.toString()).concat(" tokenIn"))

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

        var vaultBalance: UFix64 = 0.0
        var outAfterCadence: UFix64 = outBeforeCadence

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

        let result: [UFix64] = [
            desiredOut,
            quoteIn.inAmount,
            quoteIn.outAmount,
            vaultBalance,
            outBeforeCadence,
            outAfterCadence
        ]

        // --- Store result for the test to read ---
        signer.storage.load<[UFix64]>(from: /storage/swapDustResult)
        signer.storage.save(result, to: /storage/swapDustResult)

        // --- Cleanup ---
        if feeVault.balance > 0.0 {
            coa.deposit(from: <-feeVault)
        } else {
            destroy feeVault
        }
    }
}
