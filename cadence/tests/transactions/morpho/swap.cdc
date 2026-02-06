import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"

import "DeFiActions"
import "ERC4626Utils"
import "FungibleTokenConnectors"

import "MorphoERC4626SwapConnectors"

transaction (
    vaultEVMAddressHex: String,
    swapAmount: UFix64
) {
	prepare(acct: auth(Storage, Capabilities, BorrowValue) &Account){
        let vaultEVMAddress = EVM.addressFromString(vaultEVMAddressHex)

        let coaCap = acct.capabilities.storage.issue<auth(EVM.Owner, EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(/storage/evm)
        let feeVault = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            /storage/flowTokenVault
        )
        let feeSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: feeVault,
            uniqueID: nil
        )
        let swapper = MorphoERC4626SwapConnectors.Swapper(
            vaultEVMAddress: vaultEVMAddress,
            coa: coaCap,
            feeSource: feeSource,
            uniqueID: nil,
            isReverse: false
        )

        // Withdraw the required asset amount from the user's asset vault
        let assetProvider = acct.storage.borrow<
            auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
        >(from: /storage/EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750Vault)
            ?? panic("Missing underlying asset vault at /storage/assetVault (update to your actual storage path)")

        let inVault <- assetProvider.withdraw(amount: swapAmount)

        // Perform swap: assets -> ERC4626 shares
        let outVault <- swapper.swap(
            quote: nil,
            inVault: <-inVault
        )

        // Deposit received shares somewhere (update to your actual shares receiver path)
        let sharesReceiver = acct.capabilities.borrow<&{FungibleToken.Receiver}>(/public/EVMVMBridgedToken_d069d989e2f44b70c65347d1853c0c67e10a9f8dVault)
            ?? panic("Could not borrow receiver reference")

        sharesReceiver.deposit(from: <-outVault)
	}

	execute{
	}

}
