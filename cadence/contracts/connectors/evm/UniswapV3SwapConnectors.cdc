import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "FlowEVMBridge"

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
            uniqueID: DeFiActions.UniqueIdentifier?,
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

        /// Estimate required input for a desired output
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let tokenEVMAddress = reverse ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1]
            let desired = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forDesired,
                erc20Address: tokenEVMAddress
            )

            let maxAmount = self.getMaxAmount(zeroForOne: reverse)

            var safeAmount = desired
            if safeAmount > maxAmount {
                safeAmount = maxAmount
            }

            let safeAmountDesired = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                safeAmount,
                erc20Address: tokenEVMAddress
            )
            //panic("desired: \(desired), maxAmount: \(maxAmount), safeAmount: \(safeAmount)")
            let amountIn = self.getV3Quote(out: false, amount: safeAmount, reverse: reverse)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountIn != nil ? amountIn! : 0.0,
                outAmount: amountIn != nil ? safeAmountDesired : 0.0
            )
        }

        /// Estimate output for a provided input
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let tokenEVMAddress = reverse ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0]
            let provided = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forProvided,
                erc20Address: tokenEVMAddress
            )

            let maxAmount = self.getMaxAmount(zeroForOne: reverse)

            var safeAmount = provided 
            if safeAmount > maxAmount {
                safeAmount = maxAmount
            }

            let safeAmountProvided = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                safeAmount,
                erc20Address: tokenEVMAddress
            )

            let amountOut = self.getV3Quote(out: true, amount: safeAmount, reverse: reverse)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountOut != nil ? safeAmountProvided : 0.0,
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
        access(self) fun _buildPathBytes(reverse: Bool): EVM.EVMBytes {
            var bytes: [UInt8] = []
            var i: Int = 0
            let last = self.tokenPath.length - 1

            while i < self.tokenPath.length - 1 {
                let idx0 = reverse ? (last - i) : i
                let idx1 = reverse ? (last - (i + 1)) : (i + 1)

                let a0 = self.tokenPath[idx0]
                let a1 = self.tokenPath[idx1]

                let feeIdx = reverse ? (self.feePath.length - 1 - i) : i
                let f: UInt32 = self.feePath[feeIdx]

                // address 0
                let a0Fixed: [UInt8; 20] = a0.bytes
                var k: Int = 0
                while k < 20 { bytes.append(a0Fixed[k]); k = k + 1 }

                // fee uint24 big-endian
                bytes.append(UInt8((f >> 16) & 0xFF))
                bytes.append(UInt8((f >> 8) & 0xFF))
                bytes.append(UInt8(f & 0xFF))

                // address 1
                let a1Fixed: [UInt8; 20] = a1.bytes
                k = 0
                while k < 20 { bytes.append(a1Fixed[k]); k = k + 1 }

                i = i + 1
            }
            return EVM.EVMBytes(value: bytes)
        }

        access(self) fun to20(_ b: [UInt8]): [UInt8; 20] {
            if b.length != 20 { panic("to20: need exactly 20 bytes") }
            return [
                b[0],  b[1],  b[2],  b[3],  b[4],
                b[5],  b[6],  b[7],  b[8],  b[9],
                b[10], b[11], b[12], b[13], b[14],
                b[15], b[16], b[17], b[18], b[19]
            ]
        }

        access(self) fun getPoolAddress(): EVM.EVMAddress {
            let res = self._call(
                to: self.factoryAddress,
                signature: "getPool(address,address,uint24)",
                args: [ self.tokenPath[0], self.tokenPath[1], UInt256(3000) ],
                gasLimit: 120_000,
                value: 0
            )!

            if res.status != EVM.Status.successful {
                return EVM.addressFromString("0x0000000000000000000000000000000000000000")
            }

            // ABI return is one 32-byte word; the last 20 bytes are the address
            let word = res.data as! [UInt8]
            if word.length < 32 { panic("getPool: invalid ABI word length") }

            let addrSlice = word.slice(from: 12, upTo: 32)   // 20 bytes
            let addrBytes: [UInt8; 20] = self.to20(addrSlice)

            return EVM.EVMAddress(bytes: addrBytes)
        }

        access(self) fun getMaxAmount(zeroForOne: Bool): UInt256 {
            let poolEVMAddress = self.getPoolAddress()
            let wordRadius = 2

            let coa = self.borrowCOA()
            //
            // --- Helpers (kept inside prepare to avoid top-level decls) ---
            //
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
            fun wordToIntN(_ w: [UInt8], _ nBits: Int): Int {
                let u = wordToUIntN(w, nBits)
                let signBit: UInt = UInt(1) << UInt(nBits - 1)
                if (u & signBit) != 0 {
                    let twoN: UInt = UInt(1) << UInt(nBits)
                    // Signed value = u - 2^n (do it in Int space to avoid UInt underflow)
                    return Int(u) - Int(twoN)
                }
                return Int(u)
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
            fun encode1Int(_ selector: [UInt8], _ v: Int, _ bits: Int): [UInt8] {
                var word: [UInt8] = []
                if v < 0 {
                    let twoN: UInt = UInt(1) << UInt(bits)
                    let uv: UInt = UInt(-v)
                    let comp: UInt = (twoN - uv) & (twoN - 1)
                    word = EVMAbiHelpers.abiWord(UInt256(comp))
                } else {
                    word = EVMAbiHelpers.abiWord(UInt256(UInt(v)))
                }
                return EVMAbiHelpers.buildCalldata(selector: selector, args: [EVMAbiHelpers.staticArg(word)])
            }
            fun amount0DeltaUp(_ sqrtA: UInt, _ sqrtB: UInt, _ L: UInt): UInt {
                // ceil( L * (sqrtB - sqrtA) * Q96 / (sqrtB*sqrtA) )
                let Q96: UInt = 0x1000000000000000000000000
                var lo: UInt = sqrtA
                var hi: UInt = sqrtB
                if lo > hi { lo = sqrtB; hi = sqrtA }
                let num1: UInt = L * Q96
                let num2: UInt = hi - lo
                let den:  UInt = hi * lo
                let prod: UInt = num1 * num2
                let q: UInt = prod / den
                let r: UInt = prod % den
                if r == 0 { return q }
                return q + 1
            }
            fun amount1DeltaUp(_ sqrtA: UInt, _ sqrtB: UInt, _ L: UInt): UInt {
                // ceil( L * (sqrtB - sqrtA) / Q96 )
                let Q96: UInt = 0x1000000000000000000000000
                var lo: UInt = sqrtA
                var hi: UInt = sqrtB
                if lo > hi { lo = sqrtB; hi = sqrtA }
                let diff: UInt = hi - lo
                let prod: UInt = L * diff
                let q: UInt = prod / Q96
                let r: UInt = prod % Q96
                if r == 0 { return q }
                return q + 1
            }
            fun tickToSqrtPriceX96(_ tick: Int): UInt {
                pre { tick >= -887272 && tick <= 887272: "tick out of bounds" }

                var atAbs: Int = tick
                if atAbs < 0 { atAbs = -atAbs }
                fun mulShift(_ x: UInt, _ c: UInt): UInt { return (x * c) >> 128 }
                var ratio: UInt = 0x100000000000000000000000000000000
                var at: UInt = UInt(atAbs)
                if (at & 0x1)     != 0 { ratio = mulShift(ratio, 0xfffcb933bd6fad37aa2d162d1a594001) }
                if (at & 0x2)     != 0 { ratio = mulShift(ratio, 0xfff97272373d413259a46990580e213a) }
                if (at & 0x4)     != 0 { ratio = mulShift(ratio, 0xfff2e50f5f656932ef12357cf3c7fdcc) }
                if (at & 0x8)     != 0 { ratio = mulShift(ratio, 0xffe5caca7e10e4e61c3624eaa0941cd0) }
                if (at & 0x10)    != 0 { ratio = mulShift(ratio, 0xffcb9843d60f6159c9db58835c926644) }
                if (at & 0x20)    != 0 { ratio = mulShift(ratio, 0xff973b41fa98c081472e6896dfb254c0) }
                if (at & 0x40)    != 0 { ratio = mulShift(ratio, 0xff2ea16466c96a3843ec78b326b52861) }
                if (at & 0x80)    != 0 { ratio = mulShift(ratio, 0xfe5dee046a99a2a811c461f1969c3053) }
                if (at & 0x100)   != 0 { ratio = mulShift(ratio, 0xfcbe86c7900a88aedcffc83b479aa3a4) }
                if (at & 0x200)   != 0 { ratio = mulShift(ratio, 0xf987a7253ac413176f2b074cf7815e54) }
                if (at & 0x400)   != 0 { ratio = mulShift(ratio, 0xf3392b0822b70005940c7a398e4b70f3) }
                if (at & 0x800)   != 0 { ratio = mulShift(ratio, 0xe7159475a2c29b7443b29c7fa6e889d9) }
                if (at & 0x1000)  != 0 { ratio = mulShift(ratio, 0xd097f3bdfd2022b8845ad8f792aa5825) }
                if (at & 0x2000)  != 0 { ratio = mulShift(ratio, 0xa9f746462d870fdf8a65dc1f90e061e5) }
                if (at & 0x4000)  != 0 { ratio = mulShift(ratio, 0x70d869a156d2a1b890bb3df62baf32f7) }
                if (at & 0x8000)  != 0 { ratio = mulShift(ratio, 0x31be135f97d08fd981231505542fcfa6) }
                if (at & 0x10000) != 0 { ratio = mulShift(ratio, 0x9aa508b5b7a84e1c677de54f3e99bc9) }
                if (at & 0x20000) != 0 { ratio = mulShift(ratio, 0x5d6af8dedb81196699c329225ee604) }
                if (at & 0x40000) != 0 { ratio = mulShift(ratio, 0x2216e584f5fa1ea926041bedfe98) }
                if (at & 0x80000) != 0 { ratio = mulShift(ratio, 0x48a170391f7dc42444e8fa2) }
                if tick > 0 {
                    let MAX256: UInt = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                    ratio = MAX256 / ratio
                }
                let hi: UInt = ratio >> 32
                let remMask: UInt = (UInt(1) << 32) - 1
                let hasRem: Bool = (ratio & remMask) != 0
                if hasRem { return hi + 1 }
                return hi
            }

            // ticks: array of {"tick": Int, "liqNet": Int}
            fun maxInputBeforeDryNoStruct(
                _ sqrtPriceX96Raw: UInt,
                _ currentTick: Int,
                _ L0: UInt,
                _ feePpm: UInt,
                _ ticks: [{String: Int}],
                _ zeroForOne: Bool
            ): UInt {
                var sqrtP: UInt = sqrtPriceX96Raw
                var L: UInt = L0
                let oneMillion: UInt = 1_000_000

                if ticks.length == 0 || L == 0 { return 0 }

                // find first tick to cross
                var idx: Int = -1
                var i: Int = 0
                if zeroForOne {
                    var best: Int? = nil
                    while i < ticks.length {
                        let t = ticks[i]
                        let tTick = t["tick"]!
                        if tTick < currentTick && (best == nil || tTick > best!) { best = tTick; idx = i }
                        i = i + 1
                    }
                } else {
                    var best: Int? = nil
                    while i < ticks.length {
                        let t = ticks[i]
                        let tTick = t["tick"]!
                        if tTick > currentTick && (best == nil || tTick < best!) { best = tTick; idx = i }
                        i = i + 1
                    }
                }
                if idx < 0 { return 0 }

                var grossInSum: UInt = 0
                var steps: Int = 0

                while idx >= 0 && idx < ticks.length {
                    let t = ticks[idx]
                    let tTick = t["tick"]!
                    let liqNet = t["liqNet"]!
                    let sqrtNext: UInt = tickToSqrtPriceX96(tTick)

                    if zeroForOne {
                        if !(sqrtNext < sqrtP) { idx = idx - 1; continue }
                        let netIn: UInt = amount0DeltaUp(sqrtNext, sqrtP, L)
                        let grossIn: UInt = (netIn * oneMillion + (oneMillion - feePpm - 1)) / (oneMillion - feePpm)
                        grossInSum = grossInSum + grossIn
                        sqrtP = sqrtNext
                        if liqNet > 0 { L = L - UInt(liqNet) } else if liqNet < 0 { L = L + UInt(-liqNet) }
                        if L == 0 { break }
                        idx = idx - 1
                    } else {
                        if !(sqrtNext > sqrtP) { idx = idx + 1; continue }
                        let netIn: UInt = amount1DeltaUp(sqrtP, sqrtNext, L)
                        let grossIn: UInt = (netIn * oneMillion + (oneMillion - feePpm - 1)) / (oneMillion - feePpm)
                        grossInSum = grossInSum + grossIn
                        sqrtP = sqrtNext
                        if liqNet > 0 { L = L + UInt(liqNet) } else if liqNet < 0 { L = L - UInt(-liqNet) }
                        if L == 0 { break }
                        idx = idx + 1
                    }

                    steps = steps + 1
                    if steps > 100_000 { break }
                }

                return grossInSum
            }

            // discover initialized ticks via tickBitmap/ticks around current word
            fun getPopulatedTicksViaBitmap(
                _ pool: EVM.EVMAddress,
                _ currentTick: Int,
                _ tickSpacing: Int,
                _ wordRadius: Int,
                _ SEL_TICK_BITMAP: [UInt8],
                _ SEL_TICKS: [UInt8]
            ): [{String: Int}] {

                fun compressed(_ t: Int, _ spacing: Int): Int {
                    let q = t / spacing
                    if t >= 0 || t % spacing == 0 { return q }
                    return q - 1 // floor toward -inf
                }
                fun evmCallBytes(_ to: EVM.EVMAddress, _ data: [UInt8]): [UInt8] {
                    let res: EVM.Result? = self._callRaw(
                        to: to,
                        calldata: data,
                        gasLimit: 1_500_000,
                        value: 0
                    )
                    return res!.data
                }

                let comp: Int = compressed(currentTick, tickSpacing)
                let baseWord: Int = comp >> 8 // 256 ticks per word

                var result: [{String: Int}] = []
                var w = -wordRadius
                while w <= wordRadius {
                    let wordIndex = baseWord + w

                    // tickBitmap(int16)
                    let tbData = evmCallBytes(pool, encode1Int(SEL_TICK_BITMAP, wordIndex, 16))
                    let tbWord = wordToUInt(words(tbData)[0])
                    if tbWord != 0 {
                        var bit: Int = 0
                        while bit < 256 {
                            let mask: UInt = UInt(1) << UInt(bit)
                            if (tbWord & mask) != 0 {
                                let tickIndex: Int = (wordIndex << 8) + bit
                                let popped: Int = tickIndex * tickSpacing

                                // ticks(int24)
                                let txBytes = evmCallBytes(pool, encode1Int(SEL_TICKS, popped, 24))
                                let ws = words(txBytes)
                                let liqGross = wordToUIntN(ws[0], 128)
                                let liqNet   = wordToIntN(ws[1], 128)
                                if liqGross != 0 {
                                    result.append({ "tick": popped, "liqNet": liqNet })
                                }
                            }
                            bit = bit + 1
                        }
                    }
                    w = w + 1
                }

                // insertion sort by tick ASC
                var i = 1
                while i < result.length {
                    let key = result[i]
                    var j = i - 1
                    while j >= 0 && result[j]["tick"]! > key["tick"]! {
                        result[j + 1] = result[j]
                        j = j - 1
                    }
                    result[j + 1] = key
                    i = i + 1
                }

                return result
            }

            //
            // --- Selectors (locals, not top-level) ---
            //
            let SEL_SLOT0: [UInt8]        = [0x38, 0x50, 0xc7, 0xbd]
            let SEL_LIQUIDITY: [UInt8]    = [0x1a, 0x68, 0x65, 0x02]
            let SEL_FEE: [UInt8]          = [0xdd, 0xca, 0x3f, 0x43]
            let SEL_TICK_BITMAP: [UInt8]  = [0x53, 0x39, 0xc2, 0x96]
            let SEL_TICKS: [UInt8]        = [0xf3, 0x0d, 0xba, 0x93]
            let SEL_TICK_SPACING: [UInt8] = [0xd0, 0xc9, 0x3a, 0x7c]

            //
            // --- Borrow COA & make calls ---
            //

            // slot0()
            let s0Res: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_SLOT0, args: []),
                gasLimit: 1_000_000,
                value: 0
            )
            let s0w = words(s0Res!.data)
            let sqrtPriceX96 = wordToUIntN(s0w[0], 160)
            let tick         = wordToIntN(s0w[1], 24)

            // liquidity()
            let liqRes: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_LIQUIDITY, args: []),
                gasLimit: 300_000,
                value: 0
            )
            let L  = wordToUIntN(words(liqRes!.data)[0], 128)

            // fee() (ppm)
            let feeRes: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_FEE, args: []),
                gasLimit: 300_000,
                value: 0
            )
            let feePpm = wordToUIntN(words(feeRes!.data)[0], 24)

            // tickSpacing()
            let tsRes: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_TICK_SPACING, args: []),
                gasLimit: 300_000,
                value: 0
            )
            let tickSpacing = Int(wordToIntN(words(tsRes!.data)[0], 24))

            // Collect initialized ticks (±wordRadius words)
            let ticks = getPopulatedTicksViaBitmap(
                poolEVMAddress, tick, tickSpacing, wordRadius,
                SEL_TICK_BITMAP, SEL_TICKS
            )

            // Compute amount
            let amount = maxInputBeforeDryNoStruct(
                sqrtPriceX96, tick, L, feePpm, ticks, zeroForOne
            )

            return UInt256(amount / 10 * 9)
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

            let ercAddr = reverse
                ? (out ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1])
                : (out ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0])

            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintAmt, erc20Address: ercAddr)
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
            let inToken = reverse ? self.tokenPath[self.tokenPath.length - 1] : self.tokenPath[0]
            let outToken = reverse ? self.tokenPath[0] : self.tokenPath[self.tokenPath.length - 1]

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

            // Slippage/min out on EVM units (adjust factor to your policy)
            let slippage = 0.01 // 1%
            let minOutUint = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                amountOutMin * (1.0 - slippage),
                erc20Address: outToken
            )

            // exactInput((bytes,address,uint256,uint256)) selector = 0xb858183f
            let selector: [UInt8] = [0xb8, 0x58, 0x18, 0x3f]

            let coaRef = self.borrowCOA()!
            let recipient: EVM.EVMAddress = coaRef.address()

            // optional dev guards
            let _chkIn  = EVMAbiHelpers.abiUInt256(evmAmountIn)
            let _chkMin = EVMAbiHelpers.abiUInt256(minOutUint)
            //panic("path: \(EVMAbiHelpers.toHex(pathBytes.value)), amountIn: \(evmAmountIn.toString()), amountOutMin: \(minOutUint.toString())")
            assert(_chkIn.length == 32,  message: "amountIn not 32 bytes")
            assert(_chkMin.length == 32, message: "amountOutMin not 32 bytes")

            // 1) Build the tuple blob (you already have this)
            let argsBlob: [UInt8] = UniswapV3SwapConnectors.encodeTuple_bytes_addr_u256_u256(
                path: pathBytes.value,
                recipient: recipient,
                amountOne: evmAmountIn,
                amountTwo: minOutUint
            )

            // 2) Head for a single dynamic arg is always 32
            let head: [UInt8] = EVMAbiHelpers.abiWord(UInt256(32))

            // 3) Final calldata = selector || head || tuple
            let calldata: [UInt8] = selector.concat(head).concat(argsBlob)


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

             // Withdraw output back to Flow
             let outVault <- coa.withdrawTokens(type: self.outType(), amount: amountOut, feeProvider: feeVaultRef)

             // Handle leftover fee vault
             self._handleRemainingFeeVault(<-feeVault)
             return <- outVault
        }

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
            ("Call to ".concat(target.toString())
                .concat(".")
                .concat(signature)
                .concat(" from Swapper ")
                .concat(swapperType.identifier)
                .concat(" with UniqueIdentifier ")
                .concat(uniqueIDType)
                .concat(" ID ")
                .concat(id)
                .concat(" failed:\n\t"))
            .concat("Status value: ".concat(res.status.rawValue.toString()).concat("\n\t"))
            .concat("Error code: ".concat(res.errorCode.toString()).concat("\n\t"))
            .concat("ErrorMessage: ".concat(res.errorMessage).concat("\n"))
        )
    }
}
