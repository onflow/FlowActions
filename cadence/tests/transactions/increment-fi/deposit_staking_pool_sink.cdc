import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(pid: UInt64, vaultType: Type) {
    let incrementFiSink: IncrementFiStakingConnectors.PoolSink
    let tokenVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

    prepare(acct: auth(BorrowValue) &Account) {
        self.incrementFiSink = IncrementFiStakingConnectors.PoolSink(
            poolID: pid,
            staker: acct.address,
            uniqueID: nil
        )

        let ftVaultData = getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
            .resolveContractView(
                resourceType: nil,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            )! as! FungibleTokenMetadataViews.FTVaultData

        self.tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("Could not borrow reference to TokenA Vault")
    }
    
    execute {
        self.incrementFiSink.depositCapacity(
            from: self.tokenVaultRef
        )
    }
}