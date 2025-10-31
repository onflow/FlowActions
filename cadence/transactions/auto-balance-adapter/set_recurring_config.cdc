import "FungibleToken"
import "FlowToken"
import "DeFiActions"
import "FungibleTokenConnectors"
import "FlowTransactionScheduler"

/// Sets the recurring config for the AutoBalancer (stored at the specified path) to execute a recurring rebalance
/// according to the provided parameters. The recurring rebalance will be funded by the signer's FlowToken Vault.
///
/// @param storagePath: the storage path of the stored AutoBalancer
/// @param interval: the interval at which to rebalance (in seconds)
/// @param priorityRawValue: the priority of the rebalance
/// @param executionEffort: the execution effort of the rebalance
/// @param forceRebalance: the force rebalance flag
///
transaction(
    storagePath: StoragePath,
    interval: UInt64,
    priorityRawValue: UInt8,
    executionEffort: UInt64,
    forceRebalance: Bool
) {
    let autoBalancer: auth(DeFiActions.Schedule, DeFiActions.Configure) &DeFiActions.AutoBalancer
    let config: DeFiActions.AutoBalancerRecurringConfig

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // reference the AutoBalancer
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Schedule, DeFiActions.Configure) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not found in signer's storage at \(storagePath)")
        
        let fundingVault = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(/storage/flowTokenVault)
        let flowSinkAndSource = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: fundingVault,
            uniqueID: nil
        )
        
        // construct the AutoBalancerRecurringConfig
        assert(priorityRawValue >= 0 && priorityRawValue <= 2,
            message: "Invalid priorityRawValue: \(priorityRawValue) - must be between 0 and 2")
        self.config = DeFiActions.AutoBalancerRecurringConfig(
            interval: interval,
            priority: FlowTransactionScheduler.Priority(rawValue: priorityRawValue)!,
            executionEffort: executionEffort,
            forceRebalance: forceRebalance,
            txnFunder: flowSinkAndSource
        )
    }

    execute {
        // set the recurring config
        self.autoBalancer.setRecurringConfig(self.config)

        // schedule the next execution
        let err = self.autoBalancer.scheduleNextRebalance(whileExecuting: nil)
        if err != nil {
            panic("Failed to schedule next rebalance: \(err!)")
        }
    }
}
