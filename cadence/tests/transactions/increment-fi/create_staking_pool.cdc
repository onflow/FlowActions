import "Staking"
import "SwapConfig"
import "FungibleToken"
import "FungibleTokenMetadataViews"

transaction(
    limitAmount: UFix64,
    vaultType: Type,
    rewardInfo: [Staking.RewardInfo],
    depositAmount: UFix64
) {
    prepare(acct: auth(Capabilities, Storage) &Account) {        
        let poolCollection = acct.storage.borrow<&Staking.StakingPoolCollection>(from: Staking.CollectionStoragePath)
            ?? panic("Could not borrow reference to Staking Pool Collection")

        let adminRef = acct.storage.borrow<&Staking.Admin>(from: Staking.StakingAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")
        let poolAdminRef = acct.storage.borrow<&Staking.PoolAdmin>(from: Staking.PoolAdminStoragePath)
            ?? panic("Could not borrow reference to Staking Admin")

        let ftContract = getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
        let ftVaultData = ftContract
            .resolveContractView(
                resourceType: nil,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            )! as! FungibleTokenMetadataViews.FTVaultData

        let tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("Could not borrow reference to Token Vault")
        
        let pid = Staking.poolCount
        poolCollection.createStakingPool(
            adminRef: adminRef,
            poolAdminAddr: poolAdminRef.owner!.address,
            limitAmount: limitAmount,
            vault: <- ftContract.createEmptyVault(vaultType: vaultType),
            rewards: rewardInfo
        )

        poolCollection.getPool(pid: pid).extendReward(rewardTokenVault: <- tokenVaultRef.withdraw(amount: depositAmount))
    }
}