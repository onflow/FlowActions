import "FungibleToken"

import "TokenA"
import "TokenB"

transaction(swapPairCode: String) {
    prepare(signer: auth(AddContract) &Account) {
        let _ = signer.contracts.add(
            name: "SwapPair",
            code: swapPairCode.decodeHex(),
            tokenAVault: <- TokenA.createEmptyVault(vaultType: Type<@TokenA.Vault>()),
            tokenBVault: <- TokenB.createEmptyVault(vaultType: Type<@TokenB.Vault>()),
            stableMode: false
        )
    }
}
