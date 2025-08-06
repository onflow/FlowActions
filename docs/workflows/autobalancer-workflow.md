# AutoBalancer Workflow

**Purpose**: Create automated token rebalancing system  
**Components**: PriceOracle → AutoBalancer → Storage + PublicCapability  
**Related**: [Pattern 2](../patterns.md#pattern-2-autobalancer-setup)

## Required Imports
```cadence
import "DeFiActions"
import "MockOracle"  // Replace with actual oracle implementation
```

## Component Flow
```
1. PriceOracle        → Provides price data for rebalancing decisions
2. AutoBalancer       → Manages token balance within thresholds
3. Storage            → Saves AutoBalancer resource to account
4. PublicCapability   → Exposes AutoBalancer for external access
```

## Transaction Implementation
```cadence
transaction(
    vaultType: String,           // Token type identifier (e.g., "A.1654653399040a61.FlowToken.Vault")
    lowerThreshold: UFix64,      // Lower rebalance threshold (e.g., 0.9 = 90%)
    upperThreshold: UFix64,      // Upper rebalance threshold (e.g., 1.1 = 110%)
    storagePath: StoragePath,    // Storage location for AutoBalancer
    publicPath: PublicPath       // Public capability path for external access
) {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        // Step 1: Parse and validate token type
        let tokenType = CompositeType(vaultType) 
            ?? panic("Invalid vault type: ".concat(vaultType))
        
        // Step 2: Create price oracle (replace with actual implementation)
        let oracle = MockOracle.PriceOracle(nil)
        
        // Step 3: Create AutoBalancer resource
        let autoBalancer <- DeFiActions.createAutoBalancer(
            oracle: oracle,
            vaultType: tokenType,
            lowerThreshold: lowerThreshold,
            upperThreshold: upperThreshold,
            rebalanceSink: nil,      // Configure later with setSink()
            rebalanceSource: nil,    // Configure later with setSource()
            uniqueID: nil
        )
        
        // Step 4: Save AutoBalancer to storage
        signer.storage.save(<-autoBalancer, to: storagePath)
        
        // Step 5: Create and publish public capability
        let capability = signer.capabilities.storage.issue<&DeFiActions.AutoBalancer>(storagePath)
        signer.capabilities.publish(capability, at: publicPath)
    }
    
    pre {
        lowerThreshold > 0.0 && lowerThreshold < 1.0: "Lower threshold must be between 0 and 1"
        upperThreshold > 1.0: "Upper threshold must be greater than 1"
        lowerThreshold < upperThreshold: "Lower threshold must be less than upper threshold"
    }
    
    post {
        getAccount(self.address).capabilities
            .borrow<&DeFiActions.AutoBalancer>(publicPath) != nil:
            "AutoBalancer capability not published correctly"
    }
}
```

## Component Details

### PriceOracle
- **Purpose**: Provides real-time price data for rebalancing decisions
- **Input**: Token type and market data
- **Output**: Current price ratio vs target
- **Note**: Replace MockOracle with actual price oracle implementation

### AutoBalancer Resource
- **Purpose**: Automatically rebalances token holdings within specified thresholds
- **Input**: Price oracle, token type, threshold configuration
- **Output**: Managed token balance within bounds
- **Side Effects**: Triggers rebalancing when thresholds are exceeded

### Storage and Capability
- **Purpose**: Saves AutoBalancer and provides external access
- **Input**: AutoBalancer resource, storage path, public path
- **Output**: Persistent AutoBalancer with public interface

## Configuration Examples

### Conservative Rebalancing (5% tolerance)
```cadence
setupAutoBalancer(
    vaultType: "A.1654653399040a61.FlowToken.Vault",
    lowerThreshold: 0.95,  // Rebalance if below 95%
    upperThreshold: 1.05,  // Rebalance if above 105%
    storagePath: /storage/flowAutoBalancer,
    publicPath: /public/flowAutoBalancer
)
```

### Aggressive Rebalancing (20% tolerance)
```cadence
setupAutoBalancer(
    vaultType: "A.1654653399040a61.FlowToken.Vault",
    lowerThreshold: 0.8,   // Rebalance if below 80%
    upperThreshold: 1.2,   // Rebalance if above 120%
    storagePath: /storage/flowAutoBalancer,
    publicPath: /public/flowAutoBalancer
)
```

## Post-Setup Configuration

### Setting Rebalance Sink
```cadence
transaction(autoBalancerPath: StoragePath, sinkConfig: SinkConfiguration) {
    prepare(acct: auth(BorrowValue) &Account) {
        let autoBalancer = acct.storage.borrow<&DeFiActions.AutoBalancer>(from: autoBalancerPath)
            ?? panic("AutoBalancer not found")
        
        let sink = createRebalanceSink(sinkConfig)
        autoBalancer.setSink(sink: sink)
    }
}
```

### Setting Rebalance Source
```cadence
transaction(autoBalancerPath: StoragePath, sourceConfig: SourceConfiguration) {
    prepare(acct: auth(BorrowValue) &Account) {
        let autoBalancer = acct.storage.borrow<&DeFiActions.AutoBalancer>(from: autoBalancerPath)
            ?? panic("AutoBalancer not found")
        
        let source = createRebalanceSource(sourceConfig)
        autoBalancer.setSource(source: source)
    }
}
```

## Usage Integration

### Using AutoBalancer as Source
```cadence
let autoBalancerCap = getAccount(autoBalancerAddress).capabilities
    .borrow<&DeFiActions.AutoBalancer>(/public/flowAutoBalancer)!

let source = DeFiActions.AutoBalancerSource(
    autoBalancer: autoBalancerCap,
    uniqueID: operationID
)
```

### Using AutoBalancer as Sink
```cadence
let autoBalancerCap = getAccount(autoBalancerAddress).capabilities
    .borrow<&DeFiActions.AutoBalancer>(/public/flowAutoBalancer)!

let sink = DeFiActions.AutoBalancerSink(
    autoBalancer: autoBalancerCap,
    uniqueID: operationID
)
```

## Monitoring and Management

### Check Rebalancing Status
```cadence
access(all) fun checkRebalanceStatus(autoBalancerAddress: Address): Bool {
    let autoBalancer = getAccount(autoBalancerAddress).capabilities
        .borrow<&DeFiActions.AutoBalancer>(/public/flowAutoBalancer)
        ?? panic("Could not access AutoBalancer")
    
    return autoBalancer.checkRebalance()
}
```

### Trigger Manual Rebalancing
```cadence
transaction(autoBalancerPath: StoragePath) {
    prepare(acct: auth(BorrowValue) &Account) {
        let autoBalancer = acct.storage.borrow<&DeFiActions.AutoBalancer>(from: autoBalancerPath)
            ?? panic("AutoBalancer not found")
        
        if autoBalancer.checkRebalance() {
            autoBalancer.executeRebalance()
        }
    }
}
```

## Error Handling

### Common Setup Failures
- **Invalid vault type**: Ensure vault type string is correctly formatted
- **Threshold validation**: Verify thresholds are within valid ranges
- **Storage conflicts**: Check storage path is not already occupied
- **Capability issues**: Ensure account has required entitlements

### Runtime Failures
- **Oracle unavailable**: Price oracle not accessible or returning invalid data
- **Insufficient balance**: Not enough tokens to rebalance
- **Sink/Source issues**: Rebalance destination or source not properly configured
- **Threshold breach**: Current balance outside acceptable rebalancing range
