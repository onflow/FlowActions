import "DeFiActions"
import "DeFiActionsUtils"
import "FungibleToken"
import "Staking"
import "SwapConfig"
import "SwapInterfaces"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// IncrementFiStakingConnectors
///
/// DeFiActions adapter implementations for IncrementFi staking protocols. This contract provides connectors that
/// integrate with IncrementFi's staking pools, allowing users to stake tokens and claim rewards through the
/// DeFiActions framework.
///
/// The contract contains two main connector types:
/// - PoolSink: Allows depositing tokens into IncrementFi staking pools
/// - PoolRewardsSource: Allows claiming rewards from IncrementFi staking pools
///
access(all) contract IncrementFiStakingConnectors {
    /// PoolSink
    ///
    /// A DeFiActions.Sink implementation that allows depositing tokens into IncrementFi staking pools.
    /// This connector accepts tokens of a specific type and stakes them in the designated staking pool.
    ///
    access(all) struct PoolSink: DeFiActions.Sink {
        /// The type of Vault this Sink accepts when performing a deposit
        access(all) let vaultType: Type
        /// Address of the user staking in the pool
        access(self) let staker: Address
        /// The unique identifier of the staking pool to deposit into
        access(self) let pid: UInt64
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolSink
        ///
        /// @param pid: The unique identifier of the staking pool to deposit into
        /// @param staker: Address of the user staking in the pool
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            pid: UInt64,
            staker: Address,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
                ?? panic("Pool with ID \(pid) not found or not accessible")

            self.vaultType = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pool.getPoolInfo().acceptTokenKey)
            self.staker = staker
            self.pid = pid
            self.uniqueID = uniqueID
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the PoolSink
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        /// Returns the Vault type accepted by this Sink
        ///
        /// @return the type of Vault this Sink accepts when performing a deposit
        ///
        access(all) view fun getSinkType(): Type {
            return self.vaultType
        }

        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        ///
        /// @return the minimum capacity available for deposits to this Sink
        ///
        access(all) fun minimumCapacity(): UFix64 {
            if let pool = IncrementFiStakingConnectors.borrowPool(pid: self.pid) {
                // Get the staking amount for the user in the pool
                let stakingAmount = pool.getUserInfo(address: self.staker)?.stakingAmount ?? 0.0
                return pool.getPoolInfo().limitAmount - stakingAmount
            }

            return 0.0 // no capacity if the staking pool is not available
        }

        /// Deposits up to the Sink's capacity from the provided Vault
        ///
        /// @param from: The vault to withdraw tokens from for staking
        ///
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            let minimumCapacity = self.minimumCapacity()
            if minimumCapacity == 0.0 {
                return
            }

            if let pool: &{Staking.PoolPublic} = IncrementFiStakingConnectors.borrowPool(pid: self.pid) {
                let depositAmount = from.balance < minimumCapacity
                    ? from.balance
                    : minimumCapacity

                pool.stake(staker: self.staker, stakingToken: <- from.withdraw(amount: depositAmount))
            }
        }
    }

    /// PoolRewardsSource
    ///
    /// A DeFiActions.Source implementation that allows claiming rewards from IncrementFi staking pools.
    /// This connector provides tokens by claiming rewards from the designated staking pool.
    ///
    /// NOTE: This connector assumes that the pool has only one reward token type. If the pool has multiple reward
    /// token types, the connector will panic.
    ///
    access(all) struct PoolRewardsSource: DeFiActions.Source {
        /// The type of Vault this Source provides when claiming rewards
        access(all) let vaultType: Type
        /// The unique identifier of the staking pool to claim rewards from
        access(self) let pid: UInt64
        /// Capability to access the user's staking certificate
        access(self) let userCertificate: Capability<&Staking.UserCertificate>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolRewardsSource
        ///
        /// @param userCertificate: Capability to access the user's staking certificate
        /// @param pid: The unique identifier of the staking pool to claim rewards from
        /// @param vaultType: The type of Vault this Source provides when claiming rewards
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            pid: UInt64,
            uniqueID: DeFiActions.UniqueIdentifier?,
        ) {
            let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
                ?? panic("Pool with ID \(pid) not found")
            let rewardsInfo = pool.getPoolInfo().rewardsInfo

            assert(rewardsInfo.keys.length == 1, message: "Pool with ID \(pid) has multiple reward token types, only one is supported")
            let rewardTokenType = rewardsInfo.keys[0]

            self.pid = pid
            self.userCertificate = userCertificate
            self.vaultType = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(rewardTokenType)
            self.uniqueID = uniqueID
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the PoolRewardsSource
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
            )
        }

        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        /// Returns the Vault type provided by this Source
        ///
        /// @return the type of Vault this Source provides when claiming rewards
        ///
        access(all) view fun getSourceType(): Type {
            return self.vaultType
        }

        /// Returns an estimate of how much of the associated rewards can be claimed from this Source
        ///
        /// @return the minimum amount of rewards available for claiming from this Source
        ///
        access(all) fun minimumAvailable(): UFix64 {
            if let address = self.userCertificate.borrow()?.owner?.address {
                if let pool = IncrementFiStakingConnectors.borrowPool(pid: self.pid) {
                    // Stake an empty vault on behalf of the user to update the pool
                    // The Staking contract does not expose any way to update the unclaimed rewards
                    // field, so staking an empty vault is a workaround to update the unclaimed rewards
                    let emptyVault <- DeFiActionsUtils.getEmptyVault(IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pool.getPoolInfo().acceptTokenKey))
                    pool.stake(staker: address, stakingToken: <- emptyVault)
                    if let unclaimedRewards = pool.getUserInfo(address: address)?.unclaimedRewards {
                        // Return the unclaimed rewards for the specific vault type
                        return unclaimedRewards[SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.vaultType.identifier)] ?? 0.0
                    }
                }
            }

            return 0.0 // no capacity if the staking pool is not available
        }

        /// Withdraws rewards from the staking pool up to the specified maximum amount
        /// Overflow rewards are sent to the appropriate overflow sinks if provided
        ///
        /// @param maxAmount: The maximum amount of rewards to claim
        /// @return a Vault containing the claimed rewards
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let minimumAvailable = self.minimumAvailable()
            if minimumAvailable == 0.0 {
                return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
            }

            if let pool = IncrementFiStakingConnectors.borrowPool(pid: self.pid) {
                if let userCertificate = self.userCertificate.borrow() {
                    let withdrawAmount = maxAmount < minimumAvailable
                        ? maxAmount
                        : minimumAvailable

                    let rewards <- pool.claimRewards(userCertificate: userCertificate)
                    let targetSliceType = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.vaultType.identifier)
                    
                    assert(rewards.keys.length <= 1, message: "Pool with ID \(self.pid) has multiple reward token types, only one is supported")

                    if rewards.keys.length == 0 {
                        destroy rewards
                        return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
                    }

                    assert(
                        rewards.keys[0] == targetSliceType,
                        message: "Reward token type \(rewards.keys[0]) is not supported by this Source instance (poolID: \(self.pid), instance sourceType: \(self.vaultType.identifier)). This instance can only claim \(targetSliceType) rewards."
                    )
                    let reward <- rewards.remove(key: rewards.keys[0])!
                    destroy rewards
                    return <- reward
                }
            }

            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }
    }

    /// Helper function to borrow a reference to the staking pool
    ///
    /// @return a reference to the staking pool, or nil if not available
    ///
    access(all) fun borrowPool(pid: UInt64): &{Staking.PoolPublic}? {
        let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
        return poolCollectionCap.borrow()?.getPool(pid: pid)
    }

    /// Helper function to borrow a reference to the pair public interface
    ///
    /// @param pid: The pool ID to borrow the pair public interface for
    /// @return a reference to the pair public interface
    ///
    access(all) fun borrowPairPublicByPid(pid: UInt64): &{SwapInterfaces.PairPublic}? {
        let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
        if pool == nil {
            return nil
        }

        let pair = getAccount(IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pool!.getPoolInfo().acceptTokenKey).address!)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
        
        return pair
    }

    /// Helper function to convert a token type identifier to a vault type
    /// E.g. "A.0x1234567890.USDC" -> Type("A.0x1234567890.USDC.Vault")
    ///
    /// @param tokenType: The token type identifier to convert to a vault type
    /// @return the vault type
    ///
    access(all) fun tokenTypeIdentifierToVaultType(_ tokenType: String): Type {
        return CompositeType("\(tokenType).Vault")!
    }
}