import "FungibleToken"
import "FlowToken"
import "EVM"
import "DeFiActions"
import "EVMNativeFLOWConnectors"

/// Deposits the given amount of FLOW to the given EVM address via a EVMNativeFLOWConnectors.Sink
///
/// @param sinkMax: The maximum amount of FLOW the EVM address can hold; if nil, the Sink will deposit any balance
/// @param amount: The amount of FLOW to deposit
/// @param evmAddressHex: The EVM address of the recipient as a hex string
///
transaction(sinkMax: UFix64?, amount: UFix64, evmAddressHex: String) {
    /// the EVM address of the recipient
    let recipient: EVM.EVMAddress
    /// the EVM-native FLOW balance of the recipient before the deposit
    let beforeBalance: UFix64
    /// the funds to deposit to the recipient via the Sink
    let funds: @{FungibleToken.Vault}
    /// the Sink to deposit the funds to
    let sink: {DeFiActions.Sink}
    /// the capacity of the Sink
    let capacity: UFix64

    prepare(signer: auth(BorrowValue) &Account) {
        // deserialize the EVM address from the hex string & get the FLOW balance before the deposit
        self.recipient = EVM.addressFromString(evmAddressHex)
        self.beforeBalance = self.recipient.balance().inFLOW()

        // create the Sink
        self.sink = EVMNativeFLOWConnectors.Sink(
            max: sinkMax,
            address: self.recipient,
            uniqueID: nil
        )
        
        // get the signer's FlowToken Vault
        let storagePath = /storage/flowTokenVault
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: storagePath)
            ?? panic("Could not find FlowToken Vault in signer's storage at path \(storagePath)")

        // withdraw the funds from the signer's FlowToken Vault
        self.capacity = self.sink.minimumCapacity()
        let withdrawAmount = amount < self.capacity ? amount : self.capacity
        self.funds <- vault.withdraw(amount: withdrawAmount)
    }

    pre {
        // check that the signer's FlowToken Vault has the expected balance
        self.capacity >= amount
            ? self.funds.balance == amount
            : self.funds.balance == self.capacity:
        "Invalid funds balance of \(self.funds.balance) FLOW found before deposit to Sink"
        // check that the funds are FLOW
        self.funds.getType() == Type<@FlowToken.Vault>():
        "Signer's FlowToken Vault must be a FlowToken.Vault"
    }

    post {
        // check that the recipient's EVM address has the expected balance after the deposit
        self.capacity >= amount
            ? self.recipient.balance().inFLOW() == self.beforeBalance + amount
            : self.recipient.balance().inFLOW() == self.beforeBalance + self.capacity:
        "Deposit of \(amount) FLOW to \(self.recipient.toString()) failed"
    }

    execute {
        // deposit the funds to the Sink if there are any
        if self.funds.balance > 0.0 {
            self.sink.depositCapacity(from: &self.funds as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            assert(self.funds.balance == 0.0,
                message: "Expected 0.0 FLOW in signer's FlowToken Vault after deposit to Sink but found \(self.funds.balance)")
        }
        // destroy the empty Vault
        destroy self.funds
    }
}
