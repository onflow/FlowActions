import "FungibleToken"
import "FungibleTokenMetadataViews"
import "FlowToken"

import "FungibleTokenStack"

transaction(receiver: Address, vaultPublicPath: PublicPath, sinkStoragePath: StoragePath, min: UFix64?, max: UFix64?) {

    let depositVault: Capability<&{FungibleToken.Vault}>
    let signer: auth(SaveValue) &Account

    prepare(signer: auth(SaveValue) &Account) {
        // Get the Vault capability
        self.depositVault = getAccount(receiver).capabilities.get<&{FungibleToken.Vault}>(vaultPublicPath)

        // Assign the account reference to save in execute
        self.signer = signer
    }

    pre {
        min == nil || max == nil: "Can only specify a min or max for a VaultSink, not both"
        self.signer.storage.type(at: sinkStoragePath) == nil:
        "Collision at sinkStoragePath \(sinkStoragePath.toString())"
    }

    execute {
        var capacityCheck: {FungibleTokenStack.CapacityCheck}? = nil
        if min != nil {
            capacityCheck = FungibleTokenStack.MinimumCapacityCheck(min: min!)
        } else if max != nil {
            capacityCheck = FungibleTokenStack.MaximumCapacityCheck(max: max!)
        }

        let sink = FungibleTokenStack.VaultSink(
                capacityCheck: capacityCheck,
                depositVault: self.depositVault
            )
        self.signer.storage.save(sink, to: sinkStoragePath)
    }

    post {
        self.signer.storage.type(at: sinkStoragePath) == Type<FungibleTokenStack.VaultSink>():
        "VaultSink was not stored to sinkStoragePath \(sinkStoragePath.toString())"
    }
}