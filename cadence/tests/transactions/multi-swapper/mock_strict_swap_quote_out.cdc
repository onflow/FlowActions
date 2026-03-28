import "FungibleToken"

import "TokenA"
import "TokenB"

import "DeFiActions"
import "SwapConnectors"
import "MockSwapper"

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

        self.inVault <- tokenAVault.withdraw(amount: amountIn)

        let inCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenA.VaultStoragePath)
        let outCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(TokenB.VaultStoragePath)

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

        self.expectedOut = amountIn * priceRatio > maxOut ? maxOut : amountIn * priceRatio
    }

    execute {
        let outVault <- self.multiSwapper.swap(quote: nil, inVault: <-self.inVault)
        assert(outVault.balance == self.expectedOut, message: "Unexpected output amount")
        self.tokenBReceiver.deposit(from: <-outVault)
    }
}
