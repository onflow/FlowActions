import "DeFiActions"
import "DeFiActionsUtils"
import "FungibleToken"
import "Staking"
import "SwapConfig"

access(all) contract IncrementFiStack {
    access(all) struct StakingPoolSink: DeFiActions.Sink {
        /// The type of Vault this Sink accepts when performing a deposit
        access(all) let vaultType: Type
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        access(self) let poolID: UInt64
        access(self) let stakingPool: Capability<&{Staking.PoolCollectionPublic}>
        access(self) let userCertificate: Capability<&Staking.UserCertificate>

        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            stakingPool: Capability<&{Staking.PoolCollectionPublic}>,
            poolID: UInt64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            let stakingPoolCollection = stakingPool.borrow() ?? panic("Could not borrow reference to Staking Pool")
            let pool = stakingPoolCollection.getPool(pid: poolID)

            self.vaultType = CompositeType(pool.getPoolInfo().acceptTokenKey.concat(".Vault"))!
            self.poolID = poolID
            self.stakingPool = stakingPool
            self.uniqueID = uniqueID
            self.userCertificate = userCertificate
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the VaultSink
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
        access(all) view fun getSinkType(): Type {
            // TODO: we could lazy load this from the pool info
            // but we would have to return some kind of filler type
            // or error (which I don't think is desired)
            return self.vaultType
        }

        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        access(all) fun minimumCapacity(): UFix64 {
            if let address = self.userCertificate.borrow()?.owner?.address {
                if let pool = self.borrowPool() {
                    // Get the staking amount for the user in the pool
                    let stakingAmount = (pool.getUserInfo(address: address) ?? nil)?.stakingAmount ?? 0.0
                    return pool.getPoolInfo().limitAmount - stakingAmount
                }
            }

            return 0.0 // no capacity if the staking pool is not available
        }

        /// Deposits up to the Sink's capacity from the provided Vault
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

        access(self) fun borrowPool(): &{Staking.PoolPublic}? {
            return self.stakingPool.borrow()?.getPool(pid: self.poolID)
        }
    }

    access(all) struct StakingPoolRewardsSource: DeFiActions.Source {
        /// The type of Vault this Sink accepts when performing a deposit
        access(all) let vaultType: Type
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        access(self) let poolID: UInt64
        access(self) let stakingPool: Capability<&{Staking.PoolCollectionPublic}>
        access(self) let userCertificate: Capability<&Staking.UserCertificate>

        init(
            userCertificate: Capability<&Staking.UserCertificate>,
            stakingPool: Capability<&{Staking.PoolCollectionPublic}>,
            poolID: UInt64,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            let stakingPoolCollection = stakingPool.borrow() ?? panic("Could not borrow reference to Staking Pool")
            let pool = stakingPoolCollection.getPool(pid: poolID)
            self.vaultType = CompositeType(pool.getPoolInfo().acceptTokenKey.concat(".Vault"))!
            self.poolID = poolID
            self.stakingPool = stakingPool
            self.uniqueID = uniqueID
            self.userCertificate = userCertificate
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component in the VaultSink
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
        access(all) view fun getSourceType(): Type {
            return self.vaultType
        }

        /// Returns an estimate of how much of the associated Vault can be accepted by this Sink
        access(all) fun minimumAvailable(): UFix64 {
            if let address = self.userCertificate.borrow()?.owner?.address {
                if let pool = self.borrowPool() {
                    // Get the staking amount for the user in the pool
                    let stakingAmount = (pool.getUserInfo(address: address)?.stakingAmount) ?? 0.0
                    return pool.getPoolInfo().limitAmount - stakingAmount
                }
            }

            return 0.0 // no capacity if the staking pool is not available
        }

        /// Deposits up to the Sink's capacity from the provided Vault
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
                    destroy rewards
                    
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

        access(self) fun borrowPool(): &{Staking.PoolPublic}? {
            return self.stakingPool.borrow()?.getPool(pid: self.poolID)
        }
    }
}