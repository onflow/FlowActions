import "FungibleToken"
import "Burner"

import "SwapRouter"
import "SwapStack"
import "DFB"

/// IncrementFiAdapters
///
/// DeFi adapter implementations fitting IncrementFi protocols to the data structure defined in DeFiAdapters.
///
access(all) contract IncrementFiAdapters {

    /// An implementation of DFB.Swapper connector that swaps between tokens using IncrementFi's
    /// SwapRouter contract
    ///
    access(all) struct Swapper : DFB.Swapper {
        /// A swap path as defined by IncrementFi's SwapRouter
        ///  e.g. [A.f8d6e0586b0a20c7.FUSD, A.f8d6e0586b0a20c7.FlowToken, A.f8d6e0586b0a20c7.USDC]
        access(all) let path: [String]
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) let uniqueID: {DFB.UniqueIdentifier}?
        /// The pre-conversion currency accepted for a swap
        access(self) let inVault: Type
        /// The post-conversion currency returned by a swap
        access(self) let outVault: Type

        init(
            path: [String],
            inVault: Type,
            outVault: Type,
            uniqueID: {DFB.UniqueIdentifier}?
        ) {
            pre {
                path.length >= 2:
                "Provided path must have a length of at least 2 - provided path has \(path.length) elements"
            }
            IncrementFiAdapters.validateSwapperInitArgs(path: path, inVault: inVault, outVault: outVault)

            self.path = path
            self.inVault = inVault
            self.outVault = outVault
            self.uniqueID = uniqueID
        }

        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inVaultType(): Type {
            return self.inVault
        }
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outVaultType(): Type {
            return self.outVault
        }
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun amountIn(forDesired: UFix64, reverse: Bool): {DFB.Quote} {
            let amountsIn = SwapRouter.getAmountsIn(amountOut: forDesired, tokenKeyPath: reverse ? self.path.reverse() : self.path)
            return SwapStack.BasicQuote(
                inVault: reverse ? self.outVaultType() : self.inVaultType(),
                outVault: reverse ? self.inVaultType() : self.outVaultType(),
                inAmount: amountsIn.length == 0 ? 0.0 : amountsIn[0],
                outAmount: forDesired
            )
        }
        /// The estimated amount delivered out for a provided input balance
        access(all) fun amountOut(forProvided: UFix64, reverse: Bool): {DFB.Quote} {
            let amountsOut = SwapRouter.getAmountsOut(amountIn: forProvided, tokenKeyPath: reverse ? self.path.reverse() : self.path)
            return SwapStack.BasicQuote(
                inVault: reverse ? self.outVaultType() : self.inVaultType(),
                outVault: reverse ? self.inVaultType() : self.outVaultType(),
                inAmount: forProvided,
                outAmount: amountsOut.length == 0 ? 0.0 : amountsOut[amountsOut.length - 1]
            )
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(quote: {DFB.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOut = self.amountOut(forProvided: inVault.balance, reverse: false).outAmount
            return <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-inVault,
                amountOutMin: amountOut,
                tokenKeyPath: self.path,
                deadline: getCurrentBlock().timestamp
            )
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(quote: {DFB.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOut = self.amountOut(forProvided: residual.balance, reverse: true).outAmount
            return <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-residual,
                amountOutMin: amountOut,
                tokenKeyPath: self.path.reverse(),
                deadline: getCurrentBlock().timestamp
            )
        }
    }

    /// Reverts if the in and out Vaults are not defined by the token key path identifiers as used by IncrementFi's
    /// SwapRouter. Notably does not validate the intermediary path values if there are any.
    ///
    access(self)
    view fun validateSwapperInitArgs(
        path: [String],
        inVault: Type,
        outVault: Type
    ) {
        // ensure the path in and out identifiers are consistent with the defined in and out Vault types
        let inIdentifier = path[0]
        let outIdentifier = path[path.length - 1]
        let inSplit = inIdentifier.split(separator: ".")
        let outSplit = outIdentifier.split(separator: ".")
        assert(inSplit.length == 3, message: "Unknown IncrementFi path identifier at path[0] \(inIdentifier)")
        assert(inSplit.length == 3, message: "Unknown IncrementFi path identifier at path[\(path.length - 1)] \(outIdentifier)")

        // compare the defining contract address and name with the in and out Vault types
        let inAddress = inSplit[1]
        let outAddress = outSplit[1]
        let inContract = inSplit[2]
        let outContract = outSplit[2]
        assert("0x\(inAddress)" == inVault.address!.toString(),
            message: "Mismatching contract address for inVault - path defines 0x\(inAddress) but inVault defined by \(inVault.address!.toString())")
        assert("0x\(outAddress)" == outVault.address!.toString(),
            message: "Mismatching contract address for outVault - path defines 0x\(outAddress) but outVault defined by \(outVault.address!.toString())")
        assert(inContract == inVault.contractName!,
            message: "Mismatching contract address for inVault - path defines 0x\(inAddress) but inVault defined by \(inVault.address!.toString())")
        assert(outContract == outVault.contractName!,
            message: "Mismatching contract address for inVault - path defines 0x\(inAddress) but inVault defined by \(inVault.address!.toString())")
    }
}
