import "FungibleToken"
import "Staking"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "SwapStack"
import "DeFiActions"
import "SwapConfig"

transaction(pid: UInt64, vaultType: Type) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let pool: &{Staking.PoolPublic}
    let userInfoStart: Staking.UserInfo

    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        self.pool = getAccount(Type<Staking>().address!).capabilities.borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)?.getPool(pid: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")
        self.userInfoStart = self.pool.getUserInfo(address: acct.address) ?? panic("No user info found for address \(acct.address)")

        var userCertificateCap: Capability<&Staking.UserCertificate>? = nil
        if acct.storage.check<@Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) {
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        } else {
            acct.storage.save(<- Staking.setupUser(), to: Staking.UserCertificateStoragePath)
            self.userCertificateCap = acct.capabilities.storage.issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        }
    }

    pre {
        // Verify that the user has a valid certificate capability
        self.userCertificateCap.check(): "User certificate capability is invalid or not found"
        // Verify that the vault type is valid and defined by a FungibleToken contract
        self.userInfoStart.unclaimedRewards[SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: vaultType.identifier)] != nil: "User must have unclaimed rewards for the specified vault type"
        // Verify that the user has unclaimed rewards for the specified vault type
        self.userInfoStart.unclaimedRewards[SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: vaultType.identifier)]! > 0.0: "User must have unclaimed rewards greater than zero for the specified vault type"
    }

    execute {
        // Create the PoolRewardsSource
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: vaultType,
            uniqueID: nil
        )

        // Create the zapper to swap rewards to LP tokens
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: Type<@{FungibleToken.Vault}>(),
            token1Type: Type<@{FungibleToken.Vault}>(),
            stableMode: false,
            uniqueID: nil
        )

        // Create the SwapSource that uses the zapper to convert rewards to LP tokens
        let lpTokenPoolRewardsSource = SwapStack.SwapSource(
            swapper: zapper,
            source: poolRewardsSource,
            uniqueID: nil
        )

        // Create the sink where the rewards will be deposited 
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            staker: self.userCertificateCap.address,
            poolID: pid,
            uniqueID: nil
        )

        // Deposit the LP tokens into the pool sink
        let vault <- lpTokenPoolRewardsSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        assert(vault.balance == 0.0, message: "TokenA Vault should be empty after withdrawal")
        destroy vault
    }

    post {
        // Verify that all rewards have been claimed
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.unclaimedRewards[SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: vaultType.identifier)] == 0.0
        // Verify that the user's staked amount has increased
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount > self.userInfoStart.stakingAmount
    }
}