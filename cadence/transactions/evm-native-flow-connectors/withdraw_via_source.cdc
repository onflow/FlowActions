import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "EVMNativeFLOWConnectors"

/// Withdraws the given amount of FLOW from the signer's CadenceOwnedAccount's native FLOW balance via a 
/// EVMNativeFLOWConnectors.Source connector
///
/// @param sourceMin: The minimum amount of FLOW for the EVM address to hold beyond which the Source will not withdraw
///      if nil, there will be no minimum balance for the EVM address
/// @param amount: The amount of FLOW to withdraw
/// @param to: The address to deposit withdrawn funds; if nil, the signer's FlowToken Vault will receive the funds
///
transaction(sourceMin: UFix64?, amount: UFix64, to: Address?) {
    /// the receiver of the withdrawn funds
    let receiver: &{FungibleToken.Vault}
    /// the EVM-native FLOW balance of the recipient before the deposit
    let receiverBeforeBal: UFix64
    /// the Source to withdraw the funds from
    let source: {DeFiActions.Source}
    /// the available amount of FLOW to withdraw from the Source
    let available: UFix64

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        let publicPath = /public/flowTokenReceiver
        if to == nil {
            self.receiver = signer.capabilities.borrow<&{FungibleToken.Vault}>(publicPath)
                ?? panic("Could not find FlowToken Vault in recipient's capabilities at path \(publicPath)")
        } else {
            self.receiver = getAccount(to!).capabilities.borrow<&{FungibleToken.Vault}>(publicPath)
                ?? panic("Could not find FlowToken Vault in recipient's capabilities at path \(publicPath)")
        }
        // get the FLOW balance before the deposit
        self.receiverBeforeBal = self.receiver.balance


        let storagePath = /storage/evm
        let coa = signer.capabilities.storage.issue<auth(EVM.Withdraw) &EVM.CadenceOwnedAccount>(storagePath)
        let coaRef = coa.borrow()!

        // create the Source
        self.source = EVMNativeFLOWConnectors.Source(
            min: sourceMin,
            coa: coa,
            uniqueID: nil
        )
        self.available = self.source.minimumAvailable()
    }

    pre {
        // check that the Source provides FLOW
        self.source.getSourceType() == Type<@FlowToken.Vault>():
        "Source must provide FLOW but found \(self.source.getSourceType().identifier)"
    }

    post {
        // check that the recipient's EVM address has the expected balance after the deposit
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
