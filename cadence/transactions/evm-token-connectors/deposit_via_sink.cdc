import "FungibleToken"
import "FungibleTokenMetadataViews"
import "FlowToken"
import "EVM"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "DeFiActions"
import "FungibleTokenConnectors"
import "EVMTokenConnectors"

/// Deposits the given amount of the deposit token type to the given EVM address via a EVMTokenConnectors.Sink
///
/// @param sinkMax: The maximum amount of FLOW the EVM address can hold; if nil, the Sink will deposit any balance
/// @param amount: The amount of FLOW to deposit
/// @param depositVaultIdentifier: The identifier of the deposit token type
/// @param evmAddressHex: The EVM address of the recipient as a hex string
///
transaction(sinkMax: UFix64?, amount: UFix64, depositVaultIdentifier: String, evmAddressHex: String) {
    /// the type of the deposit token
    let depositVaultType: Type
    /// the EVM address associated with the deposit token type
    let erc20Address: EVM.EVMAddress
    /// the EVM address of the recipient
    let recipient: EVM.EVMAddress
    /// the EVM-native FLOW balance of the recipient before the deposit
    let beforeBalance: UFix64
    /// the EVM-native FLOW balance of the recipient after the deposit
    var afterBalance: UFix64
    /// the funds to deposit to the recipient via the Sink
    let funds: @{FungibleToken.Vault}
    /// the Sink to deposit the funds to
    let sink: {DeFiActions.Sink}
    /// the capacity of the Sink
    let capacity: UFix64

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // get the EVM address associated with the deposit token type
        self.depositVaultType = CompositeType(depositVaultIdentifier)
            ?? panic("Invalid deposit token identifier: \(depositVaultIdentifier)")
        self.erc20Address = FlowEVMBridgeConfig.getEVMAddressAssociated(with: self.depositVaultType)
            ?? panic("Deposit token type \(self.depositVaultType.identifier) has not been onboarded to the VM bridge - "
                .concat("Ensure the Cadence token type is associated with an EVM contract via the VM bridge"))

        // deserialize the EVM address from the hex string & get the EVM-native balance of the recipient before the deposit
        self.recipient = EVM.addressFromString(evmAddressHex)
        self.beforeBalance = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                FlowEVMBridgeUtils.balanceOf(owner: self.recipient, evmContractAddress: self.erc20Address),
                erc20Address: self.erc20Address
            )
        // initialize the afterBalance to compare in post-assertion
        self.afterBalance = 0.0

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
        
        // create the token Sink
        self.sink = EVMTokenConnectors.Sink(
            max: sinkMax,
            depositVaultType: self.depositVaultType,
            address: self.recipient,
            feeSource: feeSource,
            uniqueID: nil
        )
        
        // get the signer's token Vault
        let vaultData = getAccount(self.depositVaultType.address!).contracts.borrow<&{FungibleToken}>(name: self.depositVaultType.contractName!)!
                .resolveContractView(
                    resourceType: self.depositVaultType,
                    viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
                ) as? FungibleTokenMetadataViews.FTVaultData
                ?? panic("Could not resolve FTVaultData for \(self.depositVaultType.identifier)")
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: vaultData.storagePath)
            ?? panic("Could not find FlowToken Vault in signer's storage at path \(vaultData.storagePath)")

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
    }

    post {
        // check that the recipient's EVM address has the expected balance after the deposit
        self.capacity >= amount
            ? self.afterBalance == self.beforeBalance + amount
            : self.afterBalance == self.beforeBalance + self.capacity:
        "Deposit of \(amount) FLOW to \(self.recipient.toString()) failed"
    }

    execute {
        // deposit the funds to the token Sink if there are any
        if self.funds.balance > 0.0 {
            self.sink.depositCapacity(from: &self.funds as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            assert(self.funds.balance == 0.0,
                message: "Expected 0.0 FLOW in signer's FlowToken Vault after deposit to Sink but found \(self.funds.balance)")
        }
        // update the afterBalance
        self.afterBalance = FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(
                FlowEVMBridgeUtils.balanceOf(owner: self.recipient, evmContractAddress: self.erc20Address),
                erc20Address: self.erc20Address
            )
        // destroy the empty Vault
        destroy self.funds
    }
}
