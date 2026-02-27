import "FungibleToken"
import "FungibleTokenMetadataViews"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "EVMTokenConnectors"

/// Withdraws the given amount of FLOW from the signer's CadenceOwnedAccount's native FLOW balance via a 
/// EVMNativeFlowConnectors.Source connector
///
/// @param sourceMin: The minimum amount of FLOW for the EVM address to hold beyond which the Source will not withdraw
///      if nil, there will be no minimum balance for the EVM address
/// @param amount: The amount of FLOW to withdraw
/// @param to: The address to deposit withdrawn funds; if nil, the signer's FlowToken Vault will receive the funds
///
transaction(sourceMin: UFix64?, amount: UFix64, withdrawVaultIdentifier: String, to: Address?) {
    /// the type of the withdraw token
    let withdrawVaultType: Type
    /// the EVM address associated with the withdraw token type
    let erc20Address: EVM.EVMAddress
    /// the receiver of the withdrawn funds
    let receiver: &{FungibleToken.Vault}
    /// the balance of the recipient before the withdrawal
    let receiverBeforeBal: UFix64
    /// the Source to withdraw the funds from
    let source: {DeFiActions.Source}
    /// the available amount of FLOW to withdraw from the Source
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
                ?? panic("Could not find FlowToken Vault in recipient's capabilities at path \(vaultData.receiverPath)")
        } else {
            self.receiver = getAccount(to!).capabilities.borrow<&{FungibleToken.Vault}>(vaultData.receiverPath)
                ?? panic("Could not find FlowToken Vault in recipient's capabilities at path \(vaultData.receiverPath)")
        }
        // get the balance before the withdrawal
        self.receiverBeforeBal = self.receiver.balance

        // get the EVM address associated with the withdraw token type
        self.erc20Address = FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.withdrawVaultType)
            ?? panic("Withdraw token type \(self.withdrawVaultType.identifier) has not been onboarded to the VM bridge - Ensure the Cadence token type is associated with an EVM contract via the VM bridge")

        // get the signer's CadenceOwnedAccount
        let storagePath = /storage/evm
        let coa = signer.capabilities.storage.issue<auth(EVM.Bridge) &EVM.CadenceOwnedAccount>(storagePath)

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

        // create the token Source
        self.source = EVMTokenConnectors.Source(
            min: sourceMin,
            withdrawVaultType: self.withdrawVaultType,
            coa: coa,
            feeSource: feeSource,
            uniqueID: nil
        )
        self.available = self.source.minimumAvailable()
    }

    pre {
        // check that the Source provides the withdraw token type
        self.source.getSourceType() == self.withdrawVaultType:
        "Source must provide \(self.withdrawVaultType.identifier) but found \(self.source.getSourceType().identifier)"
    }

    post {
        // check that the recipient's EVM address has the expected balance after the withdrawal
        self.available >= amount
            ? self.receiver.balance == self.receiverBeforeBal + amount
            : self.receiver.balance == self.receiverBeforeBal + self.available:
        "Deposit of \(amount) FLOW to \(self.receiver.owner!.address) failed"
    }

    execute {
        let withdrawal <- self.source.withdrawAvailable(maxAmount: amount)
        self.receiver.deposit(from: <-withdrawal)
    }
}
