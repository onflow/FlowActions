import "FungibleToken"
import "Burner"

import "SwapInterfaces"
import "SwapConfig"
import "SwapFactory"
import "SwapRouter"
import "SwapConnectors"
import "DeFiActions"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// IncrementFiSwapConnectors
///
/// DeFiActions adapter implementations fitting IncrementFi protocols to the data structure defined in DeFiActions.
///
access(all) contract IncrementFiSwapConnectors {

    /// Swapper
    ///
    /// A DeFiActions connector that swaps between tokens using IncrementFi's SwapRouter contract
    ///
    access(all) struct Swapper : DeFiActions.Swapper {
        /// A swap path as defined by IncrementFi's SwapRouter
        ///  e.g. [A.f8d6e0586b0a20c7.FUSD, A.f8d6e0586b0a20c7.FlowToken, A.f8d6e0586b0a20c7.USDC]
        access(all) let path: [String]
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        /// The pre-conversion currency accepted for a swap
        access(self) let inVault: Type
        /// The post-conversion currency returned by a swap
        access(self) let outVault: Type

        init(
            path: [String],
            inVault: Type,
            outVault: Type,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                path.length >= 2:
                "Provided path must have a length of at least 2 - provided path has \(path.length) elements"
            }
            IncrementFiSwapConnectors._validateSwapperInitArgs(path: path, inVault: inVault, outVault: outVault)

            self.path = path
            self.inVault = inVault
            self.outVault = outVault
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this Swapper and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
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
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let amountsIn = SwapRouter.getAmountsIn(amountOut: forDesired, tokenKeyPath: reverse ? self.path.reverse() : self.path)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountsIn.length == 0 ? 0.0 : amountsIn[0],
                outAmount: forDesired
            )
        }
        /// The estimated amount delivered out for a provided input balance
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let amountsOut = SwapRouter.getAmountsOut(amountIn: forProvided, tokenKeyPath: reverse ? self.path.reverse() : self.path)
            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: forProvided,
                outAmount: amountsOut.length == 0 ? 0.0 : amountsOut[amountsOut.length - 1]
            )
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOut = self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
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
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let amountOut = self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
            return <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-residual,
                amountOutMin: amountOut,
                tokenKeyPath: self.path.reverse(),
                deadline: getCurrentBlock().timestamp
            )
        }
    }

    /* --- INTERNAL HELPERS --- */

    /// Reverts if the in and out Vaults are not defined by the token key path identifiers as used by IncrementFi's
    /// SwapRouter. Notably does not validate the intermediary path values if there are any.
    ///
    access(self)
    view fun _validateSwapperInitArgs(
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
