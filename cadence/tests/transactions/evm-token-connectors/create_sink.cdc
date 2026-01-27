import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "FungibleTokenConnectors"
import "EVMTokenConnectors"

/// Creates an EVMTokenConnectors.Sink and saves it to storage
transaction(
    sinkMax: UFix64?,
    uniqueID: DeFiActions.UniqueIdentifier?,
    vaultTypeIdentifier: String, 
    evmAddressHex: String,
    storagePath: StoragePath
) {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController) &Account) {
        let vaultType = CompositeType(vaultTypeIdentifier)
            ?? panic("Invalid vault type identifier: \(vaultTypeIdentifier)")
        
        let evmAddress = EVM.addressFromString(evmAddressHex)

        // create the fee source that pays the VM bridge fees
        let feeVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                /storage/flowTokenVault
            )
        let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: feeVault,
            uniqueID: nil
        )

        // Create Sink
        let sink = EVMTokenConnectors.Sink(
            max: sinkMax,
            depositVaultType: vaultType,
            address: evmAddress,
            feeSource: feeSource,
            uniqueID: uniqueID
        )
        signer.storage.save(sink, to: storagePath)
    }
}