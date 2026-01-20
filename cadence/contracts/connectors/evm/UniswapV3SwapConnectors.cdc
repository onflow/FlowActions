import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"

import "DeFiActions"
import "SwapConnectors"
import "EVMAbiHelpers"

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
    // (bytes,address,uint256,uint256)
    access(all) fun encodeTuple_bytes_addr_u256_u256(
        path: [UInt8],
        recipient: EVM.EVMAddress,
        amountOne: UInt256,
        amountTwo: UInt256
    ): [UInt8] {
        let tupleHeadSize = 32 * 4

        var head: [[UInt8]] = []
        var tail: [[UInt8]] = []

        // 1) bytes path (dynamic) -> pointer to tail, relative to start of this tuple blob
        head.append(EVMAbiHelpers.abiWord(UInt256(tupleHeadSize)))
        tail.append(EVMAbiHelpers.abiDynamicBytes(path))

        head.append(EVMAbiHelpers.abiAddress(recipient))

        head.append(EVMAbiHelpers.abiUInt256(amountOne))

        head.append(EVMAbiHelpers.abiUInt256(amountTwo))

        return EVMAbiHelpers.concat(head).concat(EVMAbiHelpers.concat(tail))
    }

    /// Convert an ERC20 `UInt256` amount into a Cadence `UFix64` **by rounding down** to the
    /// maximum `UFix64` precision (8 decimal places).
    ///
    /// - For `decimals <= 8`, the value is exactly representable, so this is a direct conversion.
    /// - For `decimals > 8`, this floors the ERC20 amount to the nearest multiple of
    ///   `quantum = 10^(decimals - 8)` so the result round-trips safely:
    ///   `ufix64ToUInt256(result) <= amt`.
    access(all) fun toCadenceOutWithDecimals(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum: UInt256 = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)
        let remainder: UInt256 = amt % quantum
        let floored: UInt256 = amt - remainder

        return FlowEVMBridgeUtils.uint256ToUFix64(value: floored, decimals: decimals)
    }

    /// Convert an ERC20 `UInt256` amount into a Cadence `UFix64` **by rounding up** to the
    /// smallest representable value at `UFix64` precision (8 decimal places).
    ///
    /// - For `decimals <= 8`, the value is exactly representable, so this is a direct conversion.
    /// - For `decimals > 8`, this ceils the ERC20 amount to the next multiple of
    ///   `quantum = 10^(decimals - 8)` (unless already exact), ensuring:
    ///   `ufix64ToUInt256(result) >= amt`, and the increase is `< quantum`.
    access(all) fun toCadenceInWithDecimals(_ amt: UInt256, decimals: UInt8): UFix64 {
        if decimals <= 8 {
            return FlowEVMBridgeUtils.uint256ToUFix64(value: amt, decimals: decimals)
        }

        let quantumExp: UInt8 = decimals - 8
        let quantum: UInt256 = FlowEVMBridgeUtils.pow(base: 10, exponent: quantumExp)

        let remainder: UInt256 = amt % quantum
        var padded: UInt256 = amt
        if remainder != 0 {
            padded = amt + (quantum - remainder)
        }

        return FlowEVMBridgeUtils.uint256ToUFix64(value: padded, decimals: decimals)
    }

    /// ExactInputSingleParams facilitates the ABI encoding/decoding of the
    /// Solidity tuple expected in `ISwapRouter.exactInput` function.
    access(all) struct ExactInputSingleParams {
        access(all) let path: EVM.EVMBytes
        access(all) let recipient: EVM.EVMAddress
        access(all) let amountIn: UInt256
        access(all) let amountOutMinimum: UInt256

        init(
            path: EVM.EVMBytes,
            recipient: EVM.EVMAddress,
            amountIn: UInt256,
            amountOutMinimum: UInt256
        ) {
            self.path = path
            self.recipient = recipient
            self.amountIn = amountIn
            self.amountOutMinimum = amountOutMinimum
        }
    }

    /// Swapper
    access(all) struct Swapper: DeFiActions.Swapper {
        access(all) let routerAddress: EVM.EVMAddress
        access(all) let quoterAddress: EVM.EVMAddress
        access(self) let factoryAddress: EVM.EVMAddress

        access(all) let tokenPath: [EVM.EVMAddress]
        access(all) let feePath: [UInt32]

        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        access(self) let inVault: Type
        access(self) let outVault: Type

        access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

        init(
            factoryAddress: EVM.EVMAddress,
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
            self.factoryAddress = factoryAddress
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


        access(self) view fun outToken(_ reverse: Bool): EVM.EVMAddress {
            if reverse {
                return self.tokenPath[0]
            }
            return self.tokenPath[self.tokenPath.length - 1]
        }
        access(self) view fun inToken(_ reverse: Bool): EVM.EVMAddress {
            if reverse {
                return self.tokenPath[self.tokenPath.length - 1]
            }
            return self.tokenPath[0]
        }

        /// Estimate required input for a desired output
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            // OUT token for this direction
            let outToken = self.outToken(reverse)
            let desiredOutEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forDesired,
                erc20Address: outToken
            )

            // Derive true Uniswap direction for pool math
            let zeroForOne = self.isZeroForOne(reverse: reverse)

            // Max INPUT proxy in correct pool terms
            // TODO: Multi-hop clamp currently uses the first pool (tokenPath[0]/[1]) even in reverse;
            // consider clamping per-hop or disabling clamp when tokenPath.length > 2.
            let maxInEVM = self.getMaxInAmount(zeroForOne: zeroForOne)

            // If clamp proxy is 0, don't clamp — it's a truncation/edge case
            var safeOutEVM = desiredOutEVM

            if maxInEVM > 0 {
                // Translate max input -> max output using exactInput quote
                if let maxOutCadence = self.getV3Quote(out: true, amount: maxInEVM, reverse: reverse) {
                    let maxOutEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                        maxOutCadence,
                        erc20Address: outToken
                    )
                    if safeOutEVM > maxOutEVM {
                        safeOutEVM = maxOutEVM
                    }
                }
                // If maxOutCadence is nil, we also skip clamping (better than forcing 0)
            }

            let safeOutCadence = self._toCadenceOut(
                safeOutEVM,
                erc20Address: outToken
            )

            // ExactOutput quote: how much IN required for safeOutEVM OUT
            let amountInCadence = self.getV3Quote(out: false, amount: safeOutEVM, reverse: reverse)

            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountInCadence ?? 0.0,
                outAmount: amountInCadence != nil ? safeOutCadence : 0.0
            )
        }

        /// Estimate output for a provided input
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            // IN token for this direction
            let inToken = self.inToken(reverse)
            let providedInEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forProvided,
                erc20Address: inToken
            )

            // Max INPUT proxy in correct pool terms
            // TODO: Multi-hop clamp currently uses the first pool (tokenPath[0]/[1]) even in reverse;
            // consider clamping per-hop or disabling clamp when tokenPath.length > 2.
            let maxInEVM = self.maxInAmount(reverse: reverse)

            // If clamp proxy is 0, don't clamp — it's a truncation/edge case
            var safeInEVM = providedInEVM
            if maxInEVM > 0 && safeInEVM > maxInEVM {
                safeInEVM = maxInEVM
            }

            // Provided IN amount => ceil
            let safeInCadence = self._toCadenceIn(
                safeInEVM,
                erc20Address: inToken
            )

            // ExactInput quote: how much OUT for safeInEVM IN
            let amountOutCadence = self.getV3Quote(out: true, amount: safeInEVM, reverse: reverse)

            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountOutCadence != nil ? safeInCadence : 0.0,
                outAmount: amountOutCadence ?? 0.0
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

        /// Build Uniswap V3 path bytes:
        /// token0(20) | fee0(3) | token1(20) | fee1(3) | token2(20) | ...
        access(self) fun _buildPathBytes(reverse: Bool): EVM.EVMBytes {
            var out: [UInt8] = []

            // helper to append address bytes
            fun appendAddr(_ a: EVM.EVMAddress) {
                let fixed: [UInt8; 20] = a.bytes
                var i = 0
                while i < 20 {
                    out.append(fixed[i])
                    i = i + 1
                }
            }

            // helper to append uint24 fee big-endian
            fun appendFee(_ f: UInt32) {
                // validate fee fits uint24
                pre { f <= 0xFFFFFF: "feePath element exceeds uint24" }
                out.append(UInt8((f >> 16) & 0xFF))
                out.append(UInt8((f >> 8) & 0xFF))
                out.append(UInt8(f & 0xFF))
            }

            let nHops = self.feePath.length
            let last = self.tokenPath.length - 1

            // choose first token based on direction
            let first = reverse ? self.tokenPath[last] : self.tokenPath[0]
            appendAddr(first)

            var i = 0
            while i < nHops {
                let feeIdx = reverse ? (nHops - 1 - i) : i
                let nextIdx = reverse ? (last - (i + 1)) : (i + 1)

                appendFee(self.feePath[feeIdx])
                appendAddr(self.tokenPath[nextIdx])

                i = i + 1
            }

            return EVM.EVMBytes(value: out)
        }

        access(self) fun getPoolAddress(): EVM.EVMAddress {
            let res = self._dryCall(
                self.factoryAddress,
                "getPool(address,address,uint24)",
                [ self.tokenPath[0], self.tokenPath[1], UInt256(self.feePath[0]) ],
                120_000
            )!
            assert(res.status == EVM.Status.successful, message: "unable to get pool: token0 \(self.tokenPath[0].toString()), token1 \(self.tokenPath[1].toString()), feePath: self.feePath[0]")

            // ABI return is one 32-byte word; the last 20 bytes are the address
            let word = res.data as! [UInt8]
            if word.length < 32 { panic("getPool: invalid ABI word length") }

            let addrSlice = word.slice(from: 12, upTo: 32)   // 20 bytes
            let addrBytes: [UInt8; 20] = addrSlice.toConstantSized<[UInt8; 20]>()!

            return EVM.EVMAddress(bytes: addrBytes)
        }

        access(self) fun maxInAmount(reverse: Bool): UInt256 {
            let zeroForOne = self.isZeroForOne(reverse: reverse)
            return self.getMaxInAmount(zeroForOne: zeroForOne)
        }

        /// Simplified max input calculation using default 6% price impact
        /// Uses current liquidity as proxy for max swappable input amount
        access(self) fun getMaxInAmount(zeroForOne: Bool): UInt256 {
            let poolEVMAddress = self.getPoolAddress()
            
            // Helper functions
            fun wordToUInt(_ w: [UInt8]): UInt {
                var acc: UInt = 0
                var i = 0
                while i < 32 { acc = (acc << 8) | UInt(w[i]); i = i + 1 }
                return acc
            }
            fun wordToUIntN(_ w: [UInt8], _ nBits: Int): UInt {
                let full = wordToUInt(w)
                if nBits >= 256 { return full }
                let mask: UInt = (UInt(1) << UInt(nBits)) - UInt(1)
                return full & mask
            }
            fun words(_ data: [UInt8]): [[UInt8]] {
                let n = data.length / 32
                var out: [[UInt8]] = []
                var i = 0
                while i < n {
                    out.append(data.slice(from: i*32, upTo: (i+1)*32))
                    i = i + 1
                }
                return out
            }
            
            // Selectors
            let SEL_SLOT0: [UInt8] = [0x38, 0x50, 0xc7, 0xbd]
            let SEL_LIQUIDITY: [UInt8] = [0x1a, 0x68, 0x65, 0x02]
            
            // Get slot0 (sqrtPriceX96, tick, etc.)
            let s0Res: EVM.Result? = self._dryCallRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_SLOT0, args: []),
                gasLimit: 1_000_000,
            )
            let s0w = words(s0Res!.data)
            let sqrtPriceX96 = wordToUIntN(s0w[0], 160)
            
            // Get current active liquidity
            let liqRes: EVM.Result? = self._dryCallRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_LIQUIDITY, args: []),
                gasLimit: 300_000,
            )
            let L = wordToUIntN(words(liqRes!.data)[0], 128)
            
            // Calculate price multiplier based on 6% price impact (600 bps)
            // Use UInt256 throughout to prevent overflow in multiplication operations
            let bps: UInt256 = 600
            let Q96: UInt256 = 0x1000000000000000000000000
            let sqrtPriceX96_256: UInt256 = UInt256(sqrtPriceX96)
            let L_256: UInt256 = UInt256(L)
            
            var maxAmount: UInt256 = 0
            if zeroForOne {
                // Swapping token0 -> token1 (price decreases by maxPriceImpactBps)
                // Formula: Δx = L * (√P - √P') / (√P * √P')
                // Approximation: √P' ≈ √P * (1 - priceImpact/2)
                let sqrtMultiplier: UInt256 = 10000 - (bps / 2)
                let sqrtPriceNew: UInt256 = (sqrtPriceX96_256 * sqrtMultiplier) / 10000
                let deltaSqrt: UInt256 = sqrtPriceX96_256 - sqrtPriceNew
                
                // Uniswap V3 spec: getAmount0Delta
                // Δx = L * (√P - √P') / (√P * √P')
                // Since sqrt prices are in Q96 format: (L * ΔsqrtP * Q96) / (sqrtP * sqrtP')
                // This gives us native token0 units after the two Q96 divisions cancel with one Q96 multiplication
                let num1: UInt256 = L_256 * bps
                let num2: UInt256 = num1 * Q96
                let den: UInt256  = UInt256(20000) * sqrtPriceNew
                maxAmount = den == 0 ? UInt256(0) : num2 / den
            } else {
                // Swapping token1 -> token0 (price increases by maxPriceImpactBps)
                // Formula: Δy = L * (√P' - √P)
                // Approximation: √P' ≈ √P * (1 + priceImpact/2)
                let sqrtMultiplier: UInt256 = 10000 + (bps / 2)
                let sqrtPriceNew: UInt256 = (sqrtPriceX96_256 * sqrtMultiplier) / 10000
                let deltaSqrt: UInt256 = sqrtPriceNew - sqrtPriceX96_256
                
                // Uniswap V3 spec: getAmount1Delta
                // Δy = L * (√P' - √P)
                // Divide by Q96 to convert from Q96 format to native token units
                maxAmount = (L_256 * deltaSqrt) / Q96
            }
            
            return maxAmount
        }

        /// Quote using the Uniswap V3 Quoter via dryCall
        access(self) fun getV3Quote(out: Bool, amount: UInt256, reverse: Bool): UFix64? {
            // For exactOutput, the path must be reversed (tokenOut -> ... -> tokenIn)
            let pathReverse = out ? reverse : !reverse
            let pathBytes = self._buildPathBytes(reverse: pathReverse)

            let callSig = out
                ? "quoteExactInput(bytes,uint256)"
                : "quoteExactOutput(bytes,uint256)"

            let args: [AnyStruct] = [pathBytes, amount]

            let res = self._dryCall(self.quoterAddress, callSig, args, 1_000_000)
            if res == nil || res!.status != EVM.Status.successful { return nil }

            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res!.data)
            if decoded.length == 0 { return nil }
            let uintAmt = decoded[0] as! UInt256

            let ercAddr = out
                ? self.outToken(reverse)
                : self.inToken(reverse)

            // out == true  => quoteExactInput  => result is an OUT amount => floor
            // out == false => quoteExactOutput => result is an IN amount  => ceil
            if out {
                return self._toCadenceOut(uintAmt, erc20Address: ercAddr)
            } else {
                return self._toCadenceIn(uintAmt, erc20Address: ercAddr)
            }
        }

        /// Executes exact input swap via router
        access(self) fun _swapExactIn(exactVaultIn: @{FungibleToken.Vault}, amountOutMin: UFix64, reverse: Bool): @{FungibleToken.Vault} {
            let id = self.uniqueID?.id?.toString() ?? "UNASSIGNED"
            let idType = self.uniqueID?.getType()?.identifier ?? "UNASSIGNED"
            let coa = self.borrowCOA()
                ?? panic("Invalid COA Capability in V3 Swapper \(self.getType().identifier) ID \(idType)#\(id)")

            // Bridge fee
            let bridgeFeeBalance = EVM.Balance(attoflow: 0)
            bridgeFeeBalance.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256))
            let feeVault <- coa.withdraw(balance: bridgeFeeBalance)
            let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

            // I/O tokens
            let inToken = self.inToken(reverse)
            let outToken = self.outToken(reverse)

            // Bridge input to EVM
            let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(exactVaultIn.balance, erc20Address: inToken)
            coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeVaultRef)

            // Build path
            let pathBytes = self._buildPathBytes(reverse: reverse)

            // Approve
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

            // Min out on EVM units
            let minOutUint = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                amountOutMin,
                erc20Address: outToken
            )

            let coaRef = self.borrowCOA()!
            let recipient: EVM.EVMAddress = coaRef.address()

            // optional dev guards
            let _chkIn  = EVMAbiHelpers.abiUInt256(evmAmountIn)
            let _chkMin = EVMAbiHelpers.abiUInt256(minOutUint)
            //panic("path: \(EVMAbiHelpers.toHex(pathBytes.value)), amountIn: \(evmAmountIn.toString()), amountOutMin: \(minOutUint.toString())")
            assert(_chkIn.length == 32,  message: "amountIn not 32 bytes")
            assert(_chkMin.length == 32, message: "amountOutMin not 32 bytes")

            let exactInputParams = UniswapV3SwapConnectors.ExactInputSingleParams(
                path: pathBytes,
                recipient: recipient,
                amountIn: evmAmountIn,
                amountOutMinimum: minOutUint
            )

            let calldata: [UInt8] = EVM.encodeABIWithSignature(
                "exactInput((bytes,address,uint256,uint256))",
                [exactInputParams]
            )

            // Call the router with raw calldata
            let swapRes = self._callRaw(
                to: self.routerAddress,
                calldata: calldata,
                gasLimit: 2_000_000,
                value: 0
            )!
            if swapRes.status != EVM.Status.successful {
                UniswapV3SwapConnectors._callError(
                    EVMAbiHelpers.toHex(calldata),
                    swapRes, self.routerAddress, idType, id, self.getType()
                )
            }
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: swapRes.data)
            let amountOut: UInt256 = decoded.length > 0 ? decoded[0] as! UInt256 : UInt256(0)

            let outTokenEVMAddress =
                FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.outType())
                ?? panic("out token \(self.outType().identifier) is not bridged")

            let outUFix = self._toCadenceOut(
                amountOut,
                erc20Address: outTokenEVMAddress
            )

            let safeAmountOut = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                outUFix,
                erc20Address: outTokenEVMAddress
            )
            // Withdraw output back to Flow
            let outVault <- coa.withdrawTokens(type: self.outType(), amount: safeAmountOut, feeProvider: feeVaultRef)

            // Handle leftover fee vault
            self._handleRemainingFeeVault(<-feeVault)
            return <- outVault
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

        access(self) fun _dryCallRaw(to: EVM.EVMAddress, calldata: [UInt8], gasLimit: UInt64): EVM.Result? {
            let valueBalance = EVM.Balance(attoflow: 0)
            if let coa = self.borrowCOA() {
                return coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBalance)
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

        access(self) fun _callRaw(to: EVM.EVMAddress, calldata: [UInt8], gasLimit: UInt64, value: UInt): EVM.Result? {
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

        /// OUT amounts: round down to UFix64 precision
        access(self) fun _toCadenceOut(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
            let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
            return UniswapV3SwapConnectors.toCadenceOutWithDecimals(amt, decimals: decimals)
        }

        /// IN amounts: round up to the next UFix64 such that the ERC20 conversion
        /// (via ufix64ToUInt256) is >= the original UInt256 amount.
        access(self) fun _toCadenceIn(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
            let decimals = FlowEVMBridgeUtils.getTokenDecimals(evmContractAddress: erc20Address)
            return UniswapV3SwapConnectors.toCadenceInWithDecimals(amt, decimals: decimals)
        }
        access(self) fun getPoolToken0(_ pool: EVM.EVMAddress): EVM.EVMAddress {
            // token0() selector = 0x0dfe1681
            let SEL_TOKEN0: [UInt8] = [0x0d, 0xfe, 0x16, 0x81]
            let res = self._dryCallRaw(
                to: pool,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_TOKEN0, args: []),
                gasLimit: 150_000,
            )!
            assert(res.status == EVM.Status.successful, message: "token0() call failed")

            let word = res.data as! [UInt8]
            let addrSlice = word.slice(from: 12, upTo: 32)
            let addrBytes: [UInt8; 20] = addrSlice.toConstantSized<[UInt8; 20]>()!
            return EVM.EVMAddress(bytes: addrBytes)
        }

        access(self) fun isZeroForOne(reverse: Bool): Bool {
            let pool = self.getPoolAddress()
            let token0 = self.getPoolToken0(pool)

            // your actual input token for this swap direction:
            let inToken = self.inToken(reverse)

            return inToken.equals(token0)
        }
    }

    /// Revert helper
    access(self)
    fun _callError(
        _ signature: String,
        _ res: EVM.Result,
        _ target: EVM.EVMAddress,
        _ uniqueIDType: String,
        _ id: String,
        _ swapperType: Type
    ) {
        panic(
            "Call to \(target.toString()).\(signature) from Swapper \(swapperType.identifier) with UniqueIdentifier \(uniqueIDType) ID \(id) failed:\n\tStatus value: \(res.status.rawValue.toString())\n\tError code: \(res.errorCode.toString())\n\tErrorMessage: \(res.errorMessage)\n"
        )
    }
}
