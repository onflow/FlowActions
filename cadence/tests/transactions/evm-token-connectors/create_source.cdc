import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "FungibleTokenConnectors"
import "EVMTokenConnectors"

/// Creates an EVMTokenConnectors.Source and saves it to storage
transaction(
    sourceMin: UFix64?,
    uniqueID: DeFiActions.UniqueIdentifier?,
    vaultTypeIdentifier: String,
) {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController) &Account) {
        let vaultType = CompositeType(vaultTypeIdentifier)
            ?? panic("Invalid vault type identifier: \(vaultTypeIdentifier)")

        // Get the COA capability
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Bridge) &EVM.CadenceOwnedAccount>(/storage/evm)

        // Create a fee source using FungibleTokenConnectors.VaultSinkAndSource
        let feeVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            /storage/flowTokenVault
        )
        let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: feeVault,
            uniqueID: nil
        )

        // Create Source
        let source = EVMTokenConnectors.Source(
            min: sourceMin,
            withdrawVaultType: vaultType,
            coa: coaCap,
            feeSource: feeSource,
            uniqueID: uniqueID
        )
        signer.storage.save(source, to: /storage/evmTokenSource)
    }
}