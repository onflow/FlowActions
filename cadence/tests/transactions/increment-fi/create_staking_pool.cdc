import "Staking"
import "SwapConfig"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(
    limitAmount: UFix64,
    stakingVaultType: Type,
    rewardInfo: [Staking.RewardInfo],
    rewardTokenVaultStoragePath: StoragePath?,
    depositAmount: UFix64?
) {
    prepare(acct: auth(Capabilities, Storage) &Account) {        
        let poolCollection = acct.storage.borrow<&Staking.StakingPoolCollection>(from: Staking.CollectionStoragePath)
            ?? panic("Could not borrow reference to Staking Pool Collection")

        let adminRef = acct.storage.borrow<&Staking.Admin>(from: Staking.StakingAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")
        let poolAdminRef = acct.storage.borrow<&Staking.PoolAdmin>(from: Staking.PoolAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")

        let contractRef = getAccount(stakingVaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: stakingVaultType.contractName!)!
        
        let pid = Staking.poolCount
        poolCollection.createStakingPool(
            adminRef: adminRef,
            poolAdminAddr: poolAdminRef.owner!.address,
            limitAmount: limitAmount,
            vault: <- contractRef.createEmptyVault(vaultType: stakingVaultType),
            rewards: rewardInfo
        )

        if let amount = depositAmount {
            if let storagePath = rewardTokenVaultStoragePath {
                let tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: storagePath)
                    ?? panic("Could not borrow reference to Token Vault")

                poolCollection.getPool(pid: pid).extendReward(rewardTokenVault: <- tokenVaultRef.withdraw(amount: amount))
            }
        }
    }
}