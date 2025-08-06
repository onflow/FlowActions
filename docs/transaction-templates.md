# Transaction Templates

## Basic Transfer Template

### Vault to Vault Transfer
```cadence
import "FungibleToken"
import "FungibleTokenStack"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    amount: UFix64,
    maxCapacity: UFix64
) {
    let source: FungibleTokenStack.VaultSource
    let sink: FungibleTokenStack.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        self.source = FungibleTokenStack.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.sink = FungibleTokenStack.VaultSink(
            max: maxCapacity,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.source.withdrawAvailable(maxAmount: amount)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Transfer incomplete")
        destroy vault
    }

    pre {
        amount > 0.0: "Amount must be positive"
    }
}
```

## Staking Templates

### Stake Tokens
```cadence
import "FungibleToken"
import "FungibleTokenStack"
import "IncrementFiStakingConnectors"

transaction(
    sourceStoragePath: StoragePath,
    staker: Address,
    poolID: UInt64,
    amount: UFix64
) {
    let source: FungibleTokenStack.VaultSource
    let sink: IncrementFiStakingConnectors.PoolSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        self.source = FungibleTokenStack.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.sink = IncrementFiStakingConnectors.PoolSink(
            staker: staker,
            poolID: poolID,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.source.withdrawAvailable(maxAmount: amount)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Staking incomplete")
        destroy vault
    }

    pre {
        amount > 0.0: "Stake amount must be positive"
        poolID > 0: "Pool ID must be valid"
    }
}
```

### Claim Rewards
```cadence
import "FungibleToken"
import "FungibleTokenStack"
import "IncrementFiStakingConnectors"
import "Staking"

transaction(
    poolID: UInt64,
    rewardTokenType: Type,
    targetVaultCap: Capability<&{FungibleToken.Vault}>
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let rewardSource: IncrementFiStakingConnectors.PoolRewardsSource
    let sink: FungibleTokenStack.VaultSink

    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)

        self.rewardSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: poolID,
            vaultType: rewardTokenType,
            overflowSinks: {},
            uniqueID: nil
        )

        self.sink = FungibleTokenStack.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.rewardSource.withdrawAvailable(maxAmount: UFix64.max)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Reward claim incomplete")
        destroy vault
    }
}
```

## Swap Templates

### Single Token Swap
```cadence
import "FungibleToken"
import "FungibleTokenStack"
import "SwapStack"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    swapper: {DeFiActions.Swapper},
    amount: UFix64
) {
    let swapSource: SwapStack.SwapSource
    let sink: FungibleTokenStack.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        let source = FungibleTokenStack.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.swapSource = SwapStack.SwapSource(
            swapper: swapper,
            source: source,
            uniqueID: nil
        )

        self.sink = FungibleTokenStack.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.swapSource.withdrawAvailable(maxAmount: amount)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Swap incomplete")
        destroy vault
    }

    pre {
        amount > 0.0: "Swap amount must be positive"
    }
}
```

### Zap to LP Tokens
```cadence
import "FungibleToken"
import "FungibleTokenStack"
import "SwapStack"
import "IncrementFiPoolLiquidityConnectors"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    token0Type: Type,
    token1Type: Type,
    stableMode: Bool,
    amount: UFix64
) {
    let swapSource: SwapStack.SwapSource
    let sink: FungibleTokenStack.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        let source = FungibleTokenStack.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: token0Type,
            token1Type: token1Type,
            stableMode: stableMode,
            uniqueID: nil
        )

        self.swapSource = SwapStack.SwapSource(
            swapper: zapper,
            source: source,
            uniqueID: nil
        )

        self.sink = FungibleTokenStack.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.swapSource.withdrawAvailable(maxAmount: amount)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Zap incomplete")
        destroy vault
    }

    pre {
        amount > 0.0: "Zap amount must be positive"
    }
}
```

## AutoBalancer Templates

### Create AutoBalancer
```cadence
import "DeFiActions"
import "MockOracle"

transaction(
    vaultType: String,
    lowerThreshold: UFix64,
    upperThreshold: UFix64,
    storagePath: StoragePath,
    publicPath: PublicPath
) {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        let tokenType = CompositeType(vaultType) 
            ?? panic("Invalid vault type: ".concat(vaultType))
        
        let oracle = MockOracle.PriceOracle(nil)
        
        let autoBalancer <- DeFiActions.createAutoBalancer(
            oracle: oracle,
            vaultType: tokenType,
            lowerThreshold: lowerThreshold,
            upperThreshold: upperThreshold,
            rebalanceSink: nil,
            rebalanceSource: nil,
            uniqueID: nil
        )
        
        signer.storage.save(<-autoBalancer, to: storagePath)
        let cap = signer.capabilities.storage.issue<&DeFiActions.AutoBalancer>(storagePath)
        signer.capabilities.publish(cap, at: publicPath)
    }

    pre {
        lowerThreshold > 0.0 && lowerThreshold < 1.0: "Lower threshold must be between 0 and 1"
        upperThreshold > 1.0: "Upper threshold must be greater than 1"
        lowerThreshold < upperThreshold: "Lower threshold must be less than upper"
    }
}
```

### Use AutoBalancer as Source
```cadence
import "FungibleToken"
import "FungibleTokenStack"
import "DeFiActions"

transaction(
    autoBalancerAddress: Address,
    autoBalancerPath: PublicPath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    amount: UFix64
) {
    let autoBalancerSource: DeFiActions.AutoBalancerSource
    let sink: FungibleTokenStack.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let autoBalancerCap = getAccount(autoBalancerAddress).capabilities
            .borrow<&DeFiActions.AutoBalancer>(autoBalancerPath)
            ?? panic("Could not access AutoBalancer")

        self.autoBalancerSource = DeFiActions.AutoBalancerSource(
            autoBalancer: autoBalancerCap,
            uniqueID: nil
        )

        self.sink = FungibleTokenStack.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.autoBalancerSource.withdrawAvailable(maxAmount: amount)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "AutoBalancer withdrawal incomplete")
        destroy vault
    }

    pre {
        amount > 0.0: "Amount must be positive"
    }
}
```

## Complex Workflow Templates

### Complete Restaking Workflow
```cadence
import "FungibleToken"
import "DeFiActions"
import "SwapStack"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "Staking"

transaction(
    pid: UInt64,
    poolCollectionAddress: Address,
    rewardTokenType: Type,
    token0Type: Type,
    token1Type: Type,
    slippageTolerance: UFix64
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let startingStake: UFix64
    
    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        
        let pool = getAccount(poolCollectionAddress).capabilities
            .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)!
            .getPool(pid: pid)
        
        self.startingStake = pool.getUserInfo(address: acct.address)!.stakingAmount
    }
    
    execute {
        // Claim rewards
        let rewardSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            poolID: pid,
            vaultType: rewardTokenType,
            overflowSinks: {},
            uniqueID: nil
        )
        
        // Convert to LP tokens
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: token0Type,
            token1Type: token1Type,
            stableMode: false,
            uniqueID: nil
        )
        
        let lpSource = SwapStack.SwapSource(
            swapper: zapper,
            source: rewardSource,
            uniqueID: nil
        )
        
        // Re-stake LP tokens
        let stakingSink = IncrementFiStakingConnectors.PoolSink(
            staker: self.userCertificateCap.address,
            poolID: pid,
            uniqueID: nil
        )
        
        let vault <- lpSource.withdrawAvailable(maxAmount: UFix64.max)
        stakingSink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Restaking incomplete")
        destroy vault
    }
    
    pre {
        pid > 0: "Pool ID must be positive"
        slippageTolerance >= 0.0 && slippageTolerance <= 1.0: "Slippage tolerance must be between 0 and 1"
    }
    
    post {
        getAccount(poolCollectionAddress).capabilities
            .borrow<&Staking.StakingPoolCollection>(Staking.CollectionPublicPath)!
            .getPool(pid: pid)
            .getUserInfo(address: self.userCertificateCap.address)!
            .stakingAmount >= self.startingStake * (1.0 - slippageTolerance):
            "Restake amount below expected"
    }
}
```

## Template Usage Guidelines

### Parameter Naming Convention
- Use descriptive parameter names
- Include units in parameter names when relevant
- Use consistent naming across templates

### Error Messages
- Include context in error messages
- Use consistent error message format
- Provide actionable information when possible

### Pre/Post Conditions
- Always validate input parameters
- Use meaningful error messages
- Keep conditions as single expressions

### Resource Handling
- Always verify complete transfers
- Use assert statements for critical validations
- Destroy vaults only after verification
