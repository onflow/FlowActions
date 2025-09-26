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
/// UniswapV3SwapConnectors
///
/// DeFiActions Swapper connector implementation for Uniswap V3 routers on Flow EVM.
/// Supports single-hop and multi-hop swaps using exactInput / exactInputSingle and Quoter for estimates.
///
access(all) contract UniswapV3SwapConnectors {

    /// Swapper
    ///
    /// A DeFiActions connector that swaps between tokens using a Uniswap V3 Router
    ///
    access(all) struct Swapper: DeFiActions.Swapper {
        /// Uniswap V3 Router EVM address
        access(all) let routerAddress: EVM.EVMAddress
        /// Uniswap V3 Quoter EVM address (for on-chain price quotes via dry calls)
        access(all) let quoterAddress: EVM.EVMAddress

        /// Ordered list of token addresses (token0 -> ... -> tokenN)
        access(all) let tokenPath: [EVM.EVMAddress]
        /// Fee tier per hop (basis points in Uniswap V3 uint24, e.g. 500, 3000, 10000)
        /// Length must be tokenPath.length - 1
        access(all) let feePath: [UInt32]

        /// Optional ID to help align this component in a DeFiActions stack
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Input and output Vault types on Flow
        access(self) let inVault: Type
        access(self) let outVault: Type

        /// COA capability for EVM calls and token custody
        access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

        init(
            routerAddress: EVM.EVMAddress,
            quoterAddress: EVM.EVMAddress,
            tokenPath: [EVM.EVMAddress],
            feePath: [UInt32],
            inVault: Type,
            outVault: Type,
            coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                tokenPath.length >= 2: "tokenPath must contain at least two addresses"
                feePath.length == tokenPath.length - 1: "feePath length must be tokenPath.length - 1"
                FlowEVMBridgeConfig.getTypeAssociated(with: tokenPath[0]) == inVault:
                "Provided inVault \(inVault.identifier) is not associated with ERC20 at tokenPath[0]"
                FlowEVMBridgeConfig.getTypeAssociated(with: tokenPath[tokenPath.length - 1]) == outVault:
                "Provided outVault \(outVault.identifier) is not associated with ERC20 at tokenPath[last]"
                coaCapability.check():
                "Provided COA Capability is invalid - need Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>"
            }
            self.routerAddress = routerAddress
            self.quoterAddress = quoterAddress
            self.tokenPath = tokenPath
            self.feePath = feePath
            self.inVault = inVault
            self.outVault = outVault
            self.coaCapability = coaCapability
            self.uniqueID = uniqueID
        }

        /* --- DeFiActions.Swapper conformance --- */

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.uniqueID?.id,
                innerComponents: []
            )
        }

        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? { return self.uniqueID }
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) { self.uniqueID = id }

        access(all) view fun inType(): Type { return self.inVault }
        access(all) view fun outType(): Type { return self.outVault }

        /// Estimate required input for a desired output
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let desired = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forDesired,
                erc20Address: reverse ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1]
            )
            let amountIn = self.getV3Quote(out: false, amount: desired, reverse: reverse)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountIn != nil ? amountIn! : 0.0,
                outAmount: amountIn != nil ? forDesired : 0.0
            )
        }

        /// Estimate output for a provided input
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let provided = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forProvided,
                erc20Address: reverse ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0]
            )
            let amountOut = self.getV3Quote(out: true, amount: provided, reverse: reverse)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountOut != nil ? forProvided : 0.0,
                outAmount: amountOut != nil ? amountOut! : 0.0
            )
        }

        /// Swap exact input -> min output using Uniswap V3 exactInput/Single
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let minOut = quote?.outAmount ?? self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
            return <- self._swapExactIn(exactVaultIn: <-inVault, amountOutMin: minOut, reverse: false)
        }

        /// Swap back (exact input of residual -> min output)
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let minOut = quote?.outAmount ?? self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
            return <- self._swapExactIn(exactVaultIn: <-residual, amountOutMin: minOut, reverse: true)
        }

        /* --- Core swap / quote internals --- */

        /// Build Uniswap V3 path bytes: address(20) + fee(uint24) + address(20) + ...
        access(self) view fun _buildPathBytes(reverse: Bool): [UInt8] {
            let pathTokens = reverse ? self.tokenPath.reverse() : self.tokenPath
            let pathFees = reverse ? self.feePath.reverse() : self.feePath

            var bytes: [UInt8] = []
            var i: Int = 0
            while i < pathTokens.length - 1 {
                let a0 = pathTokens[i]
                let a1 = pathTokens[i+1]
                let fee = pathFees[i]
                // push token0 (20 bytes)
                bytes.appendAll(a0.bytes())
                // push fee as 3 bytes big-endian (uint24)
                let f: UInt32 = fee
                bytes.append(UInt8((f >> 16) & 0xFF))
                bytes.append(UInt8((f >> 8) & 0xFF))
                bytes.append(UInt8(f & 0xFF))
                // push token1 (20 bytes)
                bytes.appendAll(a1.bytes())
                i = i + 1
            }
            return bytes
        }

        /// Quote using the Uniswap V3 Quoter via dryCall
        /// - If out==true: quoteExactInput (amount provided -> amount out)
        /// - If out==false: quoteExactOutput (amount desired -> amount in)
        access(self) fun getV3Quote(out: Bool, amount: UInt256, reverse: Bool): UFix64? {
            let singleHop: Bool = self.tokenPath.length == 2
            let callSig: String
            let args: [AnyStruct]
            if singleHop {
                // Single hop uses *Single variants with uint24 fee
                let tokenIn = reverse ? self.tokenPath[1] : self.tokenPath[0]
                let tokenOut = reverse ? self.tokenPath[0] : self.tokenPath[1]
                let fee = UInt256(UInt(self.feePath[reverse ? 0 : 0])) // same index as only hop
                if out {
                    // quoteExactInputSingle(address,address,uint24,uint256,uint160)
                    callSig = "quoteExactInputSingle(address,address,uint24,uint256,uint160)"
                    args = [tokenIn, tokenOut, fee, amount, UInt256(0)] // no price limit
                } else {
                    // quoteExactOutputSingle(address,address,uint24,uint256,uint160)
                    callSig = "quoteExactOutputSingle(address,address,uint24,uint256,uint160)"
                    args = [tokenIn, tokenOut, fee, amount, UInt256(0)]
                }
            } else {
                // Multi-hop uses bytes path
                let pathBytes = self._buildPathBytes(reverse: reverse)
                if out {
                    // quoteExactInput(bytes,uint256) in some quoter versions it's (bytes) only; using V2 signature with amount
                    // Use signature with (bytes,uint256) if supported; fallback is (bytes)
                    callSig = "quoteExactInput(bytes,uint256)"
                    args = [pathBytes, amount]
                } else {
                    // quoteExactOutput(bytes,uint256)
                    callSig = "quoteExactOutput(bytes,uint256)"
                    args = [pathBytes, amount]
                }
            }

            let res = self._dryCall(self.quoterAddress, callSig, args, 1_000_000)
            if res == nil || res!.status != EVM.Status.successful {
                return nil
            }
            // Quoter returns (uint256 amount), possibly with additional fields in some versions; decode first uint256
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res!.data)
            if decoded.length == 0 { return nil }
            let uintAmt = decoded[0] as! UInt256

            // convert amount to UFix64 depending on direction
            let ercAddr = reverse
            ? (out ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1])
            : (out ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0])
            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmt, erc20Address: ercAddr)
        }

        /// Executes exact input swap via router (exactInputSingle for single-hop, exactInput for multi-hop)
        access(self) fun _swapExactIn(exactVaultIn: @{FungibleToken.Vault}, amountOutMin: UFix64, reverse: Bool): @{FungibleToken.Vault} {
            let id = self.uniqueID?.id?.toString() ?? "UNASSIGNED"
            let idType = self.uniqueID?.getType()?.identifier ?? "UNASSIGNED"
            let coa = self.borrowCOA()
            ?? panic("Invalid COA Capability in V3 Swapper \(self.getType().identifier) ID \(idType)#\(id)")

            // Prepare bridge fees (bridge to EVM then bridge back)
            let bridgeFeeBalance = EVM.Balance(attoflow: 0)
            bridgeFeeBalance.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256))
            let feeVault <- coa.withdraw(balance: bridgeFeeBalance)
            let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

            // Determine input token based on direction
            let inToken = reverse ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0]
            let outToken = reverse ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1]

            // Convert and deposit tokens to COA (bridges to EVM)
            let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(exactVaultIn.balance, erc20Address: inToken)
            coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeVaultRef)

            // Approve router to spend the input token
            var res = self._call(
                to: inToken,
                signature: "approve(address,uint256)",
                args: [self.routerAddress, evmAmountIn],
                gasLimit: 120_000,
                value: 0
            )!
            if res.status != EVM.Status.successful {
                UniswapV3SwapConnectors._callError("approve(address,uint256)", res, inToken, idType, id, self.getType())
            }

            // Perform the swap
            let minOutUint = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(amountOutMin, erc20Address: outToken)

            if self.tokenPath.length == 2 {
                // exactInputSingle((address,address,uint24,address,uint,uint,uint,uint))
                // params: tokenIn, tokenOut, fee, recipient, deadline, amountIn, amountOutMinimum, sqrtPriceLimitX96
                let feeTier = UInt256(UInt(self.feePath[0]))
                res = self._call(
                    to: self.routerAddress,
                    signature: "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))",
                    args: [[inToken, outToken, feeTier, coa.address(), UInt256(getCurrentBlock().timestamp), evmAmountIn, minOutUint, UInt256(0)]],
                    gasLimit: 1_500_000,
                    value: 0
                )!
            } else {
                // exactInput((bytes,address,uint256,uint256))
                let pathBytes = self._buildPathBytes(reverse: reverse)
                res = self._call(
                    to: self.routerAddress,
                    signature: "exactInput((bytes,address,uint256,uint256))",
                    args: [[pathBytes, coa.address(), evmAmountIn, minOutUint]],
                    gasLimit: 2_000_000,
                    value: 0
                )!
            }

            if res.status != EVM.Status.successful {
                UniswapV3SwapConnectors._callError("exactInput*", res, self.routerAddress, idType, id, self.getType())
            }

            // Withdraw output tokens back to Flow
            let outVault <- coa.withdrawTokens(type: self.outType(), amount: self._firstUint256(res.data), feeProvider: feeVaultRef)

            // Clean up bridge fee vault
            self._handleRemainingFeeVault(<-feeVault)
            return <- outVault
        }

        /// Extract the first uint256 from an EVM call result; fall back to re-quoting if decoding differs by router version
        access(self) fun _firstUint256(_ data: [UInt8]): UInt256 {
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: data)
            if decoded.length > 0 { return decoded[0] as! UInt256 }
            return UInt256(0)
        }

        /* --- Helpers --- */

        access(self) view fun borrowCOA(): auth(EVM.Owner) &EVM.CadenceOwnedAccount? { return self.coaCapability.borrow() }

        access(self) fun _dryCall(_ to: EVM.EVMAddress, _ signature: String, _ args: [AnyStruct], _ gas: UInt64): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: 0)
            if let coa = self.borrowCOA() {
                return coa.dryCall(to: to, data: calldata, gasLimit: gas, value: valueBalance)
            }
            return nil
        }

        access(self) fun _call(to: EVM.EVMAddress, signature: String, args: [AnyStruct], gasLimit: UInt64, value: UInt): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: value)
            if let coa = self.borrowCOA() {
                return coa.call(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
            }
            return nil
        }

        access(self) fun _handleRemainingFeeVault(_ vault: @FlowToken.Vault) {
            if vault.balance > 0.0 {
                self.borrowCOA()!.deposit(from: <-vault)
            } else {
                Burner.burn(<-vault)
            }
        }
    }

    /// Revert helper mirroring V2 connector style
    access(self)
    fun _callError(_ signature: String, _ res: EVM.Result, _ target: EVM.EVMAddress, _ uniqueIDType: String, _ id: String, _ swapperType: Type) {
        panic("Call to \(target.toString()).\(signature) from Swapper \(swapperType.identifier) "
        .concat("with UniqueIdentifier \(uniqueIDType) ID \(id) failed: \n\t")
        .concat("Status value: \(res.status.rawValue)\n\t"))
        .concat("Error code: \(res.errorCode)\n\t")
        .concat("ErrorMessage: \(res.errorMessage)\n"))
    }
}
