import "Burner"
import "FungibleToken"
import "FungibleTokenStack"
import "EVM"

import "DeFiAdapters"
import "StackFiInterfaces"

/// SwapStack
///
/// This contract defines StackFi Sink & Source connector implementations for use with DeFi protocols. These
/// connectors can be used alone or in conjunction with other StackFi connectors to create complex DeFi workflows.
///
access(all) contract SwapStack {

    /// SwapSink StackFi connector that deposits the resulting post-conversion currency of a token swap to an inner
    /// StackFi Sink, sourcing funds from a deposited Vault of a pre-set Type. The swap leverages IncrementFi's
    /// SwapRouter, routing swaps along a pre-set path.
    ///
    access(all) struct UniswapV2SwapSink : StackFiInterfaces.Sink {
        /// The pre-conversion Vault Type accepted by this Sink
        access(all) let inVault: Type
        /// The post-conversion Vault Type ingested by the inner Sink
        access(all) let outVault: Type
        /// The token key path identifying how the swap from in to out vault is routed via IncrementFi
        access(all) var path: [String]
        /// A UniswapV2SwapAdapter enabling swaps according to a common UniswapV2 interface, abstracting the underling protocol
        access(all) let swapAdapter: {DeFiAdapters.UniswapV2SwapAdapter}
        /// The Sink which ingests the output swap results
        access(self) let sink: {StackFiInterfaces.Sink}

        init(
            inVault: Type,
            path: [String],
            swapAdapter: {DeFiAdapters.UniswapV2SwapAdapter},
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
            self.swapAdapter = swapAdapter
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
            let amountsIn = self.swapAdapter.getAmountsIn(amountOut: innerSinkCapacity, path: self.path)
            return amountsIn[0]
        }

        /// Deposits up to the Sink's capacity from the provided Vault, swapping the provided currency to the outVault
        /// Type along the set path. The resulting swapped currency is then deposited to the inner Sink
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            let preSwapCapacity = self.minimumCapacity()
            if from.balance == 0.0 || preSwapCapacity == 0.0 || !from.getType().isInstance(self.inVault) { 
                // nothing to swap from, no capacity to ingest, invalid Vault type - do nothing
                return
            }

            // take the lesser of this Sink's capacity or the full balance of the `from` Vault
            let amountIn = preSwapCapacity < from.balance ? preSwapCapacity : from.balance
            // perform the swap & deposit to the inner Sink
            var quotesOut = self.swapAdapter.getAmountsOut(amountIn: amountIn, path: self.path)
            let deadline = getCurrentBlock().timestamp
            let outVault <- self.swapAdapter.swapExactTokensForTokens(
                exactVaultIn: <-from.withdraw(amount: amountIn),
                amountOutMin: quotesOut[quotesOut.length - 1],
                path: self.path,
                deadline: deadline
            )
            self.sink.depositCapacity(from: &outVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            if outVault.balance > 0.0 {
                // deal with any remainder by swapping back & depositing to `from` Vault
                let reversePath = self.path.reverse()
                quotesOut = self.swapAdapter.getAmountsOut(amountIn: outVault.balance, path: reversePath)
                let remainder <- self.swapAdapter.swapExactTokensForTokens(
                    exactVaultIn: <-outVault,
                    amountOutMin: quotesOut[quotesOut.length - 1],
                    path: reversePath,
                    deadline: deadline
                )
                from.deposit(from: <-remainder)
            } else {
                Burner.burn(<-outVault) // burn the empty Vault
            }
        }
    }

    access(all) struct UniswapV2SwapSource : StackFiInterfaces.Source {
        /// The sourceVault Type provided on initialization, stored in the event the Capability becomes invalid.
        access(all) let inVault: Type
        /// The post-conversion Vault Type ingested by the inner Sink
        access(all) let outVault: Type
        /// The token key path identifying how the swap from in to out vault is routed via IncrementFi
        access(all) var path: [String]
        /// A UniswapV2SwapAdapter enabling swaps according to a common UniswapV2 interface, abstracting the underling
        /// swap protocol
        access(all) let swapAdapter: {DeFiAdapters.UniswapV2SwapAdapter}
        /// The Vault from which to source initial liquidity, swapping to the defined `outVault` type
        access(self) let source: {StackFiInterfaces.Source}

        init(
            outVault: Type,
            path: [String],
            swapAdapter: {DeFiAdapters.UniswapV2SwapAdapter},
            source: {StackFiInterfaces.Source}
        ) {
            pre {
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "outVault \(outVault.identifier) is not a FungibleToken.Vault instance"
                path.length >= 2:
                "Swap path must include at least 2 token identifiers"
                source.getSourceType().identifier == path[0]:
                "Swap path must begin with inVault \(source.getSourceType().identifier) but found \(path[0])"
                outVault.identifier == path[path.length - 1]:
                "Swap path must end with outVault \(outVault.identifier) but found \(path[path.length - 1])"
            }
            self.inVault = source.getSourceType()
            self.outVault = outVault
            self.path = path
            self.swapAdapter = swapAdapter
            self.source = source
        }

        /// Returns the Vault type provided by this Source
        access(all) view fun getSourceType(): Type {
            return self.inVault
        }

        /// Returns an estimate of how much of the associated Vault can be provided by this Source
        access(all) fun minimumAvailable(): UFix64 {
            let availableIn = self.source.minimumAvailable()
            if availableIn == 0.0 {
                return 0.0
            }
            // estimate post-conversion currency based on the source's pre-conversion balance available
            let amountsOut = self.swapAdapter.getAmountsOut(amountIn: availableIn, path: self.path)
            return amountsOut[amountsOut.length - 1] // available out based on available in
        }

        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be
        /// returned
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let minimumAvail = self.minimumAvailable()
            if minimumAvail == 0.0 {
                return <- SwapStack.getEmptyVault(self.outVault)
            }
            // expect output amount as the lesser between the amount available and the maximum amount
            var amountOut = minimumAvail < maxAmount ? minimumAvail : maxAmount

            // find out how much liquidity to gather from the inner Source
            let availableIn = self.source.minimumAvailable()
            let quotesIn = self.swapAdapter.getAmountsIn(amountOut: amountOut, path: self.path)
            let quoteIn = availableIn < quotesIn[0] ? availableIn : quotesIn[0]

            let sourceLiquidity <- self.source.withdrawAvailable(maxAmount: quoteIn)
            if sourceLiquidity.balance == 0.0 {
                Burner.burn(<-sourceLiquidity)
                return <- SwapStack.getEmptyVault(self.outVault)
            }
            if sourceLiquidity.balance > amountOut {
                // TODO - what to do if inner source exceeds the expected amount which will likely exceed `amountOut`?
            }
            let outVault <- self.swapAdapter.swapExactTokensForTokens(
                    exactVaultIn: <-sourceLiquidity,
                    amountOutMin: amountOut,
                    path: self.path,
                    deadline: getCurrentBlock().timestamp
                )
            return <- outVault
        }
    }

    /// Returns an empty Vault of the given Type, sourcing the new Vault from the defining FT contract
    access(self) fun getEmptyVault(_ vaultType: Type): @{FungibleToken.Vault} {
        return <- getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
            .createEmptyVault(vaultType: vaultType)
    }
}
