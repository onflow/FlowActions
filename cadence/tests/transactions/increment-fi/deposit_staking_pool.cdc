import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "FungibleTokenMetadataViews"
import "SwapConfig"
import "SwapFactory"
import "SwapInterfaces"

transaction(pid: UInt64, amount: UFix64, vaultType: Type) {
    let poolCollectionCap: Capability<&{Staking.PoolCollectionPublic}>
    let stakerAddress: Address
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
        self.stakerAddress = acct.address

        // Create a user certificate for the staker
        if acct.storage.check<@Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) == false {
            destroy <- acct.storage.load<@AnyResource>(from: Staking.UserCertificateStoragePath)
            acct.storage.save(<-Staking.setupUser(), to: Staking.UserCertificateStoragePath)
        }

        let pair = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
        let isLpToken = pair != nil
        var tokenVault: @{FungibleToken.Vault}? <- nil
        if isLpToken {
            let lpTokenCollectionStoragePath = SwapConfig.LpTokenCollectionStoragePath
            let lpTokenCollectionPublicPath = SwapConfig.LpTokenCollectionPublicPath
            var lpTokenCollectionRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &SwapFactory.LpTokenCollection>(from: lpTokenCollectionStoragePath)
            if lpTokenCollectionRef == nil {
                destroy <- acct.storage.load<@AnyResource>(from: lpTokenCollectionStoragePath)
                acct.storage.save(<-SwapFactory.createEmptyLpTokenCollection(), to: lpTokenCollectionStoragePath)
                let lpTokenCollectionCap = acct.capabilities.storage.issue<&{SwapInterfaces.LpTokenCollectionPublic}>(lpTokenCollectionStoragePath)
                acct.capabilities.publish(lpTokenCollectionCap, at: lpTokenCollectionPublicPath)
                lpTokenCollectionRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &SwapFactory.LpTokenCollection>(from: lpTokenCollectionStoragePath)
            }

            let vault <- lpTokenCollectionRef!.withdraw(pairAddr: pair!.owner!.address, amount: amount)
            tokenVault <-! vault
        } else {
            let ftVaultData = getAccount(vaultType.address!)
                .contracts
                .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
                .resolveContractView(
                    resourceType: nil,
                    viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
                )! as! FungibleTokenMetadataViews.FTVaultData

            let tokenVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
                ?? panic("Could not borrow reference to TokenA Vault")
            tokenVault <-! tokenVaultRef.withdraw(amount: amount)
        }

         self.poolCollectionCap.borrow()!
            .getPool(pid: pid)
            .stake(staker: self.stakerAddress, stakingToken: <- tokenVault!)
    }
}