import "FungibleToken"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"
import "UniswapV3SwapConnectors"

/// Provisions PYUSD by swapping MOET from testTokenInVault via V3.
/// After this transaction, testTokenInVault contains PYUSD.
///
/// Expects MOET in /storage/testTokenInVault (from mintMOETToTestVault).
///
transaction(
    factoryAddr: String,
    routerAddr: String,
    quoterAddr: String,
    moetAddr: String,
    pyusdAddr: String,
    fee: UInt32,
    swapAmount: UFix64
) {
    prepare(signer: auth(Storage, IssueStorageCapabilityController, BorrowValue) &Account) {
        let coaCap = signer.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)

        let factory = EVM.addressFromString(factoryAddr)
        let router  = EVM.addressFromString(routerAddr)
        let quoter  = EVM.addressFromString(quoterAddr)
        let moet    = EVM.addressFromString(moetAddr)
        let pyusd   = EVM.addressFromString(pyusdAddr)

        let moetVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: moet)
            ?? panic("MOET not in bridge config")
        let pyusdVaultType = FlowEVMBridgeConfig.getTypeAssociated(with: pyusd)
            ?? panic("PYUSD not in bridge config")

        let swapper = UniswapV3SwapConnectors.Swapper(
            factoryAddress: factory,
            routerAddress: router,
            quoterAddress: quoter,
            tokenPath: [moet, pyusd],
            feePath: [fee],
            inVault: moetVaultType,
            outVault: pyusdVaultType,
            coaCapability: coaCap,
            uniqueID: nil
        )

        // Load MOET vault and withdraw swapAmount
        let moetVault <- signer.storage.load<@{FungibleToken.Vault}>(from: /storage/testTokenInVault)
            ?? panic("No vault at /storage/testTokenInVault")

        let moetIn <- moetVault.withdraw(amount: swapAmount)
        destroy moetVault

        // Swap MOET→PYUSD (quote=nil triggers auto-quote)
        let pyusdVault <- swapper.swap(quote: nil, inVault: <-moetIn)
        log("Provisioned \(pyusdVault.balance.toString()) PYUSD from \(swapAmount.toString()) MOET")

        signer.storage.save(<-pyusdVault, to: /storage/testTokenInVault)
    }
}
