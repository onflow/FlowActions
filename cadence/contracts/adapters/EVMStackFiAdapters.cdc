import "FungibleToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"

import "DeFiAdapters"

/// EVMStackFiAdapters
///
/// DeFi adapter implementations fitting EVM-based DeFi protocols to the interfaces defined in DeFiAdapters. These
/// adapters are originally intended for use in StackFi components, but may have broader use cases.
///
access(all) contract EVMStackFiAdapters {

    /// Adapts an EVM-based UniswapV2Router contract methods to DeFiAdapters.UniswapV2SwapAdapter struct interface
    ///
    access(all) struct UniswapV2SwapAdapterSwapRouterAdapter : DeFiAdapters.UniswapV2SwapAdapter {
        access(all) let routerAddress: EVM.EVMAddress
        access(self) let coaCapability: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>

        init(
            routerAddress: EVM.EVMAddress,
            coaCapability: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
        ) {
            pre {
                coaCapability.check():
                "Provided COA Capability is invalid - provided an active, unrevoked Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>"
            }
            self.routerAddress = routerAddress
            self.coaCapability = coaCapability
        }

        /// Quotes the input amounts for some desired amount in along the provided path.
        /// NOTE: Cadence only supports decimal precision of 8
        ///
        /// @param amountOut: The desired post-conversion amout out
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        ///
        /// @return An array of input values for each step along the swap path
        ///
        access(all) fun getAmountsIn(amountOut: UFix64, path: [String]): [UFix64] {
            let _path = EVMStackFiAdapters.deserializePath(path)
            if let callRes = self.call(
                signature: "getAmountsIn(uint,address[])",
                args: [amountOut],
                gasLimit: 5_000_000,
                value: UInt(0),
                dryCall: true
            ) {
                if let amountsIn = EVM.decodeABI(types: [Type<UInt256>()], data: callRes.data) as? [UInt256] {
                    return EVMStackFiAdapters.convertEVMAmountsToCadenceAmounts(amountsIn, path: _path)
                }
            }
            return []
        }

        /// Quotes the output amounts for some amount in along the provided path
        ///
        /// @param amountIn: The input amount (in pre-conversion currency) available for the swap
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        ///
        /// @return An array of output values for each step along the swap path
        ///
        access(all) fun getAmountsOut(amountIn: UFix64, path: [String]): [UFix64] {
            let _path = EVMStackFiAdapters.deserializePath(path)
            if let callRes = self.call(
                signature: "getAmountsOut(uint,address[])",
                args: [amountIn],
                gasLimit: 5_000_000,
                value: UInt(0),
                dryCall: true
            ) {
                if let amountsOut = EVM.decodeABI(types: [Type<UInt256>()], data: callRes.data) as? [UInt256] {
                    return EVMStackFiAdapters.convertEVMAmountsToCadenceAmounts(amountsOut, path: _path)
                }
            }
            return []
        }

        /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
        /// returning the final output Vault
        ///
        /// @param exactVaultIn: The exact balance to swap as pre-converted currency
        /// @param amountOutMin: The minimum output balance expected as post-converted currency, useful for slippage
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        /// @param deadline: The block timestamp beyond which the swap should not execute
        ///
        /// @return The requested post-conversion currency
        ///
        access(all) fun swapExactTokensForTokens(
            exactVaultIn: @{FungibleToken.Vault},
            amountOutMin: UFix64,
            path: [String],
            deadline: UFix64
        ): @{FungibleToken.Vault} {
            panic("TODO")
        }

        /// Port of UniswapV2Router.swapTokensForExactTokens swapping the funds provided for exact output along the
        /// given path, returning the final output Vault as well as any remainder of the original input Vault
        ///
        /// @param exactAmountOut: The exact desired balance to expect as a swap output
        /// @param vaultInMax: The maximum balance to use as pre-converted currency, useful for slippage
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        /// @param deadline: The block timestamp beyond which the swap should not execute
        ///
        /// @return A two item array containing the output vault and the remainder of the provided Vault
        ///
        access(all) fun swapTokensForExactTokens(
            exactAmountOut: UFix64,
            vaultInMax: @{FungibleToken.Vault},
            path: [String],
            deadline: UFix64
        ): @[{FungibleToken.Vault}; 2] {
            panic("TODO")
        }

        access(self) view fun borrowCOA(): auth(EVM.Call) &EVM.CadenceOwnedAccount? {
            return self.coaCapability.borrow()
        }

        access(self) fun call(
            signature: String,
            args: [AnyStruct],
            gasLimit: UInt64,
            value: UInt,
            dryCall: Bool
        ): EVM.Result? {
            let calldata = EVM.encodeABIWithSignature(signature, args)
            let valueBalance = EVM.Balance(attoflow: value)
            if let coa = self.borrowCOA() {
                let res: EVM.Result = dryCall ? coa.dryCall(to: self.routerAddress, data: calldata, gasLimit: gasLimit, value: valueBalance)
                    : coa.call(to: self.routerAddress, data: calldata, gasLimit: gasLimit, value: valueBalance)
                return res.status == EVM.Status.successful ? res : nil
            }
            return nil
        }
    }

    access(self)
    fun deserializePath(_ path: [String]): [EVM.EVMAddress] {
        let _path: [EVM.EVMAddress] = []
        for hop in path {
            _path.append(EVM.addressFromString(hop))
        }
        return  _path
    }

    access(all)
    fun convertEVMAmountsToCadenceAmounts(_ amounts: [UInt256], path: [EVM.EVMAddress]): [UFix64] {
        let convertedAmounts: [UFix64]= []
        for i, amount in amounts {
            convertedAmounts.append(FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(amount, erc20Address: path[i]))
        }
        return convertedAmounts
    }

    /// Helper to transform the provided nested resource array to an one of constant size containing two Vaults. This is
    /// required for conformance to DeFiAdapters.UniswapV2SwapAdapter.swapTokensForExactTokens and due to the fact that
    /// the Cadence method [<T>].toConstantSized<[T, n]>() does not operate on nested resource arrays.
    ///
    access(self)
    fun toConstantSizedDoubleVaultArray(_ vaultArray: @[{FungibleToken.Vault}]): @[{FungibleToken.Vault}; 2] {
        pre {
            vaultArray.length == 2:
            "Expected vaultArray.length == 2 but was given vaultArray.length == \(vaultArray.length)"
        }
        // reference the nested Vaults
        let outVaultRef = (&vaultArray[0] as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        let remainderVaultRef = &vaultArray[1]  as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        // build the constant-sized array by withdrawing the full balance of each inner Vault
        let constantSizeOut: @[{FungibleToken.Vault}; 2] <- [
                <- outVaultRef.withdraw(amount: outVaultRef.balance),
                <- remainderVaultRef.withdraw(amount: remainderVaultRef.balance)
            ]

        // with inner Vault's empty, burn the nested resource array & burn
        Burner.burn(<-vaultArray)
        return <- constantSizeOut
    }
}
