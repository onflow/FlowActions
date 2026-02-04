import "FungibleToken"
import "FlowTransactionScheduler"

import "DeFiActions"
import "MockOracle"
import "FungibleTokenConnectors"

/// NOT FOR PRODUCTION - THIS TRANSACTION IS EXAMPLE CODE
///
/// An example transaction configuring a DeFiActions AutoBalancer and saving it in the signer's account
///
/// @param unitOfAccount: vault type denominating PriceOracle's price
/// @param staleThreshold: seconds beyond which an oracle's price will be considered stale
/// @param lowerThreshold: the relative lower bound value ratio (>= 0.01 && < 1.0) where a rebalance will occur
/// @param upperThreshold: the relative upper bound value ratio (> 1.0 && < 2.0) where a rebalance will occur
/// @param vaultIdentifier: the Vault type which the AutoBalancer will contain
/// @param storagePath: the storage path at which to save the AutoBalancer. If nil, a default path will be derived from 
///     the vaultIdentifier
/// @param publicPath: the public path at which the AutoBalancer's public Capability should be published. If nil, a 
///     default path will be derived from the vaultIdentifier
///
transaction(
    unitOfAccount: String,
    staleThreshold: UInt64?,
    lowerThreshold: UFix64,
    upperThreshold: UFix64,
    vaultIdentifier: String,
    storagePath: StoragePath?,
    publicPath: PublicPath?
) {

    var autoBalancer: auth(DeFiActions.Set) &DeFiActions.AutoBalancer
    var authCap: Capability<auth(FungibleToken.Withdraw, FlowTransactionScheduler.Execute) &DeFiActions.AutoBalancer>?

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability, UnpublishCapability) &Account) {
        let tokenType = CompositeType(vaultIdentifier) ?? panic("Invalid vaultIdentifier \(vaultIdentifier)")
        let storagePath = storagePath ?? StoragePath(identifier: DeFiActions.deriveAutoBalancerPathIdentifier(vaultType: tokenType) ?? panic("Invalid storagePath")) ?? panic("Invalid storagePath")
        let publicPath = publicPath ?? PublicPath(identifier: DeFiActions.deriveAutoBalancerPathIdentifier(vaultType: tokenType) ?? panic("Invalid publicPath")) ?? panic("Invalid publicPath")
        self.authCap = nil
        if signer.storage.type(at: storagePath) == nil {
            // construct the AutoBalancer's oracle
            let unitOfAccount: Type = CompositeType(unitOfAccount) ?? panic("Invalid unitOfAccount \(unitOfAccount)")

            // PriceOracle is mocked here
            // PRODUCTION CASES SHOULD USE A VALID PRICEORACLE ADAPTER
            let oracle = MockOracle.PriceOracle(nil)

            // construct the AutoBalancer & save in signer's account
            let ab <- DeFiActions.createAutoBalancer(
                oracle: oracle,
                vaultType: tokenType,
                lowerThreshold: lowerThreshold,
                upperThreshold: upperThreshold,
                rebalanceSink: nil,
                rebalanceSource: nil,
                recurringConfig: nil,
                uniqueID: nil
            )
            signer.storage.save(<-ab, to: storagePath)
            // publish public Capability
            let cap = signer.capabilities.storage.issue<&DeFiActions.AutoBalancer>(storagePath)
            let _ = signer.capabilities.unpublish(publicPath)
            signer.capabilities.publish(cap, at: publicPath)

            // issue an authorized Capability on the AutoBalancer
            self.authCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw, FlowTransactionScheduler.Execute) &DeFiActions.AutoBalancer>(storagePath)
        }

        // ensure proper configuration in storage and via published Capability
        self.autoBalancer = signer.storage.borrow<auth(DeFiActions.Set) &DeFiActions.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not configured properly at \(storagePath)")
        let public = signer.capabilities.borrow<&DeFiActions.AutoBalancer>(publicPath)
            ?? panic("AutoBalancer Capability was not published to \(publicPath)")
        assert(self.autoBalancer.vaultType() == tokenType,
            message: "Expected configured AutoBalancer to manage \(vaultIdentifier) but stored AutoBalancer manages \(self.autoBalancer.vaultType().identifier)")
        assert(public.vaultType() == tokenType,
            message: "Expected configured AutoBalancer to manage \(vaultIdentifier) but publicly linked AutoBalancer manages \(public.vaultType().identifier)")
    }

    pre {
        self.authCap == nil || self.authCap?.check() == true:
        "Attempting to set AutoBalancer's self Capability with invalid Capability"
    }

    execute {
        // AutoBalancer was newly configured - set its self Capability so it can issue Sink and Sourc on itself
        // and auto-execute rebalancing using scheduled callbacks
        if let authCap = self.authCap {
            self.autoBalancer.setSelfCapability(authCap)
        }
    }
}
