import "Burner"
import "FungibleToken"

/// DeFiAdapters
///
/// Data structure interfaces standardizing DeFi operations for use in modular Cadence contracts
///
access(all) contract DeFiAdapters {

    /// Struct interface adapting UniswapV2 style swaps routers. These interfaces borrow heavily from IncrementFi's
    /// SwapRouter contract as it's the leading UniswapV2 style DeFi protocol written in Cadence as of this writing.
    ///
    access(all) struct interface SwapAdapter {
        /// Port of UniswapV2Router.swapExactTokensForTokens swapping the exact amount provided along the given path,
        /// returning the final output Vault
        ///
        /// @param exactVaultIn: The exact balance to swap as pre-converted currency
        /// @param amountOutMin: The minimum output balance expected as post-converted currency, useful for slippage
        /// @param path: The routing path through which to route swaps
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
            post {
                result.getType().identifier == path[path.length - 1]:
                "Output vault is of type \(result.getType().identifier), but path defines the "
                    .concat("output should be of type \(path[path.length - 1])")
            }
        }

        /// Port of UniswapV2Router.swapTokensForExactTokens swapping the funds provided for exact output along the
        /// given path, returning the final output Vault as well as any remainder of the original input Vault
        ///
        /// @param exactAmountOut: The exact desired balance to expect as a swap output
        /// @param vaultInMax: The maximum balance to use as pre-converted currency, useful for slippage
        /// @param path: The routing path through which to route swaps
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
            post {
                result[0].getType().identifier == path[path.length - 1]:
                "Output vault at result[0] is of type \(result[0].getType().identifier), but path defines the "
                    .concat("output should be of type \(path[path.length - 1])")
                result[1].isInstance(before(vaultInMax.getType())):
                "Remainder vault at result[1] is of type \(result[1].getType().identifier), but the input Vault was of "
                    .concat("type \(before(vaultInMax.getType()).identifier)")
            }
        }
    }
}