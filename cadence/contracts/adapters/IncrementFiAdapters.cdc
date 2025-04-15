import "FungibleToken"
import "Burner"

import "SwapRouter"
import "DeFiAdapters"

/// IncrementFiAdapters
///
/// DeFi adapter implementations fitting IncrementFi protocols to the data structure defined in DeFiAdapters.
///
access(all) contract IncrementFiAdapters {

    /// Adapts IncrementFi's SwapRouter contract swap methods to DeFiAdapters.UniswapV2SwapAdapter struct interface
    ///
    access(all) struct SwapAdapter : DeFiAdapters.UniswapV2SwapAdapter {
        /// Quotes the input amounts for some desired amount in along the provided path. This implementation routes
        /// calls to IncrementFi's SwapRouter contract.
        ///
        /// @param amountOut: The desired post-conversion amount out
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        ///
        /// @return An array of input values for each step along the swap path
        ///
        access(all) fun getAmountsIn(amountOut: UFix64, path: [String]): [UFix64] {
            return SwapRouter.getAmountsIn(amountOut: amountOut, tokenKeyPath: path)
        }

        /// Quotes the output amounts for some amount in along the provided path. This implementation routes calls to
        /// IncrementFi's SwapRouter contract.
        ///
        /// @param amountIn: The input amount (in pre-conversion currency) available for the swap
        /// @param path: The routing path through which to route swaps - may be pool or vault identifiers or serialized
        ///     EVM addresses if the router is in EVM
        ///
        /// @return An array of output values for each step along the swap path
        ///
        access(all) fun getAmountsOut(amountIn: UFix64, path: [String]): [UFix64] {
            return SwapRouter.getAmountsOut(amountIn: amountIn, tokenKeyPath: path)
        }

        /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
        /// returning the final output Vault. This implementation routes calls to IncrementFi's SwapRouter contract.
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
            return <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-exactVaultIn,
                amountOutMin: amountOutMin,
                tokenKeyPath: path,
                deadline: deadline
            )
        }

        /// Port of UniswapV2Router.swapTokensForExactTokens swapping the funds provided for exact output along the
        /// given path, returning the final output Vault as well as any remainder of the original input Vault. This
        /// implementation routes calls to IncrementFi's SwapRouter contract.
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
            // perform swap & return constant-sized nested resource array
            let swapResult <- SwapRouter.swapTokensForExactTokens(
                    vaultInMax: <-vaultInMax,
                    exactAmountOut: exactAmountOut,
                    tokenKeyPath: path,
                    deadline: deadline
                )
            return <- IncrementFiAdapters.toConstantSizedDoubleVaultArray(<-swapResult)
        }
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
