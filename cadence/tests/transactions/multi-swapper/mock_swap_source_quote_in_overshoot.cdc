import "FungibleToken"

import "TokenA"
import "TokenB"

import "FungibleTokenConnectors"
import "SwapConnectors"
import "MockSwapper"

/// Regression test:
/// SwapSource.withdrawAvailable(maxAmount) must not return more than maxAmount
/// even if the chosen route's quoteIn reports a slightly larger outAmount.
transaction(maxAmount: UFix64, quoteInOvershoot: UFix64) {
    let swapSource: SwapConnectors.SwapSource
    let tokenBReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, Capabilities, BorrowValue) &Account) {
        self.tokenBReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(TokenB.ReceiverPublicPath)
            ?? panic("Missing TokenB receiver")

        let inCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenA.VaultStoragePath)
        let outCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenB.VaultStoragePath)

        // Source of TokenA liquidity to be wrapped by SwapSource.
        let source = FungibleTokenConnectors.VaultSource(
            min: nil,
            withdrawVault: inCap,
            uniqueID: nil
        )
        // MultiSwapper with a single route whose quoteIn intentionally
        // overshoots the requested outAmount.
        let swapper = SwapConnectors.MultiSwapper(
            inVault: Type<@TokenA.Vault>(),
            outVault: Type<@TokenB.Vault>(),
            swappers: [
                MockSwapper.QuoteInOvershootSwapper(
                    inVault: Type<@TokenA.Vault>(),
                    outVault: Type<@TokenB.Vault>(),
                    inVaultSource: inCap,
                    outVaultSource: outCap,
                    priceRatio: 1.0,
                    quoteInOvershoot: quoteInOvershoot,
                    uniqueID: nil
                )
            ],
            uniqueID: nil
        )

        // SwapSource is the integration point that previously leaked the
        // overshoot back to callers.
        self.swapSource = SwapConnectors.SwapSource(
            swapper: swapper,
            source: source,
            uniqueID: nil
        )
    }

    execute {
        let outVault <- self.swapSource.withdrawAvailable(maxAmount: maxAmount)
        // The returned vault must still be capped to the caller's request.
        assert(outVault.balance == maxAmount, message: "SwapSource withdrawAvailable exceeded maxAmount")
        self.tokenBReceiver.deposit(from: <-outVault)
    }
}
