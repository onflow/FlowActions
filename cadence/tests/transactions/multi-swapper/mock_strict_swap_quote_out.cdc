import "FungibleToken"

import "TokenA"
import "TokenB"

import "DeFiActions"
import "SwapConnectors"
import "MockSwapper"

/// Regression test:
/// MultiSwapper.swap(quote: nil, ...) should still succeed when the selected
/// inner route enforces `input <= quote.inAmount`.
/// Args:
/// - amountIn: TokenA sent into MultiSwapper
/// - priceRatio: TokenB out per 1 TokenA in
/// - maxOut: output cap enforced by the inner route
transaction(amountIn: UFix64, priceRatio: UFix64, maxOut: UFix64) {
    let tokenBReceiver: &{FungibleToken.Receiver}
    let multiSwapper: SwapConnectors.MultiSwapper
    let expectedOut: UFix64
    let inVault: @{FungibleToken.Vault}

    prepare(signer: auth(Storage, Capabilities, BorrowValue) &Account) {
        let tokenAVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &TokenA.Vault>(from: TokenA.VaultStoragePath)
            ?? panic("Missing TokenA vault")
        self.tokenBReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(TokenB.ReceiverPublicPath)
            ?? panic("Missing TokenB receiver")

        // Withdraw test input from the account's TokenA vault.
        self.inVault <- tokenAVault.withdraw(amount: amountIn)

        let inCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenA.VaultStoragePath)
        let outCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenB.VaultStoragePath)

        // Single-route MultiSwapper using a strict capped inner swapper.
        self.multiSwapper = SwapConnectors.MultiSwapper(
            inVault: Type<@TokenA.Vault>(),
            outVault: Type<@TokenB.Vault>(),
            swappers: [
                MockSwapper.StrictCapLimitedSwapper(
                    inVault: Type<@TokenA.Vault>(),
                    outVault: Type<@TokenB.Vault>(),
                    inVaultSource: inCap,
                    outVaultSource: outCap,
                    priceRatio: priceRatio,
                    maxOut: maxOut,
                    uniqueID: nil
                )
            ],
            uniqueID: nil
        )

        // Expected output = min(amountIn * priceRatio, maxOut).
        self.expectedOut = amountIn * priceRatio > maxOut ? maxOut : amountIn * priceRatio
    }

    execute {
        // This call used to fail if MultiSwapper forwarded a quote whose
        // inAmount no longer matched the provided vault balance.
        let outVault <- self.multiSwapper.swap(quote: nil, inVault: <-self.inVault)
        assert(outVault.balance == self.expectedOut, message: "Unexpected output amount")
        self.tokenBReceiver.deposit(from: <-outVault)
    }
}
