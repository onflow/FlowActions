import "Burner"
import "FungibleToken"
import "FungibleTokenStack"
import "EVM"

import "DFB"

/// SwapStack
///
/// This contract defines StackFi Sink & Source connector implementations for use with DeFi protocols. These
/// connectors can be used alone or in conjunction with other StackFi connectors to create complex DeFi workflows.
///
access(all) contract SwapStack {

    /// A Swapper implementation routing swap requests to the optimal contained Swapper. Once constructed, this can
    /// effectively be used as an aggregator across all contained Swapper implementations, though it is limited to the
    /// routes and pools exposed by its inner Swappers as well as runtime computation limits.
    ///
    access(all) struct MultiSwapper : DFB.Swapper {
        access(self) let inVault: Type
        access(self) let outVault: Type
        access(self) let swappers: [{DFB.Swapper}]

        init(
            inVault: Type,
            outVault: Type,
            swappers: [{DFB.Swapper}]
        ) {
            for swapper in swappers {
                assert(swapper.inVaultType() == inVault,
                    message: "Mismatched inVault \(inVault.identifier) - Swapper \(swapper.getType().identifier) accepts \(swapper.inVaultType().identifier)")
                assert(swapper.outVaultType() == outVault,
                    message: "Mismatched outVault \(outVault.identifier) - Swapper \(swapper.getType().identifier) accepts \(swapper.outVaultType().identifier)")
            }
            self.inVault = inVault
            self.outVault = outVault
            self.swappers = swappers
        }

        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inVaultType(): Type {
            return self.inVault
        }

        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outVaultType(): Type  {
            return self.outVault
        }

        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun amountIn(forDesired: UFix64, reverse: Bool): UFix64 {
            return self.estimate(amount: forDesired, out: true, reverse: reverse)[1]
        }

        /// The estimated amount delivered out for a provided input balance
        access(all) fun amountOut(forProvided: UFix64, reverse: Bool): UFix64 {
            return self.estimate(amount: forProvided, out: true, reverse: reverse)[1]
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let estimate = self.estimate(amount: inVault.balance, out: true, reverse: false)
            let optimalSwapper = &self.swappers[Int(estimate[0])] as &{DFB.Swapper}
            return <- optimalSwapper.swap(inVault: <-inVault)
        }

        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let estimate = self.estimate(amount: residual.balance, out: false, reverse: true)
            let optimalSwapper = &self.swappers[Int(estimate[0])] as &{DFB.Swapper}
            return <- optimalSwapper.swapBack(residual: <-residual) // assumes optimal via set path is also optimal in reverse
        }

        /// Returns the the index of the optimal Swapper (result[0]) and the associated amountOut or amountIn (result[0])
        /// as a UFix64 array
        access(self) fun estimate(amount: UFix64, out: Bool, reverse: Bool): [UFix64; 2] {
            var res: [UFix64; 2] = [0.0, 0.0]
            for i, swapper in self.swappers {
                // call the appropriate estimator
                let estimate = out
                    ? swapper.amountOut(forProvided: amount, reverse: true)
                    : swapper.amountIn(forDesired: amount, reverse: true)
                if (out ? res[1] < estimate : estimate < res[1]) {
                    // take minimum for in, maximum for out
                    res = [UFix64(i), estimate]
                }
            }
            return res
        }
    }

    /// SwapSink StackFi connector that deposits the resulting post-conversion currency of a token swap to an inner
    /// StackFi Sink, sourcing funds from a deposited Vault of a pre-set Type.
    ///
    access(all) struct SwapSink : DFB.Sink {
        access(self) let swapper: {DFB.Swapper}
        access(self) let sink: {DFB.Sink}

        init(swapper: {DFB.Swapper}, sink: {DFB.Sink}) {
            pre {
                swapper.outVaultType() == sink.getSinkType():
                "Swapper outputs \(swapper.outVaultType().identifier) but Sink takes \(sink.getSinkType().identifier) - "
                    .concat("Ensure the provided Swapper outputs a Vault Type compatible with the provided Sink")
            }
            self.swapper = swapper
            self.sink = sink
        }

        access(all) view fun getSinkType(): Type {
            return self.swapper.inVaultType()
        }

        access(all) fun minimumCapacity(): UFix64 {
            return self.swapper.amountIn(forDesired: self.sink.minimumCapacity(), reverse: false)
        }

        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            let limit = self.sink.minimumCapacity()
            if from.balance == 0.0 || limit == 0.0 || !from.getType().isInstance(self.getSinkType()) {
                return // nothing to swap from, no capacity to ingest, invalid Vault type - do nothing
            }

            let sinkLimit = self.minimumCapacity()
            let swapVault <- from.createEmptyVault()

            if sinkLimit < swapVault.balance {
                // The sink is limited to fewer tokens than we have available. Only swap
                // the amount we need to meet the sink limit.
                swapVault.deposit(from: <-from.withdraw(amount: sinkLimit))
            } else {
                // The sink can accept all of the available tokens, so we swap everything
                swapVault.deposit(from: <-from.withdraw(amount: from.balance))
            }

            let swappedTokens <- self.swapper.swap(inVault: <-swapVault)
            self.sink.depositCapacity(from: &swappedTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            if swappedTokens.balance > 0.0 {
                from.deposit(from: <-self.swapper.swapBack(residual: <-swappedTokens))
            } else {
                Burner.burn(<-swappedTokens)
            }
        }
    }

    /// SwapSource StackFi connector that deposits the resulting post-conversion currency of a token swap to an inner
    /// StackFi Sink, sourcing funds from a deposited Vault of a pre-set Type.
    ///
    access(all) struct SwapSource : DFB.Source {
        access(self) let swapper: {DFB.Swapper}
        access(self) let source: {DFB.Source}

        init(swapper: {DFB.Swapper}, source: {DFB.Source}) {
            pre {
                source.getSourceType() == swapper.inVaultType():
                "Source outputs \(source.getSourceType().identifier) but Swapper takes \(swapper.inVaultType().identifier) - "
                    .concat("Ensure the provided Source outputs a Vault Type compatible with the provided Swapper")
            }
            self.swapper = swapper
            self.source = source
        }

        access(all) view fun getSourceType(): Type {
            return self.swapper.outVaultType()
        }

        access(all) fun minimumAvailable(): UFix64 {
            // estimate post-conversion currency based on the source's pre-conversion balance available
            let availableIn = self.source.minimumAvailable()
            return availableIn > 0.0
                ? self.swapper.amountOut(forProvided: availableIn, reverse: false)
                : 0.0
        }

        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let minimumAvail = self.minimumAvailable()
            if minimumAvail == 0.0 {
                return <- SwapStack.getEmptyVault(self.getSourceType())
            }

            // expect output amount as the lesser between the amount available and the maximum amount
            var amountOut = minimumAvail < maxAmount ? minimumAvail : maxAmount

            // find out how much liquidity to gather from the inner Source
            let availableIn = self.source.minimumAvailable()
            var quoteIn = self.swapper.amountIn(forDesired: amountOut, reverse: false)
            quoteIn = availableIn < quoteIn ? availableIn : quoteIn

            let sourceLiquidity <- self.source.withdrawAvailable(maxAmount: quoteIn)
            if sourceLiquidity.balance == 0.0 {
                Burner.burn(<-sourceLiquidity)
                return <- SwapStack.getEmptyVault(self.getSourceType())
            }
            if sourceLiquidity.balance > amountOut {
                // TODO - what to do if inner source exceeds the expected amount which will likely exceed `amountOut`?
            }
            let outVault: @{FungibleToken.Vault} <- self.swapper.swap(inVault: <-sourceLiquidity)
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
