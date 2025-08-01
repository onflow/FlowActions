import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "TokenA"

transaction(pid: UInt64, amount: UFix64) {
    let poolCollectionCap: Capability<&{Staking.PoolCollectionPublic}>
    let tokenAVaultRef: auth(FungibleToken.Withdraw) &TokenA.Vault
    let stakerAddress: Address
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)

        self.tokenAVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &TokenA.Vault>(from: TokenA.VaultStoragePath)
            ?? panic("Could not borrow reference to TokenA Vault")

        self.stakerAddress = acct.address
    }

    execute {
        self.poolCollectionCap.borrow()!
            .getPool(pid: pid)
            .stake(staker: self.stakerAddress, stakingToken: <- self.tokenAVaultRef.withdraw(amount: amount))
    }
}