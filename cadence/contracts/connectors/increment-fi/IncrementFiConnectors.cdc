import "FungibleToken"
import "Burner"

import "SwapInterfaces"
import "SwapConfig"
import "SwapFactory"
import "SwapRouter"
import "SwapStack"
import "DeFiActions"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// IncrementFiConnectors
///
/// DeFiActions adapter implementations fitting IncrementFi protocols to the data structure defined in DeFiActions.
///
access(all) contract IncrementFiConnectors {

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
            IncrementFiConnectors._validateSwapperInitArgs(path: path, inVault: inVault, outVault: outVault)

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
            return SwapStack.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: amountsIn.length == 0 ? 0.0 : amountsIn[0],
                outAmount: forDesired
            )
        }
        /// The estimated amount delivered out for a provided input balance
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let amountsOut = SwapRouter.getAmountsOut(amountIn: forProvided, tokenKeyPath: reverse ? self.path.reverse() : self.path)
            return SwapStack.BasicQuote(
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

    /// Flasher
    ///
    /// A DeFiActions connector that performs flash loans using IncrementFi's SwapPair contract
    ///
    access(all) struct Flasher : SwapInterfaces.FlashLoanExecutor, DeFiActions.Flasher {
        /// The address of the SwapPair contract to use for flash loans
        access(all) let pairAddress: Address
        /// The type of token to borrow
        access(all) let type: Type
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(pairAddress: Address, type: Type, uniqueID: DeFiActions.UniqueIdentifier?) {
            let pair = getAccount(pairAddress).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
                ?? panic("Could not reference SwapPair public capability at address \(pairAddress)")
            let pairInfo = pair.getPairInfoStruct()
            assert(pairInfo.token0Key == type.identifier || pairInfo.token1Key == type.identifier,
                message: "Provided type is not supported by the SwapPair at address \(pairAddress) - "
                    .concat("valid types for this SwapPair are \(pairInfo.token0Key) and \(pairInfo.token1Key)"))
            self.pairAddress = pairAddress
            self.type = type
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this Flasher and its inner DFA components
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
        /// Returns the asset type this Flasher can issue as a flash loan
        ///
        /// @return the type of token this Flasher can issue as a flash loan
        ///
        access(all) view fun borrowType(): Type {
            return self.type
        }
        /// Returns the estimated fee for a flash loan of the specified amount
        ///
        /// @param loanAmount: The amount of tokens to borrow
        /// @return the estimated fee for a flash loan of the specified amount
        ///
        access(all) fun calculateFee(loanAmount: UFix64): UFix64 {
            return UFix64(SwapFactory.getFlashloanRateBps()) * loanAmount / 10000.0
        }
        /// Performs a flash loan of the specified amount. The callback function is passed the fee amount, a Vault
        /// containing the loan, and the data. The callback function should return a Vault containing the loan + fee.
        ///
        /// @param amount: The amount of tokens to borrow
        /// @param data: Optional data to pass to the callback function
        /// @param callback: The callback function to use for the flash loan
        ///
        access(all) fun flashLoan(
            amount: UFix64,
            data: AnyStruct?,
            callback: fun(UFix64, @{FungibleToken.Vault}, AnyStruct?): @{FungibleToken.Vault} // fee, loan, data
        ) {
            // get the SwapPair public capability on which to perform the flash loan
            let pair = getAccount(self.pairAddress).capabilities.borrow<&{SwapInterfaces.PairPublic}>(
                    SwapConfig.PairPublicPath
                ) ?? panic("Could not reference SwapPair public capability at address \(self.pairAddress)")

            // cast data to expected params type and add fee and callback to params for the callback function
            let params = data as! {String: AnyStruct}? ?? {}
            params["fee"] = self.calculateFee(loanAmount: amount)
            params["callback"] = callback

            // perform the flash loan
            pair.flashloan(
                executor: &self as &{SwapInterfaces.FlashLoanExecutor},
                requestedTokenVaultType: self.type,
                requestedAmount: amount,
                params: params
            )
        }
        /// Performs a flash loan of the specified amount. The Flasher.flashLoan() callback function should be found in
        /// the params object passed to this function under the key "callback". The callback function is passed the fee
        /// amount, a Vault containing the loan, and the data. The callback function should return a Vault containing
        /// the loan + fee.
        access(all) fun executeAndRepay(loanedToken: @{FungibleToken.Vault}, params: {String: AnyStruct}): @{FungibleToken.Vault} {
            // cast params to expected types and execute the callback
            let fee = params.remove(key: "fee") as? UFix64 ?? panic("No fee provided in params to executeAndRepay")
            let callback = params.remove(key: "callback") as? fun(UFix64, @{FungibleToken.Vault}, AnyStruct?): @{FungibleToken.Vault}
                ?? panic("No callback function provided in params to executeAndRepay")

            // execute the callback logic
            let repaidToken <- callback(fee, <-loanedToken, params)

            // return the repaid token
            return <- repaidToken
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
