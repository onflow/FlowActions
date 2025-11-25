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

        access(self) let maxPriceImpactBps: UInt

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
            maxPriceImpactBps: UInt?
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
                maxPriceImpactBps == nil || (maxPriceImpactBps! > 0 && maxPriceImpactBps! <= 5000):
                    "maxPriceImpactBps must be between 1 and 5000 (0.01% to 50%)"
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
            self.maxPriceImpactBps = maxPriceImpactBps ?? 600  // Default to 6%
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
                args: [ self.tokenPath[0], self.tokenPath[1], UInt256(self.feePath[0]) ],
                gasLimit: 120_000,
                value: 0
            )!
            assert(res.status == EVM.Status.successful, message: "unable to get pool: token0 \(self.tokenPath[0].toString()), token1 \(self.tokenPath[1].toString()), feePath: self.feePath[0]")

            // if res.status != EVM.Status.successful {
            //     return EVM.addressFromString("0x0000000000000000000000000000000000000000")
            // }

            // ABI return is one 32-byte word; the last 20 bytes are the address
            let word = res.data as! [UInt8]
            if word.length < 32 { panic("getPool: invalid ABI word length") }

            let addrSlice = word.slice(from: 12, upTo: 32)   // 20 bytes
            let addrBytes: [UInt8; 20] = self.to20(addrSlice)

            return EVM.EVMAddress(bytes: addrBytes)
        }

        /// Simplified getMaxAmount using configurable price impact
        /// Uses current liquidity as proxy for max swappable amount
        /// Price impact is configurable via maxPriceImpactBps (in basis points)
        access(self) fun getMaxAmount(zeroForOne: Bool): UInt256 {
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
            let s0Res: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_SLOT0, args: []),
                gasLimit: 1_000_000,
                value: 0
            )
            let s0w = words(s0Res!.data)
            let sqrtPriceX96 = wordToUIntN(s0w[0], 160)
            
            // Get current active liquidity
            let liqRes: EVM.Result? = self._callRaw(
                to: poolEVMAddress,
                calldata: EVMAbiHelpers.buildCalldata(selector: SEL_LIQUIDITY, args: []),
                gasLimit: 300_000,
                value: 0
            )
            let L = wordToUIntN(words(liqRes!.data)[0], 128)
            
            // Calculate price multiplier based on maxPriceImpactBps
            // Use UInt256 throughout to prevent overflow in multiplication operations
            let bps: UInt256 = UInt256(self.maxPriceImpactBps)
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
                let numerator: UInt256 = L_256 * deltaSqrt
                maxAmount = (numerator * Q96) / sqrtPriceX96_256 / sqrtPriceNew
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
