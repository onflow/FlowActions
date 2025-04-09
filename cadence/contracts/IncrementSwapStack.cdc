import "Burner"
import "FungibleToken"
import "FungibleTokenStack"
import "EVM"
import "StackFiInterfaces"
import "SwapRouter"

access(all) contract IncrementSwapStack {

    access(all) struct SwapSink : StackFiInterfaces.Sink {
        access(all) let inVault: Type
        access(all) let outVault: Type
        access(all) var path: [String]
        access(self) let sink: {StackFiInterfaces.Sink}
        view init(
            inVault: Type,
            outVault: Type,
            path: [String],
            sink: {StackFiInterfaces.Sink}
        ) {
            pre {
                outVault == sink.getSinkType():
                "Sink \(sink.getType().identifier) does not accept outVault \(outVault.identifier)"
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "inVault \(inVault.identifier) is not a FungibleToken.Vault instance"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "outVault \(outVault.identifier) is not a FungibleToken.Vault instance"
                path.length >= 2:
                "Swap path must include at least 2 token identifiers"
                inVault.identifier == path[0]:
                "Swap path must begin with inVault \(inVault.identifier) but found \(path[0])"
                outVault.identifier == path[path.length - 1]:
                "Swap path must end with outVault \(outVault.identifier) but found \(path[path.length - 1])"
            }
            self.inVault = inVault
            self.outVault = outVault
            self.sink = sink
            self.path = path
        }

        access(all) view fun getSinkType(): Type {
            return self.inVault
        }

        access(all) fun minimumCapacity(): UFix64 {
            return self.sink.minimumCapacity()
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // determine the limits of exchange
            let sinkCapacity = self.minimumCapacity()
            var quote = SwapRouter.getAmountsOut(amountIn: from.balance, tokenKeyPath: self.path)
            if sinkCapacity < quote[quote.length - 1] {
                quote = SwapRouter.getAmountsIn(amountOut: self.minimumCapacity(), tokenKeyPath: self.path)
                self.swapTokensForExactTokens(from: from, quote: quote)
            } else {
                self.swapExactTokensForTokens(from: from, quote: quote)
            }
        }

        access(self) fun swapTokensForExactTokens(
            from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
            quote: [UFix64]
        ) {
            pre {
                quote.length > 0: "Quote must contain at least one estimate but received none"
            }
            let deadline = getCurrentBlock().timestamp
            // perform the swap
            let swapResult <- SwapRouter.swapTokensForExactTokens(
                vaultInMax: <-from.withdraw(amount: quote[0]),
                exactAmountOut: quote[quote.length - 1],
                tokenKeyPath: self.path,
                deadline: deadline
            )
            
            // deposit the swap result
            let outRef = &swapResult[0] as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
            let remainingRef = &swapResult[1] as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
            
            // deposit to sink and return any remainder if exists
            self.sink.depositCapacity(from: outRef)
            if outRef.balance > 0.0 {
                from.deposit(from: <-outRef.withdraw(amount: outRef.balance))
            }
            if remainingRef.balance > 0.0 {
                from.deposit(from: <-remainingRef.withdraw(amount: remainingRef.balance))
            }

            Burner.burn(<-swapResult) // burn swapResult array
        }

        access(self) fun swapExactTokensForTokens(
            from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
            quote: [UFix64]
        ) {
            pre {
                quote.length > 0: "Quote must contain at least one estimate but received none"
            }
            let deadline = getCurrentBlock().timestamp
            // perform the swap
            let swapResult <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-from.withdraw(amount: from.balance),
                amountOutMin: quote[quote.length - 1],
                tokenKeyPath: self.path,
                deadline: deadline
            )

            // deposit the swap result
            self.sink.depositCapacity(from: &swapResult as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // handle remainder by swapping back and depositing to from vault
            if swapResult.balance > 0.0 {
                let remainderSwap <- SwapRouter.swapExactTokensForTokens(
                    exactVaultIn: <-swapResult,
                    amountOutMin: 0.0,
                    tokenKeyPath: self.path.reverse(),
                    deadline: deadline
                )
                from.deposit(from: <-remainderSwap)
            } else {
                Burner.burn(<-swapResult) // burn the resulting empty vault
            }
        }
    }
}
