import "Staking"
import "SwapConfig"
import "TokenA"

transaction(
    limitAmount: UFix64,
    vaultType: Type,
    rewardInfo: [Staking.RewardInfo]
) {
    prepare(acct: auth(Capabilities, Storage) &Account) {        
        let poolCollection = acct.storage.borrow<&Staking.StakingPoolCollection>(from: Staking.CollectionStoragePath)
            ?? panic("Could not borrow reference to Staking Pool Collection")

        let adminRef = acct.storage.borrow<&Staking.Admin>(from: Staking.StakingAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")
        let poolAdminRef = acct.storage.borrow<&Staking.PoolAdmin>(from: Staking.PoolAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")
        
        let pid = Staking.poolCount
        poolCollection.createStakingPool(
            adminRef: adminRef,
            poolAdminAddr: poolAdminRef.owner!.address,
            limitAmount: limitAmount,
            vault: <- TokenA.createEmptyVault(vaultType: vaultType),
            rewards: rewardInfo
        )
    }
}