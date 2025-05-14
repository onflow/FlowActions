import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "FlowEVMBridge"

import "DFB"
import "SwapStack"

/// DeFiBlocksEVMAdapters
///
/// DeFi adapter implementations fitting EVM-based DeFi protocols to the interfaces defined in DFB. These
/// adapters are originally intended for use in DeFiBlocks components, but may have broader use cases.
///
access(all) contract DeFiBlocksEVMAdapters {

    /// Adapts an EVM-based UniswapV2Router contract methods to DeFiAdapters.UniswapV2SwapAdapter struct interface
    ///
    access(all) struct UniswapV2EVMSwapper : DFB.Swapper {
        /// UniswapV2Router contract's EVM address
        access(all) let routerAddress: EVM.EVMAddress
        /// A swap path defining the route followed for facilitated swaps
        access(all) let path: [EVM.EVMAddress]
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: {DFB.UniqueIdentifier}?
        /// The pre-conversion currency accepted for a swap
        access(self) let inVault: Type
        /// The post-conversion currency returned by a swap
        access(self) let outVault: Type
        /// An authorized Capability on the CadenceOwnedAccount which this Swapper executes swaps on behalf of
        access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

        init(
            routerAddress: EVM.EVMAddress,
            path: [EVM.EVMAddress],
            inVault: Type,
            outVault: Type,
            coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
            uniqueID: {DFB.UniqueIdentifier}?
        ) {
            pre {
                path.length >= 2: "Provided path with length of \(path.length) - path must contain at least two EVM addresses)"
                FlowEVMBridgeConfig.getTypeAssociated(with: path[0]) == inVault:
                "Provided inVault \(inVault.identifier) is not associated with ERC20 at path[0] \(path[0].toString()) - "
                    .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
                FlowEVMBridgeConfig.getTypeAssociated(with: path[path.length - 1]) == outVault: 
                "Provided outVault \(outVault.identifier) is not associated with ERC20 at path[\(path.length - 1)] \(path[path.length - 1].toString()) - "
                    .concat("Ensure the type & ERC20 contracts are associated via the VM bridge")
                coaCapability.check():
                "Provided COA Capability is invalid - provided an active, unrevoked Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>"
            }
            self.routerAddress = routerAddress
            self.path = path
            self.uniqueID = uniqueID
            self.inVault = inVault
            self.outVault = outVault
            self.coaCapability = coaCapability
        }

        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inVaultType(): Type {
            return self.inVault
        }

        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outVaultType(): Type {
            return self.outVault
        }

        /// The estimated amount required to provide a Vault with the desired output balance returned as a BasicQuote
        /// struct containing the in and out Vault types and quoted in and out amounts
        /// NOTE: Cadence only supports decimal precision of 8
        access(all) fun amountIn(forDesired: UFix64, reverse: Bool): {DFB.Quote} {
            let amounts = self.getAmounts(out: false, amount: forDesired, path: reverse ? self.path.reverse() : self.path)
            return SwapStack.BasicQuote(
                inVault: reverse ? self.outVaultType() : self.inVaultType(),
                outVault: reverse ? self.inVaultType() : self.outVaultType(),
                inAmount: amounts.length > 0 ? amounts[0] : 0.0,
                outAmount: amounts.length > 0 ? forDesired : 0.0
            )
        }
        /// The estimated amount delivered out for a provided input balance returned as a BasicQuote returned as a
        /// BasicQuote struct containing the in and out Vault types and quoted in and out amounts
        /// NOTE: Cadence only supports decimal precision of 8
        access(all) fun amountOut(forProvided: UFix64, reverse: Bool): {DFB.Quote} {
            let amounts = self.getAmounts(out: true, amount: forProvided, path: reverse ? self.path.reverse() : self.path)
            return SwapStack.BasicQuote(
                inVault: reverse ? self.outVaultType() : self.inVaultType(),
                outVault: reverse ? self.inVaultType() : self.outVaultType(),
                inAmount: amounts.length > 0 ? forProvided : 0.0,
                outAmount: amounts.length > 0 ? amounts[amounts.length - 1] : 0.0
            )
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. This implementation swaps
        /// along a path defined on init routing the swap to the pre-defined UniswapV2Router implementation on Flow EVM.
        /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
        /// used.
        /// NOTE: Cadence only supports decimal precision of 8
        access(all) fun swap(quote: {DFB.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOutMin = quote?.outAmount ?? self.amountOut(forProvided: inVault.balance, reverse: true).outAmount
            return <-self.swapExactTokensForTokens(exactVaultIn: <-inVault, amountOutMin: amountOutMin, reverse: false)
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
        /// used.
        /// NOTE: Cadence only supports decimal precision of 8
        access(all) fun swapBack(quote: {DFB.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOutMin = quote?.outAmount ?? self.amountOut(forProvided: residual.balance, reverse: true).outAmount
            return <-self.swapExactTokensForTokens(
                exactVaultIn: <-residual,
                amountOutMin: amountOutMin,
                reverse: true
            )
        }

        /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
        /// returning the final output Vault
        ///
        /// @param exactVaultIn: The exact balance to swap as pre-converted currency
        /// @param amountOutMin: The minimum output balance expected as post-converted currency, useful for slippage
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        /// @param deadline: The block timestamp beyond which the swap should not execute
        ///
        /// @return The requested post-conversion currency
        ///
        access(self) fun swapExactTokensForTokens(
            exactVaultIn: @{FungibleToken.Vault},
            amountOutMin: UFix64,
            reverse: Bool
        ): @{FungibleToken.Vault} {
            let id = self.uniqueID?.id?.toString() ?? "UNASSIGNED"
            let idType = self.uniqueID?.getType()?.identifier ?? "UNASSIGNED"
            let coa = self.borrowCOA()
                ?? panic("The COA Capability contained by Swapper \(self.getType().identifier) with UniqueIdentifier "
                    .concat("\(idType) ID \(id) is invalid - cannot perform an EVM swap without a valid COA Capability"))

            // withdraw FLOW from the COA to cover the VM bridge fee
            let bridgeFeeBalance = EVM.Balance(attoflow: 0)
            bridgeFeeBalance.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 128)) // bridging to EVM then from EVM, hence factor of 2
            let feeVault <- coa.withdraw(balance: bridgeFeeBalance)
            let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

            // bridge the provided to the COA's EVM address
            let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                exactVaultIn.balance,
                erc20Address: reverse ? self.path[self.path.length - 1] : self.path[0]
            )
            coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeVaultRef)

            // perform the swap
            let res = self.call(
                signature: "swapExactTokensForTokens(uint,uint,address[],address,uint)", // amountIn, amountOutMin, path, to, deadline (timestamp)
                args: [evmAmountIn, UInt256(0), (reverse ? self.path.reverse() : self.path), coa.address(), UInt256(getCurrentBlock().timestamp)],
                gasLimit: 15_000_000,
                value: 0,
                dryCall: false
            )!
            // Resolve if the call was unsuccessful
            if res.status != EVM.Status.successful {
                // revert because the funds have already been deposited to the COA - a no-op would leave the funds in EVM
                panic("Call to \(self.routerAddress.toString()).swapExactTokensForTokens from Swapper \(self.getType().identifier) "
                    .concat("with UniqueIdentifier \(idType) ID \(id) failed: \n\t"
                    .concat("Status value: \(res.status.rawValue)\n\t"))
                    .concat("Error code: \(res.errorCode)\n\t")
                    .concat("ErrorMessage: \(res.errorMessage)\n"))
            }
            let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)
            let amountsOut = decoded[0] as! [UInt256]
            // withdraw tokens from EVM
            let outVault <- coa.withdrawTokens(type: self.outVaultType(), amount: amountsOut[amountsOut.length - 1], feeProvider: feeVaultRef)

            // clean up the remaining feeVault & return the swapped out Vault
            self.handleRemainingFeeVault(<-feeVault)
            return <- outVault
        }

        access(self) fun getAmounts(out: Bool, amount: UFix64, path: [EVM.EVMAddress]): [UFix64] {
            let callRes = self.call(
                signature: out ? "getAmountsOut(uint,address[])" : "getAmountsIn(uint,address[])",
                args: [amount],
                gasLimit: 5_000_000,
                value: UInt(0),
                dryCall: true
            )
            if callRes == nil || callRes!.status != EVM.Status.successful {
                return []
            }
            let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: callRes!.data) // can revert if the type cannot be decoded
            return decoded.length > 0 ? DeFiBlocksEVMAdapters.convertEVMAmountsToCadenceAmounts(decoded[0] as! [UInt256], path: path) : []
        }

        access(self) fun handleRemainingFeeVault(_ vault: @FlowToken.Vault) {
            if vault.balance > 0.0 {
                self.borrowCOA()!.deposit(from: <-vault)
            } else {
                Burner.burn(<-vault)
            }
        }

        access(self) view fun borrowCOA(): auth(EVM.Owner) &EVM.CadenceOwnedAccount? {
            return self.coaCapability.borrow()
        }

        access(self) fun call(
            signature: String,
            args: [AnyStruct],
            gasLimit: UInt64,
            value: UInt,
            dryCall: Bool
        ): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: value)
            if let coa = self.borrowCOA() {
                let res: EVM.Result = dryCall
                    ? coa.dryCall(to: self.routerAddress, data: calldata, gasLimit: gasLimit, value: valueBalance)
                    : coa.call(to: self.routerAddress, data: calldata, gasLimit: gasLimit, value: valueBalance)
                return res
            }
            return nil
        }
    }

    access(self)
    fun convertEVMAmountsToCadenceAmounts(_ amounts: [UInt256], path: [EVM.EVMAddress]): [UFix64] {
        let convertedAmounts: [UFix64]= []
        for i, amount in amounts {
            convertedAmounts.append(FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(amount, erc20Address: path[i]))
        }
        return convertedAmounts
    }
}
