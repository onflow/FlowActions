import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"

import "DeFiActions"
import "SwapConnectors"
import "EVMAbiHelpers"
import "EVMAmountUtils"

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

            // For multi-hop paths, find the effective max input by considering all hops.
            // The bottleneck is the hop with the smallest capacity when translated to input terms.
            let maxInEVM = self.getEffectiveMaxInput(reverse: reverse)

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

            // Refine outAmount: the ceiled input may produce more output than safeOutCadence
            // because (a) UFix64 ceiling rounds the input up and (b) the pool's exactOutput/
            // exactInput math is not perfectly invertible.  Do a follow-up exactInput quote
            // with the ceiled input so that quoteIn.outAmount matches what a subsequent
            // quoteOut(forProvided: ceiledInput) would return.  This keeps quote-level dust
            // bounded at ≤ 1 UFix64 quantum (0.00000001).
            var refinedOutCadence = safeOutCadence
            if let inCadence = amountInCadence {
                let inToken = self.inToken(reverse)
                let ceiledInEVM = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                    inCadence,
                    erc20Address: inToken
                )
                if let forwardOut = self.getV3Quote(out: true, amount: ceiledInEVM, reverse: reverse) {
                    refinedOutCadence = forwardOut
                }
            }

            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountInCadence ?? 0.0,
                outAmount: amountInCadence != nil ? refinedOutCadence : 0.0
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

            // For multi-hop paths, find the effective max input by considering all hops.
            // The bottleneck is the hop with the smallest capacity when translated to input terms.
            let maxInEVM = self.getEffectiveMaxInput(reverse: reverse)

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

        /// Calculates the effective maximum input for the entire path by finding the bottleneck hop.
        /// For multi-hop swaps, each hop has its own max input capacity based on liquidity.
        /// We translate each hop's capacity back to the initial input token terms
        /// and find the minimum.
        ///
        /// For a path A -> B -> C (forward):
        ///   - Hop 0: maxIn0 is already in terms of token A
        ///   - Hop 1: maxIn1 is in terms of token B, need to translate to token A via quoteExactOutput
        ///
        /// For a path C -> B -> A (reverse):
        ///   - Hop 0: maxIn0 is in terms of token C
        ///   - Hop 1: maxIn1 is in terms of token B, need to translate to token C via quoteExactOutput
        access(self) fun getEffectiveMaxInput(reverse: Bool): UInt256 {
            let nHops = self.feePath.length

            // For single-hop, just return the first hop's max
            if nHops == 1 {
                return self.getMaxInForHop(hopIndex: 0, reverse: reverse)
            }

            // Start with no limit
            var effectiveMaxIn: UInt256 = 0

            // Process each hop
            var hopIdx = 0
            while hopIdx < nHops {
                // Get the max input for this hop (in terms of its input token)
                let hopMaxIn = self.getMaxInForHop(hopIndex: hopIdx, reverse: reverse)

                if hopMaxIn == 0 {
                    // Skip if this hop returns 0
                    hopIdx = hopIdx + 1
                    continue
                }

                var translatedMaxIn = hopMaxIn

                // If not the first hop, translate back to initial input token
                if hopIdx > 0 {
                    // Use getV3QuoteRaw with partial path (exactOutput) to translate
                    // hopMaxIn (in hop's input token) back to initial input token
                    let translatedAmount = self.getV3QuoteRaw(out: false, amount: hopMaxIn, reverse: reverse, numHops: hopIdx)
                    
                    if translatedAmount == nil {
                        // Cannot translate, skip this hop's constraint
                        hopIdx = hopIdx + 1
                        continue
                    }
                    
                    translatedMaxIn = translatedAmount!
                }

                // Update effective max (take minimum)
                if translatedMaxIn > 0 && (effectiveMaxIn == 0 || translatedMaxIn < effectiveMaxIn) {
                    effectiveMaxIn = translatedMaxIn
                }

                hopIdx = hopIdx + 1
            }

            return effectiveMaxIn
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

        /// Build Uniswap V3 path bytes.
        ///
        /// - reverse: path direction (false = A->B->C->D, true = D->C->B->A)
        /// - numHops: number of hops to include. If nil, includes all hops (full path).
        /// - exactOutput:
        ///     - false → normal path order (used for exactInput & standard quoting)
        ///     - true  → reversed partial path (used for quoteExactOutput)
        ///
        /// Path format: token(20) | fee(3) | token(20) | fee(3) | token(20) | ...
        ///
        /// Examples for tokenPath [A, B, C, D] with fees [f0, f1, f2]:
        ///
        /// Normal path (exactInput & forward quoting):
        ///
        /// For forward swap (A -> B -> C -> D):
        ///   - numHops=nil: need to quote A -> B -> C -> D, want D amount,
        ///                     path: A | f0 | B | f1 | C | f2 | D
        ///   - numHops=1:   need to quote A -> B, want B amount,
        ///                     path: A | f0 | B
        ///   - numHops=2:   need to quote A -> B -> C, want C amount,
        ///                     path: A | f0 | B | f1 | C
        ///
        /// For reverse swap (D -> C -> B -> A):
        ///   - numHops=nil: need to quote D -> C -> B -> A, want A amount,
        ///                     path: D | f2 | C | f1 | B | f0 | A
        ///   - numHops=1:   need to quote D -> C, want C amount,
        ///                     path: D | f2 | C
        ///   - numHops=2:   need to quote D -> C -> B, want B amount,
        ///                     path: D | f2 | C | f1 | B
        ///
        /// Exact output path (quoteExactOutput):
        ///
        /// For forward swap (A -> B -> C -> D):
        ///   - numHops=nil: need to quote D -> C -> B -> A, want A amount,
        ///                     path: D | f2 | C | f1 | B | f0 | A
        ///   - numHops=1:   need to quote B -> A, want A amount,
        ///                     path: B | f0 | A
        ///   - numHops=2:   need to quote C -> B -> A, want A amount,
        ///                     path: C | f1 | B | f0 | A
        ///
        /// For reverse swap (D -> C -> B -> A):
        ///   - numHops=nil: need to quote A -> B -> C -> D, want D amount,
        ///                     path: A | f0 | B | f1 | C | f2 | D
        ///   - numHops=1:   need to quote D -> C, want C amount,
        ///                     path: C | f2 | D
        ///   - numHops=2:   need to quote D -> C -> B, want B amount,
        ///                     path: B | f1 | C | f2 | D
        ///
        access(self) fun _buildPathBytes(
            reverse: Bool,
            exactOutput: Bool,
            numHops: Int?,
        ): EVM.EVMBytes {
            if let nHops = numHops {
                assert(nHops >= 1 && nHops <= self.feePath.length, message: "numHops out of bounds: path supports up to \(self.feePath.length), got: \(nHops)")
            }

            var out: [UInt8] = []

            // helper to append address bytes
            fun appendAddr(_ a: EVM.EVMAddress) {
                let fixed = a.bytes
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
            let hopsToInclude = numHops ?? nHops

            // Exact output (reversed path)
            if exactOutput {
                if reverse {
                    // Reverse swap direction: D -> C -> B -> A
                    // Initial input is tokenPath[last], hop 1's input is tokenPath[last-1], etc.
                    // For numHops=1: output is tokenPath[last-1]=C, input is tokenPath[last]=D
                    // Path: C | f2 | D

                    // Start with the output token (the input token of the target hop)
                    let outputIdx = last - hopsToInclude
                    appendAddr(self.tokenPath[outputIdx])

                    // Walk backwards through hops until we reach the initial input token
                    var i = hopsToInclude - 1
                    while i >= 0 {
                        let feeIdx = nHops - 1 - i
                        let tokenIdx = last - i
                        appendFee(self.feePath[feeIdx])
                        appendAddr(self.tokenPath[tokenIdx])
                        i = i - 1
                    }
                } else {
                    // Forward swap direction: A -> B -> C -> D
                    // Initial input is tokenPath[0], hop 1's input is tokenPath[1], etc.
                    // For numHops=1: output is tokenPath[1]=B, input is tokenPath[0]=A
                    // Path: B | f0 | A

                    // Start with the output token (the input token of the target hop)
                    appendAddr(self.tokenPath[hopsToInclude])

                    // Walk backwards through hops until we reach the initial input token
                    var i = hopsToInclude - 1
                    while i >= 0 {
                        appendFee(self.feePath[i])
                        appendAddr(self.tokenPath[i])
                        i = i - 1
                    }
                }

                return EVM.EVMBytes(value: out)
            }

            // Normal path (forward encoding)

            // Start token depends on direction:
            //   forward → tokenPath[0]
            //   reverse → tokenPath[last]
            let first = reverse ? self.tokenPath[last] : self.tokenPath[0]
            appendAddr(first)

            var i = 0
            while i < hopsToInclude {
                let feeIdx = reverse ? (nHops - 1 - i) : i
                let nextIdx = reverse ? (last - (i + 1)) : (i + 1)

                appendFee(self.feePath[feeIdx])
                appendAddr(self.tokenPath[nextIdx])
                i = i + 1
            }

            return EVM.EVMBytes(value: out)
        }

        /// Returns the pool address for a specific hop in the path.
        /// - hopIndex: 0-based index of the hop (0 for first hop, 1 for second, etc.)
        /// - reverse: if true, the path is traversed in reverse order
        /// For a path [A, B, C] with fees [fee0, fee1]:
        ///   - Forward: hop 0 = pool(A, B, fee0), hop 1 = pool(B, C, fee1)
        ///   - Reverse: hop 0 = pool(C, B, fee1), hop 1 = pool(B, A, fee0)
        access(self) fun getPoolAddress(hopIndex: Int, reverse: Bool): EVM.EVMAddress {
            pre {
                hopIndex >= 0 && hopIndex < self.feePath.length: "hopIndex out of bounds: \(hopIndex), nHops: \(self.feePath.length)"
            }

            let nHops = self.feePath.length
            let last = self.tokenPath.length - 1

            let tokenA = reverse
                ? self.tokenPath[last - hopIndex]
                : self.tokenPath[hopIndex]

            let tokenB = reverse
                ? self.tokenPath[last - hopIndex - 1]
                : self.tokenPath[hopIndex + 1]

            let fee = reverse
                ? self.feePath[nHops - 1 - hopIndex]
                : self.feePath[hopIndex]

            let res = self._dryCall(
                self.factoryAddress,
                "getPool(address,address,uint24)",
                [ tokenA, tokenB, UInt256(fee) ],
                120_000
            )!
            assert(
                res.status == EVM.Status.successful,
                message: "unable to get pool: tokenA \(tokenA.toString()), tokenB \(tokenB.toString()), fee: \(fee)"
            )

            // ABI return is one 32-byte word; the last 20 bytes are the address
            let word = res.data
            if word.length < 32 { panic("getPool: invalid ABI word length") }

            let addrSlice = word.slice(from: 12, upTo: 32)   // 20 bytes
            let addrBytes = addrSlice.toConstantSized<[UInt8; 20]>()!

            return EVM.EVMAddress(bytes: addrBytes)
        }

        /// Get max input amount for a specific hop
        access(self) fun getMaxInForHop(hopIndex: Int, reverse: Bool): UInt256 {
            // Derive true Uniswap direction for pool math
            let zeroForOne = self.isZeroForOne(hopIndex: hopIndex, reverse: reverse)

            return self.getMaxInAmount(
                hopIndex: hopIndex,
                zeroForOne: zeroForOne,
                reverse: reverse
            )
        }

        /// Simplified max input calculation using default 6% price impact
        /// Uses current liquidity as proxy for max swappable input amount
        access(self) fun getMaxInAmount(hopIndex: Int, zeroForOne: Bool, reverse: Bool): UInt256 {
            let poolEVMAddress = self.getPoolAddress(hopIndex: hopIndex, reverse: reverse)
            
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
                let mask: UInt = (1 << UInt(nBits)) - 1
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
            let s0Res = self._dryCallRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_SLOT0, args: []),
                gasLimit: 1_000_000,
            )
            let s0w = words(s0Res!.data)
            let sqrtPriceX96 = wordToUIntN(s0w[0], 160)
            
            // Get current active liquidity
            let liqRes = self._dryCallRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_LIQUIDITY, args: []),
                gasLimit: 300_000,
            )
            let L = wordToUIntN(words(liqRes!.data)[0], 128)
            
            // Calculate price multiplier based on 6% price impact (600 bps)
            // Use UInt256 throughout to prevent overflow in multiplication operations
            let bps: UInt256 = 600
            let Q96: UInt256 = 0x1000000000000000000000000
            let sqrtPriceX96_256 = UInt256(sqrtPriceX96)
            let L_256 = UInt256(L)
            
            var maxAmount: UInt256 = 0
            if zeroForOne {
                // Swapping token0 -> token1 (price decreases by maxPriceImpactBps)
                // Formula: Δx = L * (√P - √P') / (√P * √P')
                // Approximation: √P' ≈ √P * (1 - priceImpact/2)
                let sqrtMultiplier: UInt256 = 10000 - (bps / 2)
                let sqrtPriceNew: UInt256 = (sqrtPriceX96_256 * sqrtMultiplier) / 10000
                
                // Uniswap V3 spec: getAmount0Delta
                // Δx = L * (√P - √P') / (√P * √P')
                // Since sqrt prices are in Q96 format: (L * ΔsqrtP * Q96) / (sqrtP * sqrtP')
                // This gives us native token0 units after the two Q96 divisions cancel with one Q96 multiplication
                let num1 = L_256 * bps
                let num2 = num1 * Q96
                let den: UInt256 = 20000 * sqrtPriceNew
                maxAmount = den == 0 ? 0 : num2 / den
            } else {
                // Swapping token1 -> token0 (price increases by maxPriceImpactBps)
                // Formula: Δy = L * (√P' - √P)
                // Approximation: √P' ≈ √P * (1 + priceImpact/2)
                let sqrtMultiplier: UInt256 = 10000 + (bps / 2)
                let sqrtPriceNew = (sqrtPriceX96_256 * sqrtMultiplier) / 10000
                let deltaSqrt = sqrtPriceNew - sqrtPriceX96_256
                
                // Uniswap V3 spec: getAmount1Delta
                // Δy = L * (√P' - √P)
                // Divide by Q96 to convert from Q96 format to native token units
                maxAmount = (L_256 * deltaSqrt) / Q96
            }
            
            return maxAmount
        }

        /// Quote using the Uniswap V3 Quoter via dryCall (returns UFix64)
        access(self) fun getV3Quote(out: Bool, amount: UInt256, reverse: Bool): UFix64? {
            let result = self.getV3QuoteRaw(out: out, amount: amount, reverse: reverse, numHops: nil)
            if result == nil {
                return nil
            }

            let ercAddr = out
                ? self.outToken(reverse)
                : self.inToken(reverse)

            // out == true  => quoteExactInput  => result is an OUT amount => floor
            // out == false => quoteExactOutput => result is an IN amount  => ceil
            if out {
                return self._toCadenceOut(result!, erc20Address: ercAddr)
            } else {
                return self._toCadenceIn(result!, erc20Address: ercAddr)
            }
        }

        /// Quote using the Uniswap V3 Quoter via dryCall (returns raw UInt256)
        /// - out: true for quoteExactInput (get output amount), false for quoteExactOutput (get input amount)
        /// - amount: the amount to quote
        /// - reverse: swap direction
        /// - numHops: for partial path quotes. If nil, uses full path.
        access(self) fun getV3QuoteRaw(out: Bool, amount: UInt256, reverse: Bool, numHops: Int?): UInt256? {
            // For exactOutput, Uniswap expects path in reverse order (output -> input)
            let pathBytes = self._buildPathBytes(reverse: reverse, exactOutput: !out, numHops: numHops)

            let callSig = out
                ? "quoteExactInput(bytes,uint256)"
                : "quoteExactOutput(bytes,uint256)"

            let args = [pathBytes, amount]

            let res = self._dryCall(self.quoterAddress, callSig, args, 10_000_000)
            if res == nil || res!.status != EVM.Status.successful { return nil }

            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res!.data)
            if decoded.length == 0 { return nil }

            return decoded[0] as! UInt256
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
            let pathBytes = self._buildPathBytes(reverse: reverse, exactOutput: false, numHops: nil)

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
            let recipient = coaRef.address()

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

            let calldata = EVM.encodeABIWithSignature(
                "exactInput((bytes,address,uint256,uint256))",
                [exactInputParams]
            )

            // Call the router with raw calldata
            let swapRes = self._callRaw(
                to: self.routerAddress,
                calldata: calldata,
                gasLimit: 10_000_000,
                value: 0
            )!
            if swapRes.status != EVM.Status.successful {
                UniswapV3SwapConnectors._callError(
                    EVMAbiHelpers.toHex(calldata),
                    swapRes, self.routerAddress, idType, id, self.getType()
                )
            }
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: swapRes.data)
            let amountOut: UInt256 = decoded.length > 0 ? decoded[0] as! UInt256 : 0

            let outVaultType = reverse ? self.inType() : self.outType()
            let outTokenEVMAddress =
                FlowEVMBridgeConfig.getEVMAddressAssociated(with: outVaultType)
                ?? panic("out token \(outVaultType.identifier) is not bridged")

            let outUFix = self._toCadenceOut(
                amountOut,
                erc20Address: outTokenEVMAddress
            )

            // Defensive: ensure the router respected amountOutMinimum.
            // Under normal operation the V3 router reverts when output < min, but guard
            // against a buggy or malicious router contract.
            assert(
                amountOutMin == 0.0 || outUFix >= amountOutMin,
                message: "UniswapV3SwapConnectors: swap output \(outUFix.toString()) < amountOutMin \(amountOutMin.toString())"
            )

            /// Quoting exact output then swapping exact input can overshoot by up to 0.00000001 (1 UFix64 quantum)
            /// when the pool's effective exchange rate is near 1:1.
            ///
            /// UFix64 has 8 decimals; EVM tokens typically have 18. One UFix64 step = 10^10 wei.
            ///
            /// Example (pool price 1 FLOW = 2 USDC, want 10 USDC out):
            ///   1. Quoter says need 5,000000002000000000 FLOW wei
            ///   2. Ceil to UFix64:  5,000000010000000000  (overshoot: 8e9 wei)
            ///   3. exactInput swaps the ceiled amount; extra 8e9 FLOW wei × 2 = 16e9 USDC wei extra
            ///   4. Actual output:  10,000000016000000000 USDC wei
            ///   5. Floor to UFix64: 10.00000001 USDC  (quoted 10.00000000)
            ///
            /// The overshoot is always non-negative (ceiled input >= what pool needs).
            /// It surfaces when the extra output crosses a 10^10 wei quantum boundary.
            /// Cap at amountOutMin so only the expected amount is bridged; dust stays in the COA.
            let bridgeUFix = outUFix > amountOutMin && amountOutMin > 0.0 ? amountOutMin : outUFix
            let dust = outUFix > bridgeUFix ? outUFix - bridgeUFix : 0.0
            let safeAmountOut = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                bridgeUFix,
                erc20Address: outTokenEVMAddress
            )
            // Withdraw output back to Flow; sub-quantum remainder and any overshoot stay in COA
            let outVault <- coa.withdrawTokens(type: outVaultType, amount: safeAmountOut, feeProvider: feeVaultRef)

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
            return EVMAmountUtils.toCadenceOutForToken(amt, erc20Address: erc20Address)
        }

        /// IN amounts: round up to the next UFix64 such that the ERC20 conversion
        /// (via ufix64ToUInt256) is >= the original UInt256 amount.
        access(self) fun _toCadenceIn(_ amt: UInt256, erc20Address: EVM.EVMAddress): UFix64 {
            return EVMAmountUtils.toCadenceInForToken(amt, erc20Address: erc20Address)
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

            let word = res.data
            if word.length < 32 { panic("getPoolToken0: invalid ABI word length") }

            let addrSlice = word.slice(from: 12, upTo: 32)
            let addrBytes = addrSlice.toConstantSized<[UInt8; 20]>()!
            return EVM.EVMAddress(bytes: addrBytes)
        }

        access(self) fun isZeroForOne(hopIndex: Int, reverse: Bool): Bool {
            let pool = self.getPoolAddress(hopIndex: hopIndex, reverse: reverse)
            let token0 = self.getPoolToken0(pool)

            // your actual input token for this swap direction:
            let inToken = reverse
                ? self.tokenPath[self.tokenPath.length - 1 - hopIndex]
                : self.tokenPath[hopIndex]

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