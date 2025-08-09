import "FungibleToken"
import "DeFiActions"
import "SwapInterfaces"
import "SwapConfig"
import "SwapFactory"

access(all) contract IncrementFiFlashloanConnectors {

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
}