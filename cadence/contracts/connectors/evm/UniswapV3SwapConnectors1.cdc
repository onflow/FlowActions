import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "FlowEVMBridge"

import "DeFiActions"
import "SwapConnectors"

/// UniswapV3SwapConnectors
///
/// DeFiActions Swapper connector implementation for Uniswap V3-style swaps.
/// Supports single- and multi-hop via a path of token addresses + per-hop fee tiers.
access(all) contract UniswapV3SwapConnectors1 {

    /// Swapper
    ///
    /// Swaps between tokens using a Uniswap V3 ISwapRouter-compatible contract on Flow EVM.
    access(all) struct Swapper : DeFiActions.Swapper {
        /// ISwapRouter EVM address
        access(all) let routerAddress: EVM.EVMAddress
        /// Quoter EVM address (Quoter or QuoterV2). We only rely on the `quoteExactInput(bytes)` / `quoteExactOutput(bytes,uint256)` ABI.
        access(all) let quoterAddress: EVM.EVMAddress
        /// Token address path (tokenIn -> ... -> tokenOut)
        access(all) let addressPath: [EVM.EVMAddress]
        /// Per-hop V3 fee tiers (in hundredths of a bip; e.g. 500, 3000, 10000). Length must be addressPath.length - 1
        access(all) let feePath: [UInt32]

        /// Optional identifier for stack alignment
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Pre-/post- conversion Flow types bound to the token addresses at the ends of the path
        access(self) let inVault: Type
        access(self) let outVault: Type

        /// Authorized COA capability used for EVM calls/transfers
        access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

        init(
            routerAddress: EVM.EVMAddress,
            quoterAddress: EVM.EVMAddress,
            path: [EVM.EVMAddress],
            fees: [UInt32],
            inVault: Type,
            outVault: Type,
            coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                path.length >= 2: "V3 path needs >= 2 token addresses"
                fees.length == path.length - 1: "feePath length must equal addressPath length - 1"
                FlowEVMBridgeConfig.getTypeAssociated(with: path[0]) == inVault:
                    "Provided inVault not associated with ERC20 at path[0] – check bridge type associations"
                FlowEVMBridgeConfig.getTypeAssociated(with: path[path.length - 1]) == outVault:
                    "Provided outVault not associated with ERC20 at last hop – check bridge type associations"
                coaCapability.check():
                    "Invalid COA Capability – provide an active Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>"
            }
            self.routerAddress = routerAddress
            self.quoterAddress = quoterAddress
            self.addressPath = path
            self.feePath = fees
            self.uniqueID = uniqueID
            self.inVault = inVault
            self.outVault = outVault
            self.coaCapability = coaCapability
        }

        /* ---------- DeFiActions.Swapper conformance ---------- */

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.uniqueID?.id,
                innerComponents: []
            )
        }

        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        access(all) view fun inType(): Type { 
            return self.inVault
        }
        access(all) view fun outType(): Type {
            return self.outVault
        }

        /// Quote amount *in* required for a desired *out* (uses Quoter.exactOutput)
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let inT  = reverse ? self.outType() : self.inType()
            let outT = reverse ? self.inType() : self.outType()
            let pathBytes = self.encodeV3Path(reverse: reverse)
            let desiredOutUInt = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forDesired,
                erc20Address: reverse ? self.addressPath[0] : self.addressPath[self.addressPath.length - 1]
            )

            let amountIn: UFix64? = self.quoterExactOutput(path: pathBytes, amountOut: desiredOutUInt)
            return SwapConnectors.BasicQuote(
                inType: inT,
                outType: outT,
                inAmount: amountIn ?? 0.0,
                outAmount: amountIn != nil ? forDesired : 0.0
            )
        }

        /// Quote amount *out* given a provided *in* (uses Quoter.exactInput)
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let inT  = reverse ? self.outType() : self.inType()
            let outT = reverse ? self.inType() : self.outType()
            let pathBytes = self.encodeV3Path(reverse: reverse)
            let providedUInt = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forProvided,
                erc20Address: reverse ? self.addressPath[self.addressPath.length - 1] : self.addressPath[0]
            )

            let amountOut: UFix64? = self.quoterExactInput(path: pathBytes, amountIn: providedUInt)
            return SwapConnectors.BasicQuote(
                inType: inT,
                outType: outT,
                inAmount: amountOut != nil ? forProvided : 0.0,
                outAmount: amountOut ?? 0.0
            )
        }

        /// Swap in -> out using V3 exactInput
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let minOut = quote?.outAmount ?? self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
            return <- self.v3ExactInputSwap(exactVaultIn: <-inVault, amountOutMin: minOut, reverse: false)
        }

        /// Swap back out -> in using V3 exactInput on the reversed path
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let minOut = quote?.outAmount ?? self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
            return <- self.v3ExactInputSwap(exactVaultIn: <-residual, amountOutMin: minOut, reverse: true)
        }

        /* ---------- V3 implementation ---------- */

        /// Perform exactInput using a V3 path (bytes) built from addressPath/feePath
        access(self)
        fun v3ExactInputSwap(
            exactVaultIn: @{FungibleToken.Vault},
            amountOutMin: UFix64,
            reverse: Bool
        ): @{FungibleToken.Vault} {
            let id = self.uniqueID?.id?.toString() ?? "UNASSIGNED"
            let idType = self.uniqueID?.getType()?.identifier ?? "UNASSIGNED"
            let coa = self.borrowCOA()
                ?? panic("COA Capability invalid for Swapper \(self.getType().identifier) \(idType):\(id)")

            // Bridge fee (to EVM and back)
            let feeBal = EVM.Balance(attoflow: 0)
            feeBal.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256))
            let feeVault <- coa.withdraw(balance: feeBal)
            let feeRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

            // Determine tokenIn address wrt direction
            let tokenIn = reverse ? self.addressPath[self.addressPath.length - 1] : self.addressPath[0]
            let tokenOut = reverse ? self.addressPath[0] : self.addressPath[self.addressPath.length - 1]

            // Convert amountIn to ERC20 units & deposit tokens to EVM
            let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                exactVaultIn.balance,
                erc20Address: tokenIn
            )
            coa.depositTokens(vault: <-exactVaultIn, feeProvider: feeRef)

            // Approve router
            var res = self.call(
                to: tokenIn,
                signature: "approve(address,uint256)",
                args: [self.routerAddress, evmAmountIn],
                gasLimit: 120_000,
                value: 0,
                dryCall: false
            )!
            if res.status != EVM.Status.successful {
                UniswapV3SwapConnectors1._callError("approve(address,uint256)", res, tokenIn, idType, id, self.getType())
            }

            // Build V3 path (bytes)
            let pathBytes: [UInt8] = self.encodeV3Path(reverse: reverse)

            // exactInput params tuple: (bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum)
            // ABI signature uses tuple: exactInput((bytes,address,uint256,uint256,uint256))
            let deadline: UInt256 = UInt256(getCurrentBlock().timestamp)
            let minOutUInt = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(amountOutMin, erc20Address: tokenOut)
            let paramsTuple: [AnyStruct] = [pathBytes, coa.address(), deadline, evmAmountIn, minOutUInt]

            res = self.call(
                to: self.routerAddress,
                signature: "exactInput((bytes,address,uint256,uint256,uint256))",
                args: [paramsTuple],
                gasLimit: 1_200_000,
                value: 0,
                dryCall: false
            )!
            if res.status != EVM.Status.successful {
                UniswapV3SwapConnectors1._callError("exactInput((bytes,address,uint256,uint256,uint256))",
                    res, self.routerAddress, idType, id, self.getType())
            }

            // exactInput returns amountOut (uint256). We ignore here; we’ll withdraw all received tokenOut anyway.
            // Withdraw tokenOut from EVM back to Cadence
            let outVault <- coa.withdrawTokens(
                type: reverse ? self.inType() : self.outType(),
                amount: FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount( // request "all" by passing the on-chain balance seen by bridge:
                    FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount( // decode from result for precision; fallback to bridge balance if needed
                        (EVM.decodeABI(types: [Type<UInt256>()], data: res.data)[0] as! UInt256),
                        erc20Address: tokenOut
                    ),
                    erc20Address: tokenOut
                ),
                feeProvider: feeRef
            )

            self.handleRemainingFeeVault(<-feeVault)
            return <- outVault
        }

        /* ---------- Quoter helpers ---------- */

        /// Quoter: exact input amount -> output
        access(self) fun quoterExactInput(path: [UInt8], amountIn: UInt256): UFix64? {
            // Prefer QuoterV2's quoteExactInput(bytes) which returns (uint256 amountOut, ...),
            // but Quoter's quoteExactInput(bytes) also returns a single uint256.
            let res = self.call(
                to: self.quoterAddress,
                signature: "quoteExactInput(bytes,uint256)",
                args: [path, amountIn],
                gasLimit: 1_000_000,
                value: 0,
                dryCall: true
            )
            if res == nil || res!.status != EVM.Status.successful { return nil }

            // Try decode single uint256 first; if V2, it’s the first field of a tuple/struct.
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res!.data)
            if decoded != nil && decoded!.length > 0 {
                let uintOut = decoded![0] as! UInt256
                return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintOut, erc20Address: self.addressPath[self.addressPath.length - 1])
            }

            // Fallback: decode tuple with first field uint256
            let decoded2 = EVM.decodeABI(types: [Type<UInt256>(), Type<[UInt256]>(), Type<[Int256]>(), Type<UInt256>()], data: res!.data)
            let amountOut = decoded2[0] as! UInt256
            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(amountOut, erc20Address: self.addressPath[self.addressPath.length - 1])
        }

        /// Quoter: exact output amount -> required input
        access(self) fun quoterExactOutput(path: [UInt8], amountOut: UInt256): UFix64? {
            // Note: for exactOutput the path must be reversed (tokenOut->...->tokenIn) in canonical Uniswap contracts.
            // We pass the already-correct direction from caller via encodeV3Path(reverse: X) when needed.
            let res = self.call(
                to: self.quoterAddress,
                signature: "quoteExactOutput(bytes,uint256)",
                args: [path, amountOut],
                gasLimit: 1_000_000,
                value: 0,
                dryCall: true
            )
            if res == nil || res!.status != EVM.Status.successful { return nil }

            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res!.data)
            if decoded != nil && decoded!.length > 0 {
                let uintIn = decoded![0] as! UInt256
                return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(uintIn, erc20Address: self.addressPath[0])
            }

            let decoded2 = EVM.decodeABI(types: [Type<UInt256>(), Type<[UInt256]>(), Type<[Int256]>(), Type<UInt256>()], data: res!.data)
            let amountIn = decoded2[0] as! UInt256
            return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(amountIn, erc20Address: self.addressPath[0])
        }

        /* ---------- Path & utility helpers ---------- */

        /// Encode the V3 path as bytes: addr(20) | fee(3) | addr(20) | fee(3) | ... | addr(20)
        /// If reverse=true, we reverse both the addressPath and feePath ordering for out->in quotes/swaps.
        access(self) fun encodeV3Path(reverse: Bool): [UInt8] {
            let addrs: [EVM.EVMAddress] = reverse ? self.addressPath.reverse() : self.addressPath
            let fees:  [UInt32]         = reverse ? self.feePath.reverse()    : self.feePath

            var bytes: [UInt8] = []
            var i = 0
            while i < addrs.length {
                // EVMAddress is defined over exactly 20 bytes — use the .bytes field
                let addrBytes: [UInt8; 20] = addrs[i].bytes

                var j = 0
                while j < 20 {
                    bytes.append(addrBytes[j])
                    j = j + 1
                }

                if i < fees.length {
                    let fee = fees[i]           // e.g. 500, 3000, 10000
                    bytes.append(UInt8((fee >> 16) & 0xff))
                    bytes.append(UInt8((fee >> 8)  & 0xff))
                    bytes.append(UInt8(fee         & 0xff))
                }
                i = i + 1
            }
            return bytes
        }
        /// Deposits remainder fee vault back to COA or burns if empty
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

        /// Generic COA (dry)call wrapper
        access(self) fun call(
            to: EVM.EVMAddress,
            signature: String,
            args: [AnyStruct],
            gasLimit: UInt64,
            value: UInt,
            dryCall: Bool
        ): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBal = EVM.Balance(attoflow: value)
            if let coa = self.borrowCOA() {
                return dryCall
                    ? coa.dryCall(to: to, data: calldata, gasLimit: gasLimit, value: valueBal)
                    : coa.call(   to: to, data: calldata, gasLimit: gasLimit, value: valueBal)
            }
            return nil
        }
    }

    /// Standardized error reversion helper
    access(self)
    fun _callError(_ signature: String, _ res: EVM.Result, _ target: EVM.EVMAddress, _ uniqueIDType: String, _ id: String, _ swapperType: Type) {
        panic("Call to \(target.toString()).\(signature) from \(swapperType.identifier) with UniqueIdentifier \(uniqueIDType) ID \(id) failed: \n\t"
            .concat("Status: \(res.status.rawValue)\n\t")
            .concat("Error code: \(res.errorCode)\n\t")
            .concat("ErrorMessage: \(res.errorMessage)\n")
        )
    }
}
