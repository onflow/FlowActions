import "DeFiActions"

/// THIS TRANSACTION IS FOR TESTING PURPOSES ONLY AND SHOULD NOT SUCCEED
///
/// Tests that an AutoBalancerRecurringConfig cannot be set on a different AutoBalancer - should fail
transaction(victimAddress: Address, victimPublicPath: PublicPath, attackerStoragePath: StoragePath) {
    
    let victimConfig: DeFiActions.AutoBalancerRecurringConfig
    let attackerAB: auth(DeFiActions.Configure) &DeFiActions.AutoBalancer
    
    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        // get victim's AutoBalancer
        let victimAB = signer.capabilities.borrow<&DeFiActions.AutoBalancer>(victimPublicPath)
            ?? panic("Victim AutoBalancer was not found in signer's storage at \(victimPublicPath)")
        self.victimConfig = victimAB.getRecurringConfig() ?? panic("Victim AutoBalancer does not have a recurring config")

        // get attacker's AutoBalancer
        self.attackerAB = signer.storage.borrow<auth(DeFiActions.Configure) &DeFiActions.AutoBalancer>(from: attackerStoragePath)
            ?? panic("Attacker AutoBalancer was not found in signer's storage at \(attackerStoragePath)")
    }

    execute {
        // set the copied config - should fail
        self.attackerAB.setRecurringConfig(self.victimConfig)
    }
}
