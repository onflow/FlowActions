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
        let assetEVMAddress = ERC4626Utils.underlyingAssetEVMAddress(vault: vaultEVMAddress)
            ?? panic("Cannot get an underlying asset EVM address from the vault")
        let assetType = FlowEVMBridgeConfig.getTypeAssociated(with: assetEVMAddress)
                ?? panic("Invalid asset vault identifier: \(assetEVMAddress.toString())")

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
            assetType: assetType,
            vaultEVMAddress: vaultEVMAddress,
            coa: coaCap,
            feeSource: feeSource,
            uniqueID: nil
        )

        // Withdraw the required asset amount from the user's asset vault
        let shareProvider = acct.storage.borrow<
            auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
        >(from: /storage/EVMVMBridgedToken_d069d989e2f44b70c65347d1853c0c67e10a9f8dVault)
            ?? panic("Missing underlying asset vault at /storage/assetVault (update to your actual storage path)")

        let residual <- shareProvider.withdraw(amount: swapAmount)

        // Perform swap: assets -> ERC4626 shares
        let outVault <- swapper.swapBack(
            quote: nil,
            residual: <-residual
        )

        // Deposit received shares somewhere (update to your actual shares receiver path)
        let assetReceiver = acct.capabilities.borrow<&{FungibleToken.Receiver}>(/public/EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750Vault)
            ?? panic("Could not borrow receiver reference")

        assetReceiver.deposit(from: <-outVault)
	}

	execute{
	}

}
