import "DeFiActions"
import "DeFiActionsUtils"
import "FungibleToken"
import "Staking"
import "SwapConfig"

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
        access(self) let poolID: UInt64
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolSink
        ///
        /// @param poolID: The unique identifier of the staking pool to deposit into
        /// @param staker: Address of the user staking in the pool
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            poolID: UInt64,
            staker: Address,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
            let poolCollectionRef = poolCollectionCap.borrow() ?? panic("Could not borrow reference to Staking Pool")
            let pool = poolCollectionRef.getPool(pid: poolID)

            self.vaultType = CompositeType(pool.getPoolInfo().acceptTokenKey.concat(".Vault"))!
            self.staker = staker
            self.poolID = poolID
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
            if let pool = IncrementFiStakingConnectors.borrowPool(poolID: self.poolID) {
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

            if let pool: &{Staking.PoolPublic} = IncrementFiStakingConnectors.borrowPool(poolID: self.poolID) {
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
    access(all) struct PoolRewardsSource: DeFiActions.Source {
        /// The type of Vault this Source provides when claiming rewards
        access(all) let vaultType: Type
        /// The unique identifier of the staking pool to claim rewards from
        access(self) let poolID: UInt64
        /// Capability to access the user's staking certificate
        access(self) let userCertificate: Capability<&Staking.UserCertificate>
        /// The set of overflow sinks to handle any excess rewards that cannot be handled by this Source
        access(self) let overflowSinks: {Type: {DeFiActions.Sink}}
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolRewardsSource
        ///
        /// @param userCertificate: Capability to access the user's staking certificate
        /// @param poolID: The unique identifier of the staking pool to claim rewards from
        /// @param vaultType: The type of Vault this Source provides when claiming rewards
        /// @param overflowSinks: A set of DeFiActions.Sink to handle any overflow from the rewards claim
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            poolID: UInt64,
            vaultType: Type,
            overflowSinks: {Type: {DeFiActions.Sink}},
            uniqueID: DeFiActions.UniqueIdentifier?,
        ) {
            self.poolID = poolID
            self.userCertificate = userCertificate
            self.vaultType = vaultType
            self.overflowSinks = overflowSinks
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
                if let pool = IncrementFiStakingConnectors.borrowPool(poolID: self.poolID) {
                    // Stake an empty vault on behalf of the user to update the pool
                    // The Staking contract does not expose any way to update the unclaimed rewards
                    // field, so staking an empty vault is a workaround to update the unclaimed rewards
                    let emptyVault <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
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

            if let pool = IncrementFiStakingConnectors.borrowPool(poolID: self.poolID) {
                if let userCertificate = self.userCertificate.borrow() {
                    let withdrawAmount = maxAmount < minimumAvailable
                        ? maxAmount
                        : minimumAvailable

                    let rewards <- pool.claimRewards(userCertificate: userCertificate)
                    var targetRewards: @{FungibleToken.Vault}? <- nil
                    let targetSliceType = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.vaultType.identifier)
                    for sliceType in rewards.keys {
                        let reward <- rewards.remove(key: sliceType)!
                        if sliceType == targetSliceType {
                            if reward.balance > withdrawAmount {
                                targetRewards <-! reward.withdraw(amount: withdrawAmount)
                                if let overflowSink = self.overflowSinks[CompositeType(sliceType.concat(".Vault"))!] {
                                    overflowSink.depositCapacity(from: &reward as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                                    assert(reward.balance == 0.0, message: "Overflow sink should consume all rewards for type \(sliceType).Vault")
                                    destroy reward
                                } else {
                                    panic("No overflow sink found for slice type \(sliceType)")
                                }
                            } else {
                                targetRewards <-! reward
                            }
                        } else if let overflowSink = self.overflowSinks[CompositeType(sliceType.concat(".Vault"))!] {
                            overflowSink.depositCapacity(from: &reward as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                            assert(reward.balance == 0.0, message: "Overflow sink should consume all rewards for type \(sliceType).Vault")
                            destroy reward
                        } else {
                            panic("No overflow sink found for slice type \(sliceType)")
                        }
                    }

                    if targetRewards != nil {
                        destroy rewards
                        return <- targetRewards!
                    } else {
                        destroy rewards
                        destroy targetRewards
                        return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
                    }
                }
            }

            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }
    }

    /// Helper function to borrow a reference to the staking pool
    ///
    /// @return a reference to the staking pool, or nil if not available
    ///
    access(all) fun borrowPool(poolID: UInt64): &{Staking.PoolPublic}? {
        let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
        return poolCollectionCap.borrow()?.getPool(pid: poolID)
    }
}