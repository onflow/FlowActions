import "Burner"
import "FungibleToken"

import "DeFiActions"
import "DeFiActionsUtils"

/// TEST-ONLY mock swapper that withdraws output from a user-provided Vault capability.
/// Do NOT use in production.
access(all) contract MockSwapper {

    access(all) struct BasicQuote : DeFiActions.Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64
        init(inType: Type, outType: Type, inAmount: UFix64, outAmount: UFix64) {
            self.inType = inType
            self.outType = outType
            self.inAmount = inAmount
            self.outAmount = outAmount
        }
    }

    access(all) struct Swapper : DeFiActions.Swapper {
        access(self) let inVault: Type
        access(self) let outVault: Type
        access(self) let inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let priceRatio: UFix64 // out per unit in
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            inVault: Type,
            outVault: Type,
            inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            priceRatio: UFix64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "inVault must be a FungibleToken Vault"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "outVault must be a FungibleToken Vault"
                inVaultSource.check(): "Invalid inVaultSource capability"
                outVaultSource.check(): "Invalid outVaultSource capability"
                priceRatio > 0.0: "Invalid price ratio"
            }
            self.inVault = inVault
            self.outVault = outVault
            self.inVaultSource = inVaultSource
            self.outVaultSource = outVaultSource
            self.priceRatio = priceRatio
            self.uniqueID = uniqueID
        }

        access(all) view fun inType(): Type { return self.inVault }
        access(all) view fun outType(): Type { return self.outVault }

        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            log(reverse ? "\(self.outType().identifier) -> \(self.inType().identifier)" : "\(self.inType().identifier) -> \(self.outType().identifier)")
            let inAmt = reverse ? forDesired * self.priceRatio : forDesired / self.priceRatio
            log("MockSwapper quoteIn - forDesired: \(forDesired) | reverse: \(reverse) | inAmt: \(inAmt)")
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: inAmt,
                outAmount: forDesired
            )
        }

        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            log(reverse ? "\(self.outType().identifier) -> \(self.inType().identifier)" : "\(self.inType().identifier) -> \(self.outType().identifier)")
            let outAmt = reverse ? forProvided / self.priceRatio : forProvided * self.priceRatio
            log("MockSwapper quoteOut - forProvided: \(forProvided) | reverse: \(reverse) | outAmt: \(outAmt)")
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: forProvided,
                outAmount: outAmt
            )
        }

        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { inVault.getType() == self.inType(): "Wrong in type \(inVault.getType().identifier) - expected \(self.inType().identifier)" }
            let outAmt = (quote?.outAmount) ?? (inVault.balance * self.priceRatio)

            // deposit tokens back to the outVaultSource
            let depositTo = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-inVault)

            // withdraw tokens from the inVaultSource & return
            let src = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: outAmt)
        }

        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { residual.getType() == self.outType(): "Wrong out type \(residual.getType().identifier) - expected \(self.outType().identifier)" }
            let inAmt = (quote?.inAmount) ?? (residual.balance / self.priceRatio)

            // deposit tokens back to the inVaultSource
            let depositTo = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-residual)

            // withdraw tokens from the outVaultSource & return
            let src = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            log("MockSwapper swapBack returning: \(src.getType().identifier)")
            return <- src.withdraw(amount: inAmt)
        }

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(type: self.getType(), id: self.id(), innerComponents: [])
        }
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? { return self.uniqueID }
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) { self.uniqueID = id }
    }

    /// TEST-ONLY capacity-limited swapper. Caps outAmount at maxOut in both quoteIn and quoteOut.
    /// Do NOT use in production.
    access(all) struct CapLimitedSwapper : DeFiActions.Swapper {
        access(self) let inVault: Type
        access(self) let outVault: Type
        access(self) let inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let priceRatio: UFix64 // out per unit in
        access(self) let maxOut: UFix64     // maximum output this swapper can deliver
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            inVault: Type,
            outVault: Type,
            inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            priceRatio: UFix64,
            maxOut: UFix64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "inVault must be a FungibleToken Vault"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "outVault must be a FungibleToken Vault"
                inVaultSource.check(): "Invalid inVaultSource capability"
                outVaultSource.check(): "Invalid outVaultSource capability"
                priceRatio > 0.0: "Invalid price ratio"
                maxOut > 0.0: "Invalid maxOut"
            }
            self.inVault = inVault
            self.outVault = outVault
            self.inVaultSource = inVaultSource
            self.outVaultSource = outVaultSource
            self.priceRatio = priceRatio
            self.maxOut = maxOut
            self.uniqueID = uniqueID
        }

        access(all) view fun inType(): Type { return self.inVault }
        access(all) view fun outType(): Type { return self.outVault }

        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let actualOut = forDesired > self.maxOut ? self.maxOut : forDesired
            let inAmt = reverse ? actualOut * self.priceRatio : actualOut / self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: inAmt,
                outAmount: actualOut
            )
        }

        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let rawOut = reverse ? forProvided / self.priceRatio : forProvided * self.priceRatio
            let actualOut = rawOut > self.maxOut ? self.maxOut : rawOut
            let actualIn = reverse ? actualOut * self.priceRatio : actualOut / self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: actualIn,
                outAmount: actualOut
            )
        }

        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { inVault.getType() == self.inType(): "Wrong in type \(inVault.getType().identifier) - expected \(self.inType().identifier)" }
            let outAmt = (quote?.outAmount) ?? (inVault.balance * self.priceRatio)
            let depositTo = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-inVault)
            let src = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: outAmt)
        }

        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { residual.getType() == self.outType(): "Wrong out type \(residual.getType().identifier) - expected \(self.outType().identifier)" }
            let inAmt = (quote?.inAmount) ?? (residual.balance / self.priceRatio)
            let depositTo = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-residual)
            let src = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: inAmt)
        }

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(type: self.getType(), id: self.id(), innerComponents: [])
        }
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? { return self.uniqueID }
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) { self.uniqueID = id }
    }

    /// TEST-ONLY strict capacity-limited swapper. Behaves like CapLimitedSwapper, but
    /// also enforces that swaps do not exceed quote.inAmount.
    access(all) struct StrictCapLimitedSwapper : DeFiActions.Swapper {
        access(self) let inVault: Type
        access(self) let outVault: Type
        access(self) let inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let priceRatio: UFix64
        access(self) let maxOut: UFix64
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            inVault: Type,
            outVault: Type,
            inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            priceRatio: UFix64,
            maxOut: UFix64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "inVault must be a FungibleToken Vault"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "outVault must be a FungibleToken Vault"
                inVaultSource.check(): "Invalid inVaultSource capability"
                outVaultSource.check(): "Invalid outVaultSource capability"
                priceRatio > 0.0: "Invalid price ratio"
                maxOut > 0.0: "Invalid maxOut"
            }
            self.inVault = inVault
            self.outVault = outVault
            self.inVaultSource = inVaultSource
            self.outVaultSource = outVaultSource
            self.priceRatio = priceRatio
            self.maxOut = maxOut
            self.uniqueID = uniqueID
        }

        access(all) view fun inType(): Type { return self.inVault }
        access(all) view fun outType(): Type { return self.outVault }

        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let actualOut = forDesired > self.maxOut ? self.maxOut : forDesired
            let inAmt = reverse ? actualOut * self.priceRatio : actualOut / self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: inAmt,
                outAmount: actualOut
            )
        }

        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let rawOut = reverse ? forProvided / self.priceRatio : forProvided * self.priceRatio
            let actualOut = rawOut > self.maxOut ? self.maxOut : rawOut
            let actualIn = reverse ? actualOut * self.priceRatio : actualOut / self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: actualIn,
                outAmount: actualOut
            )
        }

        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { inVault.getType() == self.inType(): "Wrong in type \(inVault.getType().identifier) - expected \(self.inType().identifier)" }
            let appliedQuote = quote ?? self.quoteOut(forProvided: inVault.balance, reverse: false)
            // Special behavior for this mock: reject swaps whose input is larger than quote.inAmount.
            assert(inVault.balance <= appliedQuote.inAmount, message: "Swap input exceeds quote.inAmount")

            let depositTo = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-inVault)

            let src = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: appliedQuote.outAmount)
        }

        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { residual.getType() == self.outType(): "Wrong out type \(residual.getType().identifier) - expected \(self.outType().identifier)" }
            let appliedQuote = quote ?? self.quoteOut(forProvided: residual.balance, reverse: true)
            // Same strict check in reverse, so swapBack also fails on quote/input mismatch.
            assert(residual.balance <= appliedQuote.inAmount, message: "SwapBack input exceeds quote.inAmount")

            let depositTo = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-residual)

            let src = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: appliedQuote.outAmount)
        }

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(type: self.getType(), id: self.id(), innerComponents: [])
        }
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? { return self.uniqueID }
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) { self.uniqueID = id }
    }

    /// TEST-ONLY swapper that returns a quoteIn outAmount above the requested amount.
    access(all) struct QuoteInOvershootSwapper : DeFiActions.Swapper {
        access(self) let inVault: Type
        access(self) let outVault: Type
        access(self) let inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>
        access(self) let priceRatio: UFix64
        access(self) let quoteInOvershoot: UFix64
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            inVault: Type,
            outVault: Type,
            inVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            outVaultSource: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            priceRatio: UFix64,
            quoteInOvershoot: UFix64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            pre {
                inVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "inVault must be a FungibleToken Vault"
                outVault.isSubtype(of: Type<@{FungibleToken.Vault}>()): "outVault must be a FungibleToken Vault"
                inVaultSource.check(): "Invalid inVaultSource capability"
                outVaultSource.check(): "Invalid outVaultSource capability"
                priceRatio > 0.0: "Invalid price ratio"
                quoteInOvershoot >= 0.0: "Invalid quoteInOvershoot"
            }
            self.inVault = inVault
            self.outVault = outVault
            self.inVaultSource = inVaultSource
            self.outVaultSource = outVaultSource
            self.priceRatio = priceRatio
            self.quoteInOvershoot = quoteInOvershoot
            self.uniqueID = uniqueID
        }

        access(all) view fun inType(): Type { return self.inVault }
        access(all) view fun outType(): Type { return self.outVault }

        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let inAmt = reverse ? forDesired * self.priceRatio : forDesired / self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: inAmt,
                // Special behavior for this mock: quoteIn intentionally reports more out than requested.
                outAmount: forDesired + self.quoteInOvershoot
            )
        }

        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let outAmt = reverse ? forProvided / self.priceRatio : forProvided * self.priceRatio
            return BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: forProvided,
                outAmount: outAmt
            )
        }

        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { inVault.getType() == self.inType(): "Wrong in type \(inVault.getType().identifier) - expected \(self.inType().identifier)" }
            let outAmt = (quote?.outAmount) ?? (inVault.balance * self.priceRatio)
            let depositTo = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-inVault)
            let src = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: outAmt)
        }

        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre { residual.getType() == self.outType(): "Wrong out type \(residual.getType().identifier) - expected \(self.outType().identifier)" }
            let inAmt = (quote?.inAmount) ?? (residual.balance / self.priceRatio)
            let depositTo = self.outVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            depositTo.deposit(from: <-residual)
            let src = self.inVaultSource.borrow() ?? panic("Invalid borrowed vault source")
            return <- src.withdraw(amount: inAmt)
        }

        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(type: self.getType(), id: self.id(), innerComponents: [])
        }
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? { return self.uniqueID }
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) { self.uniqueID = id }
    }
}
