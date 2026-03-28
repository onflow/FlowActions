import "FungibleToken"

import "TokenA"
import "TokenB"

import "DeFiActions"
import "FungibleTokenConnectors"
import "SwapConnectors"
import "MockSwapper"

transaction(maxAmount: UFix64, quoteInOvershoot: UFix64) {
    let swapSource: SwapConnectors.SwapSource
    let tokenBReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, Capabilities, BorrowValue) &Account) {
        self.tokenBReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(TokenB.ReceiverPublicPath)
            ?? panic("Missing TokenB receiver")

        let inCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenA.VaultStoragePath)
        let outCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenB.VaultStoragePath)

        let source = FungibleTokenConnectors.VaultSource(
            min: nil,
            withdrawVault: inCap,
            uniqueID: nil
        )

        let multiSwapper = SwapConnectors.MultiSwapper(
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

        self.swapSource = SwapConnectors.SwapSource(
            swapper: multiSwapper,
            source: source,
            uniqueID: nil
        )
    }

    execute {
        let outVault <- self.swapSource.withdrawAvailable(maxAmount: maxAmount)
        assert(outVault.balance == maxAmount, message: "SwapSource withdrawAvailable exceeded maxAmount")
        self.tokenBReceiver.deposit(from: <-outVault)
    }
}
