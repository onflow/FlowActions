import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(pid: UInt64, amount: UFix64, vaultType: Type) {
    let poolCollectionCap: Capability<&{Staking.PoolCollectionPublic}>
    let tokenVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let stakerAddress: Address
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)

        let ftVaultData = getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
            .resolveContractView(
                resourceType: nil,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            )! as! FungibleTokenMetadataViews.FTVaultData

        self.tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("Could not borrow reference to TokenA Vault")

        self.stakerAddress = acct.address
    }

    execute {
        self.poolCollectionCap.borrow()!
            .getPool(pid: pid)
            .stake(staker: self.stakerAddress, stakingToken: <- self.tokenVaultRef.withdraw(amount: amount))
    }
}