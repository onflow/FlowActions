import "FungibleToken"
import "FungibleTokenMetadataViews"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "DeFiActions"
import "CrossVMConnectors"

/// Withdraws the given amount from the signer's unified balance (Cadence vault + COA) via a
/// CrossVMConnectors.UnifiedBalanceSource connector
///
/// @param amount: The maximum amount to withdraw
/// @param withdrawVaultIdentifier: The type identifier of the vault to withdraw from
/// @param to: The address to deposit withdrawn funds; if nil, the signer's vault will receive the funds
///
transaction(amount: UFix64, withdrawVaultIdentifier: String, to: Address?) {
    /// the type of the withdraw token
    let withdrawVaultType: Type
    /// the receiver of the withdrawn funds
    let receiver: &{FungibleToken.Vault}
    /// the balance of the recipient before the withdrawal
    let receiverBeforeBal: UFix64
    /// the Source to withdraw the funds from
    let source: {DeFiActions.Source}
    /// the available amount to withdraw from the Source
    let available: UFix64

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // get the withdraw token type
        self.withdrawVaultType = CompositeType(withdrawVaultIdentifier)
            ?? panic("Invalid withdraw token identifier: \(withdrawVaultIdentifier)")

        // get the FTVaultData for the withdraw token type
        let vaultData = getAccount(self.withdrawVaultType.address!).contracts.borrow<&{FungibleToken}>(
                name: self.withdrawVaultType.contractName!
            )!.resolveContractView(
                resourceType: self.withdrawVaultType,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData
            ?? panic("Could not resolve FTVaultData for \(self.withdrawVaultType.identifier)")

        // get the receiver Vault
        if to == nil {
            self.receiver = signer.capabilities.borrow<&{FungibleToken.Vault}>(vaultData.receiverPath)
                ?? panic("Could not find vault in recipient's capabilities at path \(vaultData.receiverPath)")
        } else {
            self.receiver = getAccount(to!).capabilities.borrow<&{FungibleToken.Vault}>(vaultData.receiverPath)
                ?? panic("Could not find vault in recipient's capabilities at path \(vaultData.receiverPath)")
        }
        // get the balance before the withdrawal
        self.receiverBeforeBal = self.receiver.balance

        // issue capability on the signer's Cadence vault
        let cadenceVaultCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            vaultData.storagePath
        )

        // issue capability on the signer's COA
        let storagePath = /storage/evm
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Withdraw, EVM.Bridge) &EVM.CadenceOwnedAccount>(storagePath)

        // issue capability for fee provision
        let feeProviderCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(
            /storage/flowTokenVault
        )

        // Calculate available Cadence balance
        // For FlowToken, use availableBalance to account for storage reservation
        // For other tokens, use vault balance
        let availableCadenceBalance: UFix64 = self.withdrawVaultType == Type<@FlowToken.Vault>()
            ? signer.availableBalance
            : (signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath)?.balance ?? 0.0)

        // create the UnifiedBalanceSource
        self.source = CrossVMConnectors.UnifiedBalanceSource(
            vaultType: self.withdrawVaultType,
            cadenceVault: cadenceVaultCap,
            coa: coaCap,
            feeProvider: feeProviderCap,
            availableCadenceBalance: availableCadenceBalance,
            uniqueID: nil
        )
        self.available = self.source.minimumAvailable()
    }

    pre {
        // check that the Source provides the withdraw token type
        self.source.getSourceType() == self.withdrawVaultType:
        "Source must provide \(self.withdrawVaultType.identifier) but found \(self.source.getSourceType().identifier)"
    }

    execute {
        let withdrawal <- self.source.withdrawAvailable(maxAmount: amount)
        self.receiver.deposit(from: <-withdrawal)
    }
}
