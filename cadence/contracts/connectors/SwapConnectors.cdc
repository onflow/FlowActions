import "Burner"
import "FungibleToken"

import "DeFiActions"
import "DeFiActionsUtils"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// SwapConnectors
///
/// This contract defines DeFi Actions Sink & Source connector implementations for use with DeFi protocols. These
/// connectors can be used alone or in conjunction with other DeFi Actions connectors to create complex DeFi workflows.
///
access(all) contract SwapConnectors {

    /// BasicQuote
    ///
    /// A simple implementation of DeFiActions.Quote allowing callers of Swapper.quoteIn() and .quoteOut() to cache quoted
    /// amount in and/or out.
    ///
    access(all) struct BasicQuote : DeFiActions.Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64

        init(
            inType: Type,
            outType: Type,
            inAmount: UFix64,
            outAmount: UFix64
        ) {
            self.inType = inType
            self.outType = outType
            self.inAmount = inAmount
            self.outAmount = outAmount
        }
    }

    /// Swap mode metadata for interpreting quote semantics in Swapper.swap().
    access(all) enum SwapMode: UInt8 {
        access(all) case IN
        access(all) case OUT
    }

    /// A quote that carries swap mode metadata and a receiver capability for exact-output residual input.
    access(all) struct ModeQuote : DeFiActions.Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64
        access(all) let mode: SwapMode
        access(all) let leftoverInReceiver: Capability<&{FungibleToken.Receiver}>?

        init(
            inType: Type,
            outType: Type,
            inAmount: UFix64,
            outAmount: UFix64,
            mode: SwapMode,
            leftoverInReceiver: Capability<&{FungibleToken.Receiver}>?
        ) {
            self.inType = inType
            self.outType = outType
            self.inAmount = inAmount
            self.outAmount = outAmount
            self.mode = mode
            self.leftoverInReceiver = leftoverInReceiver
        }
    }

    /// Returns a ModeQuote copy of any DeFiActions.Quote.
    access(all) fun asModeQuote(
        quote: {DeFiActions.Quote},
        mode: SwapMode,
        leftoverInReceiver: Capability<&{FungibleToken.Receiver}>?
    ): ModeQuote {
        if let modeQuote = quote as? ModeQuote {
            return ModeQuote(
                inType: modeQuote.inType,
                outType: modeQuote.outType,
                inAmount: modeQuote.inAmount,
                outAmount: modeQuote.outAmount,
                mode: mode,
                leftoverInReceiver: leftoverInReceiver ?? modeQuote.leftoverInReceiver
            )
        }
        return ModeQuote(
            inType: quote.inType,
            outType: quote.outType,
            inAmount: quote.inAmount,
            outAmount: quote.outAmount,
            mode: mode,
            leftoverInReceiver: leftoverInReceiver
        )
    }

    /// Returns a ModeQuote configured for exact-input behavior.
    access(all) fun asExactInQuote(quote: {DeFiActions.Quote}): ModeQuote {
        return self.asModeQuote(
            quote: quote,
            mode: SwapMode.IN,
            leftoverInReceiver: nil
        )
    }

    /// Returns a ModeQuote configured for exact-output behavior.
    access(all) fun asExactOutQuote(
        quote: {DeFiActions.Quote},
        leftoverInReceiver: Capability<&{FungibleToken.Receiver}>
    ): ModeQuote {
        return self.asModeQuote(
            quote: quote,
            mode: SwapMode.OUT,
            leftoverInReceiver: leftoverInReceiver
        )
    }

    /// MultiSwapperQuote
    ///
    /// A MultiSwapper specific DeFiActions.Quote implementation allowing for callers to set the Swapper used in
    /// MultiSwapper that should fulfill the Swap
    ///
    access(all) struct MultiSwapperQuote : DeFiActions.Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64
        access(all) let swapperIndex: Int

        init(
            inType: Type,
            outType: Type,
            inAmount: UFix64,
            outAmount: UFix64,
            swapperIndex: Int
        ) {
            pre {
                swapperIndex >= 0: "Invalid swapperIndex - provided \(swapperIndex) is less than 0"
            }
            self.inType = inType
            self.outType = outType
            self.inAmount = inAmount
            self.outAmount = outAmount
            self.swapperIndex = swapperIndex
        }
    }

    /// MultiSwapper
    ///
    /// A Swapper implementation routing swap requests to the optimal contained Swapper. Once constructed, this can
    /// effectively be used as an aggregator across all contained Swapper implementations, though it is limited to the
    /// routes and pools exposed by its inner Swappers as well as runtime computation limits.
    ///
    access(all) struct MultiSwapper : DeFiActions.Swapper {
        access(all) let swappers: [{DeFiActions.Swapper}]
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        access(self) let inVault: Type
        access(self) let outVault: Type

        init(
            inVault: Type,
            outVault: Type,
            swappers: [{DeFiActions.Swapper}],
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Invalid inVault type - \(inVault.identifier) is not a FungibleToken Vault implementation"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                "Invalid outVault type - \(outVault.identifier) is not a FungibleToken Vault implementation"
            }
            for i in InclusiveRange(0, swappers.length - 1) {
                let swapper = &swappers[i] as &{DeFiActions.Swapper}
                assert(swapper.inType() == inVault,
                    message: "Mismatched inVault \(inVault.identifier) - Swapper \(swapper.getType().identifier) accepts \(swapper.inType().identifier)")
                assert(swapper.outType() == outVault,
                    message: "Mismatched outVault \(outVault.identifier) - Swapper \(swapper.getType().identifier) accepts \(swapper.outType().identifier)")
            }
            self.inVault = inVault
            self.outVault = outVault
            self.uniqueID = uniqueID
            self.swappers = swappers
        }

        /// Returns a ComponentInfo struct containing information about this MultiSwapper and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            let inner: [DeFiActions.ComponentInfo] = []
            for swapper in self.swappers {
                inner.append(swapper.getComponentInfo())
            }
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: inner
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
        access(all) view fun outType(): Type  {
            return self.outVault
        }
        /// The estimated amount required to provide a Vault with the desired output balance
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let estimate = self._estimate(amount: forDesired, out: false, reverse: reverse)
            return MultiSwapperQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: estimate[1],
                outAmount: forDesired,
                swapperIndex: Int(estimate[0])
            )
        }
        /// The estimated amount delivered out for a provided input balance
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let estimate = self._estimate(amount: forProvided, out: true, reverse: reverse)
            return MultiSwapperQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: forProvided,
                outAmount: estimate[1],
                swapperIndex: Int(estimate[0])
            )
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols. If the provided quote is not a MultiSwapperQuote, a new quote is
        /// requested and the optimal Swapper used to fulfill the swap.
        /// NOTE: providing a Quote does not guarantee the fulfilled swap will enforce the quote's defined outAmount
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            if quote != nil {
                if let modeQuote = quote as? ModeQuote {
                    if modeQuote.mode == SwapMode.OUT {
                        let residualReceiverCap = modeQuote.leftoverInReceiver
                            ?? panic("Exact-out quote requires a valid leftoverInReceiver capability")
                        let residualReceiver = residualReceiverCap.borrow()
                            ?? panic("Exact-out quote contains an invalid leftoverInReceiver capability")

                        let estimate = self.quoteIn(forDesired: modeQuote.outAmount, reverse: false) as! MultiSwapperQuote
                        let routedQuote = MultiSwapperQuote(
                            inType: estimate.inType,
                            outType: estimate.outType,
                            inAmount: modeQuote.inAmount,
                            outAmount: modeQuote.outAmount,
                            swapperIndex: estimate.swapperIndex
                        )
                        let optimalSwapper = &self.swappers[routedQuote.swapperIndex] as &{DeFiActions.Swapper}
                        let vaults <- optimalSwapper.swapExactOut(quote: routedQuote, inVault: <-inVault)

                        let outVault <- vaults.remove(at: 0)
                        let leftoverInVault <- vaults.remove(at: 0)
                        destroy vaults

                        if leftoverInVault.balance > 0.0 {
                            residualReceiver.deposit(from: <-leftoverInVault)
                        } else {
                            Burner.burn(<-leftoverInVault)
                        }

                        return <-outVault
                    }
                }
            }
            return <-self._swap(quote: quote, from: <-inVault, reverse: false)
        }
        /// Swap for exact output using the optimal inner Swapper
        access(all) fun swapExactOut(quote: {DeFiActions.Quote}, inVault: @{FungibleToken.Vault}): @[{FungibleToken.Vault}] {
            var multiQuote = quote as? MultiSwapperQuote
            if multiQuote == nil || multiQuote!.swapperIndex >= self.swappers.length {
                let estimate = self.quoteIn(forDesired: quote.outAmount, reverse: false) as! MultiSwapperQuote
                multiQuote = MultiSwapperQuote(
                    inType: estimate.inType,
                    outType: estimate.outType,
                    inAmount: quote.inAmount,
                    outAmount: quote.outAmount,
                    swapperIndex: estimate.swapperIndex
                )
            }
            let optimalSwapper = &self.swappers[multiQuote!.swapperIndex] as &{DeFiActions.Swapper}
            return <- optimalSwapper.swapExactOut(quote: multiQuote!, inVault: <-inVault)
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        /// NOTE: providing a Quote does not guarantee the fulfilled swap will enforce the quote's defined outAmount
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            return <-self._swap(quote: quote, from: <-residual, reverse: true)
        }
        /// Returns the the index of the optimal Swapper (result[0]) and the associated amountOut or amountIn (result[0])
        /// as a UFix64 array
        access(self) fun _estimate(amount: UFix64, out: Bool, reverse: Bool): [UFix64; 2] {
            var res: [UFix64; 2] = out ? [0.0, 0.0] : [0.0, UFix64.max] // maximizing for out, minimizing for in
            for i in InclusiveRange(0, self.swappers.length - 1) {
                let swapper = &self.swappers[i] as &{DeFiActions.Swapper}
                // call the appropriate estimator
                let estimate = out
                    ? swapper.quoteOut(forProvided: amount, reverse: reverse).outAmount
                    : swapper.quoteIn(forDesired: amount, reverse: reverse).inAmount
                // estimates of 0.0 are presumed to be graceful failures - skip them
                if estimate > 0.0 && (out ? res[1] < estimate : estimate < res[1]) {
                    // take minimum for in, maximum for out
                    res = [UFix64(i), estimate]
                }
            }
            return res
        }
        /// Swaps the provided Vault in the defined direction. If the quote is not a MultiSwapperQuote, a new quote is
        /// requested and the current optimal Swapper used to fulfill the swap.
        access(self) fun _swap(quote: {DeFiActions.Quote}?, from: @{FungibleToken.Vault}, reverse: Bool): @{FungibleToken.Vault} {
            var multiQuote = quote as? MultiSwapperQuote
            if multiQuote == nil || multiQuote!.swapperIndex >= self.swappers.length {
                multiQuote = self.quoteOut(forProvided: from.balance, reverse: reverse) as! MultiSwapperQuote
            }
            let optimalSwapper = &self.swappers[multiQuote!.swapperIndex] as &{DeFiActions.Swapper}
            if reverse {
                return <- optimalSwapper.swapBack(quote: multiQuote, residual: <-from)
            } else {
                return <- optimalSwapper.swap(quote: multiQuote, inVault: <-from)
            }
        }
    }

    /// SwapSink
    ///
    /// A DeFiActions connector that deposits the resulting post-conversion currency of a token swap to an inner
    /// DeFiActions Sink, sourcing funds from a deposited Vault of a pre-set Type.
    ///
    /// NOTE: If residual tokens remain after depositing to the inner sink, swapBack() is called on the swapper to
    ///     return them to the original vault. One-way swappers (e.g., ERC4626SwapConnectors.Swapper) that do not
    ///     support swapBack() can still be used safely if the inner sink always consumes all swapped tokens (i.e.,
    ///     has sufficient capacity). If residuals occur with a one-way swapper, the transaction will revert.
    ///
    access(all) struct SwapSink : DeFiActions.Sink {
        access(self) let swapper: {DeFiActions.Swapper}
        access(self) let sink: {DeFiActions.Sink}
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(swapper: {DeFiActions.Swapper}, sink: {DeFiActions.Sink}, uniqueID: DeFiActions.UniqueIdentifier?) {
            pre {
                swapper.outType() == sink.getSinkType():
                "Swapper outputs \(swapper.outType().identifier) but Sink takes \(sink.getSinkType().identifier) - "
                    .concat("Ensure the provided Swapper outputs a Vault Type compatible with the provided Sink")
            }
            self.swapper = swapper
            self.sink = sink
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this SwapSink and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.swapper.getComponentInfo(),
                    self.sink.getComponentInfo()
                ]
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
        /// Returns the type of Vault this Sink accepts when performing a swap
        ///
        /// @return the type of Vault this Sink accepts when performing a swap
        ///
        access(all) view fun getSinkType(): Type {
            return self.swapper.inType()
        }
        /// Returns the minimum capacity required to deposit to this Sink
        ///
        /// @return the minimum capacity required to deposit to this Sink
        ///
        access(all) fun minimumCapacity(): UFix64 {
            return self.swapper.quoteIn(forDesired: self.sink.minimumCapacity(), reverse: false).inAmount
        }
        /// Deposits the provided Vault to this Sink, swapping the provided Vault to the required type if necessary
        ///
        /// @param from: the Vault to source deposits from
        ///
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            // nothing to swap from, no capacity to ingest, invalid Vault type - do nothing
            if from.balance == 0.0 || from.getType() != self.getSinkType() { return; }
            let limit = self.sink.minimumCapacity()
            if limit == 0.0 { return; }

            // quote based on available funds & inner sink limit
            var quote = self.swapper.quoteOut(forProvided: from.balance, reverse: false)
            if limit <= quote.outAmount {
                quote = self.swapper.quoteIn(forDesired: limit, reverse: false)
            }
            // error when quoting - in/out should not be 0.0
            if quote.inAmount == 0.0 || quote.outAmount == 0.0 { return; }

            // assign the amount to swap based on updated quote
            let swapAmount = quote.inAmount <= from.balance ? quote.inAmount : from.balance
            // swap then deposit to the inner sink
            let swapVault <- from.withdraw(amount: swapAmount)
            let swappedTokens <- self.swapper.swap(quote: quote, inVault: <-swapVault)
            self.sink.depositCapacity(from: &swappedTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})

            if swappedTokens.balance > 0.0 {
                // swap back any residual to the originating vault
                let residual <- self.swapper.swapBack(quote: nil, residual: <-swappedTokens)
                from.deposit(from: <-residual)
            } else {
                Burner.burn(<-swappedTokens) // nothing left - burn & execute vault's burnCallback()
            }
        }
    }

    /// SequentialSwapper
    ///
    /// A Swapper implementation routing swap requests to a sequence of Swappers. This may be helpful when a single
    /// path is not sufficient to meet the desired swap requirements - e.g. swapping from one token to the underlying
    /// asset of an ERC4626 vault to then swap to the ERC4626 vault shares.
    ///
    access(all) struct SequentialSwapper : DeFiActions.Swapper {
        access(all) let swappers: [{DeFiActions.Swapper}]
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        access(self) let inVault: Type
        access(self) let outVault: Type

        init(swappers: [{DeFiActions.Swapper}], uniqueID: DeFiActions.UniqueIdentifier?) {
            pre {
                swappers.length > 1:
                "Provided swappers must have a length of at least 2 - provided \(swappers.length) swappers"
            }
            // ensure each swapper's inType matches the previous swapper's outType
            for i in InclusiveRange(0, swappers.length - 1) {
                let swapper = &swappers[i] as &{DeFiActions.Swapper}
                if i < swappers.length - 1 {
                    let nextSwapper = &swappers[i + 1] as &{DeFiActions.Swapper}
                    assert(swapper.outType() == nextSwapper.inType(),
                        message: "Mismatched inType \(nextSwapper.inType().identifier) - Swapper \(swapper.getType().identifier) accepts \(swapper.outType().identifier)")
                    }
            }
            self.inVault = swappers[0].inType()
            self.outVault = swappers[swappers.length - 1].outType()
            self.swappers = swappers
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this SequentialSwapper and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            let inner: [DeFiActions.ComponentInfo] = []
            for i in InclusiveRange(0, self.swappers.length - 1) {
                let swapper = &self.swappers[i] as &{DeFiActions.Swapper}
                inner.append(swapper.getComponentInfo())
            }
            return DeFiActions.ComponentInfo(type: self.getType(), id: self.id(), innerComponents: inner)
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
        ///
        /// @param forDesired: The amount in desired of the pre-conversion currency as a result of the swap
        /// @param reverse: If false, the default inVault -> outVault is used, otherwise, the method estimates a swap
        ///     in the opposite direction, outVault -> inVault
        ///
        /// @return a DeFiActions.Quote containing estimate data. In order to prevent upstream reversion,
        ///     result.inAmount and result.outAmount will be 0.0 if an estimate is not available
        ///
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            var tmpAmount = forDesired
            var finalOutAmount = forDesired

            // walk through the swappers in the sequence starting with the output based on direction of swap
            let range = reverse
                ? InclusiveRange(0, self.swappers.length - 1)
                : InclusiveRange(self.swappers.length - 1, 0, step: -1)
            for i in range {
                let swapper = &self.swappers[i] as &{DeFiActions.Swapper}
                let quote = swapper.quoteIn(forDesired: tmpAmount, reverse: reverse)
                if quote.inAmount == 0.0 || quote.outAmount == 0.0 {
                    return SwapConnectors.BasicQuote(
                        inType: reverse ? self.outType() : self.inType(),
                        outType: reverse ? self.inType() : self.outType(),
                        inAmount: 0.0,
                        outAmount: 0.0
                    )
                }
                if i == range.start { finalOutAmount = quote.outAmount; }
                tmpAmount = quote.inAmount
            }

            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: tmpAmount,
                outAmount: finalOutAmount
            )
        }
        /// The estimated amount delivered out for a provided input balance
        ///
        /// @param forProvided: The amount in provided of the pre-conversion currency as a result of the swap
        /// @param reverse: If false, the default inVault -> outVault is used, otherwise, the method estimates a swap
        ///     in the opposite direction, outVault -> inVault
        ///
        /// @return a DeFiActions.Quote containing estimate data. In order to prevent upstream reversion,
        ///     result.inAmount and result.outAmount will be 0.0 if an estimate is not available
        ///
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            var tmpAmount = forProvided
            var finalInAmount = forProvided

            // walk through the swappers in the sequence starting with the input based on direction of swap
            let range = reverse
                ? InclusiveRange(self.swappers.length - 1, 0, step: -1)
                : InclusiveRange(0, self.swappers.length - 1)
            for i in range {
                let swapper = &self.swappers[i] as &{DeFiActions.Swapper}
                let quote = swapper.quoteOut(forProvided: tmpAmount, reverse: reverse)
                if quote.inAmount == 0.0 || quote.outAmount == 0.0 {
                    return SwapConnectors.BasicQuote(
                        inType: reverse ? self.outType() : self.inType(),
                        outType: reverse ? self.inType() : self.outType(),
                        inAmount: 0.0,
                        outAmount: 0.0
                    )
                }
                if i == range.start { finalInAmount = quote.inAmount; }
                tmpAmount = quote.outAmount
            }

            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: finalInAmount,
                outAmount: tmpAmount
            )
        }
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Callers should be careful
        /// to ensure the resulting output meets their expectations given the provided inVault.balance.
        /// NOTE: providing a Quote does not guarantee the fulfilled swap will enforce the quote's defined outAmount
        ///
        /// @param quote: A `DeFiActions.Quote` data structure. This implementation ignores the quote parameter so callers
        ///     should be sure to enforce outputs against the expected outVault.balance
        /// @param inVault: The Vault to swap from
        ///
        /// @return a Vault of type `outVault` containing the swapped currency.
        ///
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            return <- self._swap(quote: quote, from: <-inVault, reverse: false)
        }
        /// Exact output swaps are not supported for SequentialSwapper
        access(all) fun swapExactOut(quote: {DeFiActions.Quote}, inVault: @{FungibleToken.Vault}): @[{FungibleToken.Vault}] {
            panic("SequentialSwapper does not support swapExactOut - use swap() with quoteIn() instead")
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Callers should be careful
        /// to ensure the resulting output meets their expectations given the provided residual.balance.
        /// NOTE: providing a Quote does not guarantee the fulfilled swap will enforce the quote's defined outAmount
        ///
        /// @param quote: A `DeFiActions.Quote` data structure. This implementation ignores the quote parameter so callers
        ///     should be sure to enforce outputs against the expected inVault.balance
        /// @param residual: The Vault to swap back from
        ///
        /// @return a Vault of type `inVault` containing the swapped currency.
        ///
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            return <- self._swap(quote: quote, from: <-residual, reverse: true)
        }
        /// Internal swap function performing the swap along the defined path.
        ///
        /// @param quote: A `DeFiActions.Quote` data structure. If provided, quote.outAmount is used as the minimum amount out
        ///     desired otherwise a new quote is generated from current state
        /// @param from: The Vault to swap from
        /// @param reverse: Whether to swap in the reverse direction
        ///
        /// @return a Vault of type `outVault` containing the swapped currency.
        ///
        access(self)
        fun _swap(quote: {DeFiActions.Quote}?, from: @{FungibleToken.Vault}, reverse: Bool): @{FungibleToken.Vault} {
            let range = reverse
                ? InclusiveRange(self.swappers.length - 1, 0, step: -1)
                : InclusiveRange(0, self.swappers.length - 1)
            var vault <- from.withdraw(amount: from.balance)
            Burner.burn(<-from)

            for i in range {
                let swapper = &self.swappers[i] as &{DeFiActions.Swapper}
                let swapFun = reverse ? swapper.swapBack : swapper.swap

                let preSwap <- vault.withdraw(amount: vault.balance)
                var swapped <- swapFun(quote: nil, <-preSwap)
                vault <-> swapped
                Burner.burn(<-swapped)
            }
            return <- vault
        }
    }

    /// SwapSource
    ///
    /// A DeFiActions connector that returns post-conversion currency, sourcing pre-converted funds from an inner
    /// DeFiActions Source
    ///
    access(all) struct SwapSource : DeFiActions.Source {
        access(self) let swapper: {DeFiActions.Swapper}
        access(self) let source: {DeFiActions.Source}
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(swapper: {DeFiActions.Swapper}, source: {DeFiActions.Source}, uniqueID: DeFiActions.UniqueIdentifier?) {
            pre {
                source.getSourceType() == swapper.inType():
                "Source outputs \(source.getSourceType().identifier) but Swapper takes \(swapper.inType().identifier) - "
                    .concat("Ensure the provided Source outputs a Vault Type compatible with the provided Swapper")
            }
            self.swapper = swapper
            self.source = source
            self.uniqueID = uniqueID
        }

        /// Returns a ComponentInfo struct containing information about this SwapSource and its inner DFA components
        ///
        /// @return a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        ///     each inner component in the stack.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: [
                    self.swapper.getComponentInfo(),
                    self.source.getComponentInfo()
                ]
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
        /// Returns the type of Vault this Source provides when performing a swap
        ///
        /// @return the type of Vault this Source provides when performing a swap
        ///
        access(all) view fun getSourceType(): Type {
            return self.swapper.outType()
        }
        /// Returns the minimum amount of currency available to withdraw from this Source
        ///
        /// @return the minimum amount of currency available to withdraw from this Source
        ///
        access(all) fun minimumAvailable(): UFix64 {
            // estimate post-conversion currency based on the source's pre-conversion balance available
            let availableIn = self.source.minimumAvailable()
            return availableIn > 0.0
                ? self.swapper.quoteOut(forProvided: availableIn, reverse: false).outAmount
                : 0.0
        }
        /// Withdraws the provided amount of currency from this Source, swapping the provided amount to the required type if necessary
        ///
        /// @param maxAmount: the maximum amount of currency to withdraw from this Source
        ///
        /// @return the Vault containing the withdrawn currency
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let minimumAvail = self.minimumAvailable()
            if minimumAvail == 0.0 || maxAmount == 0.0 {
                return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
            }

            // expect output amount as the lesser between the amount available and the maximum amount
            var quote = minimumAvail < maxAmount
                ? self.swapper.quoteOut(forProvided: self.source.minimumAvailable(), reverse: false)
                : self.swapper.quoteIn(forDesired: maxAmount, reverse: false)

            let sourceLiquidity <- self.source.withdrawAvailable(maxAmount: quote.inAmount)
            if sourceLiquidity.balance == 0.0 {
                Burner.burn(<-sourceLiquidity)
                return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
            }
            return <- self.swapper.swap(quote: quote, inVault: <-sourceLiquidity)
        }
    }
}
