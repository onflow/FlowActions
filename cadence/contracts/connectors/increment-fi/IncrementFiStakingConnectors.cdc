import "DeFiActions"
import "DeFiActionsUtils"
import "FungibleToken"
import "Staking"
import "SwapConfig"

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
        /// The unique identifier of the staking pool to deposit into
        access(self) let poolID: UInt64
        /// Capability to access the user's staking certificate
        access(self) let userCertificate: Capability<&Staking.UserCertificate>
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolSink
        ///
        /// @param userCertificate: Capability to access the user's staking certificate
        /// @param poolID: The unique identifier of the staking pool to deposit into
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            poolID: UInt64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
            let poolCollectionCollection = poolCollectionCap.borrow() ?? panic("Could not borrow reference to Staking Pool")
            let pool = poolCollectionCollection.getPool(pid: poolID)

            self.vaultType = CompositeType(pool.getPoolInfo().acceptTokenKey.concat(".Vault"))!
            self.poolID = poolID
            self.userCertificate = userCertificate
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
            if let address = self.userCertificate.borrow()?.owner?.address {
                if let pool = self.borrowPool() {
                    // Get the staking amount for the user in the pool
                    let stakingAmount = pool.getUserInfo(address: address)?.stakingAmount ?? 0.0
                    return pool.getPoolInfo().limitAmount - stakingAmount
                }
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

            if let pool = self.borrowPool() {
                if let address = self.userCertificate.borrow()?.owner?.address {
                    let depositAmount = from.balance < minimumCapacity
                        ? from.balance
                        : minimumCapacity
                    
                    pool.stake(staker: address, stakingToken: <- from.withdraw(amount: depositAmount))
                }
            }
        }

        /// Helper function to borrow a reference to the staking pool
        ///
        /// @return a reference to the staking pool, or nil if not available
        ///
        access(self) fun borrowPool(): &{Staking.PoolPublic}? {
            let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
            return poolCollectionCap.borrow()?.getPool(pid: self.poolID)
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
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        /// Initializes a new PoolRewardsSource
        ///
        /// @param userCertificate: Capability to access the user's staking certificate
        /// @param poolID: The unique identifier of the staking pool to claim rewards from
        /// @param vaultType: The type of Vault this Source provides when claiming rewards
        /// @param uniqueID: Optional identifier for associating connectors in a stack
        ///
        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            poolID: UInt64,
            vaultType: Type,
            uniqueID: DeFiActions.UniqueIdentifier?,
        ) {
            self.poolID = poolID
            self.userCertificate = userCertificate
            self.uniqueID = uniqueID
            self.vaultType = vaultType
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
                if let pool = self.borrowPool() {
                    // Get the remaining staking capacity for the user in the pool
                    let stakingAmount = (pool.getUserInfo(address: address)?.stakingAmount) ?? 0.0
                    return pool.getPoolInfo().limitAmount - stakingAmount
                }
            }

            return 0.0 // no capacity if the staking pool is not available
        }

        /// Withdraws rewards from the staking pool up to the specified maximum amount
        ///
        /// @param maxAmount: The maximum amount of rewards to claim
        /// @return a Vault containing the claimed rewards
        ///
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            let minimumAvailable = self.minimumAvailable()
            if minimumAvailable == 0.0 {
                return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
            }

            if let pool = self.borrowPool() {
                if let userCertificate = self.userCertificate.borrow() {
                    let withdrawAmount = maxAmount < minimumAvailable
                        ? maxAmount
                        : minimumAvailable

                    let rewards <- pool.claimRewards(userCertificate: userCertificate)
                    let vaultRewards <- rewards.remove(key: SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.vaultType.identifier))
                    if rewards.keys.length == 0 {
                        destroy rewards
                    } else {
                        panic("Staking pool rewards contain multiple token types, which is not supported by this connector")
                    }
                    
                    if vaultRewards != nil {
                        return <- vaultRewards!
                    } else {
                        destroy vaultRewards
                        return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
                    }
                }
            }

            return <- DeFiActionsUtils.getEmptyVault(self.getSourceType())
        }

        /// Helper function to borrow a reference to the staking pool
        ///
        /// @return a reference to the staking pool, or nil if not available
        ///
        access(self) fun borrowPool(): &{Staking.PoolPublic}? {
            let poolCollectionCap = getAccount(Type<Staking>().address!).capabilities.get<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)
            return poolCollectionCap.borrow()?.getPool(pid: self.poolID)
        }
    }
}