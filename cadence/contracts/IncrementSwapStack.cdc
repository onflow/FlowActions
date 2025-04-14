import "Burner"
import "FungibleToken"
import "FungibleTokenStack"
import "EVM"
import "SwapRouter"

import "StackFiInterfaces"

/// IncrementSwapStack
///
/// This contract defines StackFi Sink & Source connector implementations for use with IncrementFi's DeFi protocols.
/// These connectors can be used alone or in conjunction with other StackFi connectors to create complex DeFi
/// workflows.
///
access(all) contract IncrementSwapStack {

    access(all) struct SwapSink : StackFiInterfaces.Sink {
        /// The pre-conversion Vault Type accepted by this Sink
        access(all) let inVault: Type
        /// The post-conversion Vault Type ingested by the inner Sink
        access(all) let outVault: Type
        /// The token key path identifying how the swap from in to out vault is routed via IncrementFi
        access(all) var path: [String]
        /// The Sink which ingests the output swap results
        access(self) let sink: {StackFiInterfaces.Sink}

        init(
            inVault: Type,
            path: [String],
            sink: {StackFiInterfaces.Sink}
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "inVault \(inVault.identifier) is not a FungibleToken.Vault instance"
                sink.getSinkType().isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Sink Vault Type \(sink.getSinkType().identifier) is not a FungibleToken.Vault instance"
                path.length >= 2:
                "Swap path must include at least 2 token identifiers"
                inVault.identifier == path[0]:
                "Swap path must begin with inVault \(inVault.identifier) but found \(path[0])"
                sink.getSinkType().identifier == path[path.length - 1]:
                "Swap path must end with outVault \(sink.getSinkType().identifier) but found \(path[path.length - 1])"
            }
            self.inVault = inVault
            self.outVault = sink.getSinkType()
            self.sink = sink
            self.path = path
        }

        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type {
            return self.inVault
        }

        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        access(all) fun minimumCapacity(): UFix64 {
            let innerSinkCapacity = self.sink.minimumCapacity()
            if innerSinkCapacity == 0.0 {
                // nothing to ingest as inner sink cannot accept post-conversion currency
                return 0.0
            }
            // estimate pre-conversion currency capacity based on the inner Sink's post-conversion currency capacity
            let amountsIn = SwapRouter.getAmountsIn(amountOut: innerSinkCapacity, tokenKeyPath: self.path)
            return amountsIn[0]
        }

        /// Deposits up to the Sink's capacity from the provided Vault, swapping the provided currency to the outVault
        /// Type along the set path. The resulting swapped currency is then deposited to the inner Sink
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            let preSwapCapacity = self.minimumCapacity()
            if from.balance == 0.0 || preSwapCapacity == 0.0 {
                // nothing to swap from or no capacity to ingest - do nothing
                return
            }

            // take the lesser of this Sink's capacity or the full balance of the `from` Vault
            let amountIn = preSwapCapacity < from.balance ? preSwapCapacity : from.balance
            // perform the swap & deposit to the inner Sink
            var quote = SwapRouter.getAmountsOut(amountIn: amountIn, tokenKeyPath: self.path)
            let deadline = getCurrentBlock().timestamp
            let outVault <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-from.withdraw(amount: amountIn),
                amountOutMin: quote[quote.length - 1],
                tokenKeyPath: self.path,
                deadline: deadline
            )
            self.sink.depositCapacity(from: &outVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            if outVault.balance > 0.0 {
                // deal with any remainder by swapping back & depositing to `from` Vault
                let reversePath = self.path.reverse()
                quote = SwapRouter.getAmountsOut(amountIn: outVault.balance, tokenKeyPath: reversePath)
                let remainder <- SwapRouter.swapExactTokensForTokens(
                    exactVaultIn: <-outVault,
                    amountOutMin: quote[quote.length - 1],
                    tokenKeyPath: reversePath,
                    deadline: deadline
                )
                from.deposit(from: <-remainder)
            } else {
                Burner.burn(<-outVault) // burn the empty Vault
            }
        }
    }
}
