import "FungibleToken"

import "DFB"
import "BandOracleAdapters"
import "FungibleTokenStack"

/// An example transaction configuring a DeFiBlocks AutoBalancer and saving it in the signer's account
///
/// @param unitOfAccount: vault type denominating PriceOracle's price
/// @param staleThreshold: seconds beyond which an oracle's price will be considered stale
/// @param lowerThreshold: the relative lower bound value ratio (>= 0.01 && < 1.0) where a rebalance will occur
/// @param upperThreshold: the relative upper bound value ratio (> 1.0 && < 2.0) where a rebalance will occur
/// @param vaultIdentifier: the Vault type which the AutoBalancer will contain
/// @param storagePath: the storage path at which to save the AutoBalancer
/// @param publicPath: the public path at which the AutoBalancer's public Capability should be published
///
transaction(
    unitOfAccount: String,
    staleThreshold: UInt64?,
    lowerThreshold: UFix64,
    upperThreshold: UFix64,
    vaultIdentifier: String,
    storagePath: StoragePath,
    publicPath: PublicPath
) {

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability, UnpublishCapability) &Account) {
        if signer.storage.type(at: storagePath) == nil {
            // get the Vault contract
            let tokenType = CompositeType(vaultIdentifier) ?? panic("Invalid vaultIdentifier \(vaultIdentifier)")
            let tokenContract = getAccount(tokenType.address!).contracts.borrow<&{FungibleToken}>(name: tokenType.contractName!)
                ?? panic("Vault Type \(vaultIdentifier) is not defined by a FungibleToken conforming contract")

            // construct the AutoBalancer's oracle
            let unitOfAccount = CompositeType(unitOfAccount) ?? panic("Invalid unitOfAccount \(unitOfAccount)")
            let oracle = BandOracleAdapters.PriceOracle(
                unitOfAccount: unitOfAccount,
                staleThreshold: staleThreshold,
                feeSource: FungibleTokenStack.VaultSource(
                    min: nil,
                    withdrawVault: signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(/storage/flowTokenVault),
                    uniqueID: nil
                )
            )

            // construct the AutoBalancer & save in signer's account
            let ab <- DFB.createAutoBalancer(
                oracle: oracle,
                vault: <-tokenContract.createEmptyVault(vaultType: tokenType),
                lowerThreshold: lowerThreshold,
                upperThreshold: upperThreshold,
                rebalanceSink: nil,
                rebalanceSource: nil,
                uniqueID: nil
            )
            signer.storage.save(<-ab, to: storagePath)
            // publish public Capability
            let cap = signer.capabilities.storage.issue<&DFB.AutoBalancer>(storagePath)
            signer.capabilities.unpublish(publicPath)
            signer.capabilities.publish(cap, at: publicPath)
        }

        // ensure proper configuration in storage and via published Capability
        signer.storage.borrow<&DFB.AutoBalancer>(from: storagePath)
            ?? panic("AutoBalancer was not configured properly at \(storagePath)")
        signer.capabilities.borrow<&DFB.AutoBalancer>(publicPath)
            ?? panic("AutoBalancer Capability was not published to \(publicPath)")
    }
}
