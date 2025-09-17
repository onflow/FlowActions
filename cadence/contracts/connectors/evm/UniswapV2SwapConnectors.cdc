import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "FlowEVMBridge"

import "DeFiActions"
import "SwapConnectors"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// UniswapV2SwapConnectors
///
/// DeFiActions Swapper connector implementation fitting UniswapV2 EVM-based swap protocols for use in DeFiActions
/// workflows.
///
access(all) contract UniswapV2SwapConnectors {

    /// Swapper
    ///
    /// A DeFiActions connector that swaps between tokens using an EVM-based UniswapV2Router contract
    ///
    access(all) struct Swapper : DeFiActions.Swapper {
        /// UniswapV2Router contract's EVM address
        access(all) let routerAddress: EVM.EVMAddress
        /// A swap path defining the route followed for facilitated swaps. Each element should be a valid token address
        /// for which there is a pool available with the previous and subsequent token address via the defined Router
        access(all) let addressPath: [EVM.EVMAddress]
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
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
            uniqueID: DeFiActions.UniqueIdentifier?
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
            self.addressPath = path
            self.uniqueID = uniqueID
            self.inVault = inVault
            self.outVault = outVault
            self.coaCapability = coaCapability
        }

        /// Returns a ComponentInfo struct containing information about this Swapper and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.uniqueID?.id,
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inType(): Type {
            return self.inVault
        }
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outType(): Type {
            return self.outVault
        }
        /// The estimated amount required to provide a Vault with the desired output balance returned as a BasicQuote
        /// struct containing the in and out Vault types and quoted in and out amounts
        /// NOTE: Cadence only supports decimal precision of 8
        ///
        /// @param forDesired: The amount out desired of the post-conversion currency as a result of the swap
        /// @param reverse: If false, the default inVault -> outVault is used, otherwise, the method estimates a swap
        ///     in the opposite direction, outVault -> inVault
        ///
        /// @return a SwapConnectors.BasicQuote containing estimate data. In order to prevent upstream reversion,
        ///     result.inAmount and result.outAmount will be 0.0 if an estimate is not available
        ///
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let uintDesired = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                    forDesired,
                    erc20Address: reverse ? self.addressPath[0] : self.addressPath[self.addressPath.length - 1]
                )
            let amountIn = self.getAmount(out: false, amount: uintDesired, path: reverse ? self.addressPath.reverse() : self.addressPath)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountIn != nil ? amountIn! : 0.0,
                outAmount: amountIn != nil ? forDesired : 0.0
            )
        }
        /// The estimated amount delivered out for a provided input balance returned as a BasicQuote returned as a
        /// BasicQuote struct containing the in and out Vault types and quoted in and out amounts
        /// NOTE: Cadence only supports decimal precision of 8
        ///
        /// @param forProvided: The amount provided of the relevant pre-conversion currency
        /// @param reverse: If false, the default inVault -> outVault is used, otherwise, the method estimates a swap
        ///     in the opposite direction, outVault -> inVault
        ///
        /// @return a SwapConnectors.BasicQuote containing estimate data. In order to prevent upstream reversion,
        ///     result.inAmount and result.outAmount will be 0.0 if an estimate is not available
        ///
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let uintProvided = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                    forProvided,
                    erc20Address: reverse ? self.addressPath[self.addressPath.length - 1] : self.addressPath[0]
                )
            let amountOut = self.getAmount(out: true, amount: uintProvided, path: reverse ? self.addressPath.reverse() : self.addressPath)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountOut != nil ? forProvided : 0.0,
                outAmount: amountOut != nil ? amountOut! : 0.0
            )
        }

        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. This implementation swaps
        /// along a path defined on init routing the swap to the pre-defined UniswapV2Router implementation on Flow EVM.
        /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
        /// used.
        /// NOTE: Cadence only supports decimal precision of 8
        ///
        /// @param quote: A `DeFiActions.Quote` data structure. If provided, quote.outAmount is used as the minimum amount out
        ///     desired otherwise a new quote is generated from current state
        /// @param inVault: Tokens of type `inVault` to swap for a vault of type `outVault`
        ///
        /// @return a Vault of type `outVault` containing the swapped currency.
        ///
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOutMin = quote?.outAmount ?? self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
            return <-self.swapExactTokensForTokens(exactVaultIn: <-inVault, amountOutMin: amountOutMin, reverse: false)
        }

        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        /// Any Quote provided defines the amountOutMin value - if none is provided, the current quoted outAmount is
        /// used.
        /// NOTE: Cadence only supports decimal precision of 8
        ///
        /// @param quote: A `DeFiActions.Quote` data structure. If provided, quote.outAmount is used as the minimum amount out
        ///     desired otherwise a new quote is generated from current state
        /// @param residual: Tokens of type `outVault` to swap back to `inVault`
        ///
        /// @return a Vault of type `inVault` containing the swapped currency.
        ///
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOutMin = quote?.outAmount ?? self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
            return <-self.swapExactTokensForTokens(
                exactVaultIn: <-residual,
                amountOutMin: amountOutMin,
                reverse: true
            )
        }

        /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
        /// returning the final output Vault
        ///
        /// @param exactVaultIn: The pre-conversion currency to swap
        /// @param amountOutMin: The minimum amount of post-conversion tokens to swap for
        /// @param reverse: If false, the default inVault -> outVault is used, otherwise, the method swaps in the
        ///     opposite direction, outVault -> inVault
        ///
        /// @return the resulting Vault containing the swapped tokens
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
            let inTokenAddress = reverse ? self.addressPath[self.addressPath.length - 1] : self.addressPath[0]
            let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                exactVaultIn.balance,
                erc20Address: inTokenAddress
            )
            coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeVaultRef)

            // approve the router to swap tokens
            var res = self.call(to: inTokenAddress,
                signature: "approve(address,uint256)",
                args: [self.routerAddress, evmAmountIn],
                gasLimit: 100_000,
                value: 0,
                dryCall: false
            )!
            if res.status != EVM.Status.successful {
                UniswapV2SwapConnectors._callError("approve(address,uint256)",
                    res, inTokenAddress, idType, id, self.getType())
            }
            // perform the swap
            res = self.call(to: self.routerAddress,
                signature: "swapExactTokensForTokens(uint,uint,address[],address,uint)", // amountIn, amountOutMin, path, to, deadline (timestamp)
                args: [evmAmountIn, UInt256(0), (reverse ? self.addressPath.reverse() : self.addressPath), coa.address(), UInt256(getCurrentBlock().timestamp)],
                gasLimit: 1_000_000,
                value: 0,
                dryCall: false
            )!
            if res.status != EVM.Status.successful {
                // revert because the funds have already been deposited to the COA - a no-op would leave the funds in EVM
                UniswapV2SwapConnectors._callError("swapExactTokensForTokens(uint,uint,address[],address,uint)",
                    res, self.routerAddress, idType, id, self.getType())
            }
            let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)
            let amountsOut = decoded[0] as! [UInt256]

            // withdraw tokens from EVM
            let outVault <- coa.withdrawTokens(type: self.outType(),
                    amount: amountsOut[amountsOut.length - 1],
                    feeProvider: feeVaultRef
                )

            // clean up the remaining feeVault & return the swap output Vault
            self.handleRemainingFeeVault(<-feeVault)
            return <- outVault
        }

        /* --- Internal --- */

        /// Internal method used to retrieve router.getAmountsIn and .getAmountsOut estimates. The returned array is the
        /// estimate returned from the router where each value is a swapped amount corresponding to the swap along the
        /// provided path.
        ///
        /// @param out: If true, getAmountsOut is called, otherwise getAmountsIn is called
        /// @param amount: The amount in or out. If out is true, the amount will be used as the amount in provided,
        ///     otherwise amount defines the desired amount out for the estimate
        /// @param path: The path of ERC20 token addresses defining the sequence of swaps executed to arrive at the
        ///     desired token out
        ///
        /// @return An estimate of the amounts for each swap along the path. If out is true, the return value contains
        ///     the values in, otherwise the array contains the values out for each swap along the path
        ///
        access(self) fun getAmount(out: Bool, amount: UInt256, path: [EVM.EVMAddress]): UFix64? {
            let callRes = self.call(to: self.routerAddress,
                signature: out ? "getAmountsOut(uint,address[])" : "getAmountsIn(uint,address[])",
                args: [amount],
                gasLimit: 1_000_000,
                value: UInt(0),
                dryCall: true
            )
            if callRes == nil || callRes!.status != EVM.Status.successful {
                return nil
            }
            let decoded = EVM.decodeABI(types: [Type<[UInt256]>()], data: callRes!.data) // can revert if the type cannot be decoded
            let uintAmounts: [UInt256] = decoded.length > 0 ? decoded[0] as! [UInt256] : []
            if uintAmounts.length == 0 {
                return nil
            } else if out {
                return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmounts[uintAmounts.length - 1], erc20Address: path[path.length - 1])
            } else {
                return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmounts[0], erc20Address: path[0])
            }
        }

        /// Deposits any remainder in the provided Vault or burns if it it's empty
        access(self) fun handleRemainingFeeVault(_ vault: @FlowToken.Vault) {
            if vault.balance > 0.0 {
                self.borrowCOA()!.deposit(from: <-vault)
            } else {
                Burner.burn(<-vault)
            }
        }

        /// Returns a reference to the Swapper's COA or `nil` if the contained Capability is invalid
        access(self) view fun borrowCOA(): auth(EVM.Owner) &EVM.CadenceOwnedAccount? {
            return self.coaCapability.borrow()
        }

        /// Makes a call to the Swapper's routerEVMAddress via the contained COA Capability with the provided signature,
        /// args, and value. If flagged as dryCall, the more efficient and non-mutating COA.dryCall is used. A result is
        /// returned as long as the COA Capability is valid, otherwise `nil` is returned.
        access(self) fun call(
            to: EVM.EVMAddress,
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
                    ? coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
                    : coa.call(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
                return res
            }
            return nil
        }
    }

    /// Reverts with a message constructed from the provided args. Used in the event of a coa.call() error
    access(self)
    fun _callError(_ signature: String, _ res: EVM.Result,_ target: EVM.EVMAddress, _ uniqueIDType: String, _ id: String, _ swapperType: Type) {
        panic("Call to \(target.toString()).\(signature) from Swapper \(swapperType.identifier) "
            .concat("with UniqueIdentifier \(uniqueIDType) ID \(id) failed: \n\t"
            .concat("Status value: \(res.status.rawValue)\n\t"))
            .concat("Error code: \(res.errorCode)\n\t")
            .concat("ErrorMessage: \(res.errorMessage)\n"))
    }
}
