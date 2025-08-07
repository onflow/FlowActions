import "IncrementFiStakingConnectors"
import "Staking"
import "FungibleToken"
import "TokenA"

transaction(pid: UInt64) {
    let incrementFiSink: IncrementFiStakingConnectors.PoolSink
    let tokenAVaultRef: auth(FungibleToken.Withdraw) &TokenA.Vault

    prepare(acct: auth(BorrowValue) &Account) {
        self.incrementFiSink = IncrementFiStakingConnectors.PoolSink(
            poolID: pid,
            staker: acct.address,
            uniqueID: nil
        )
        self.tokenAVaultRef = acct.storage.borrow<auth(FungibleToken.Withdraw) &TokenA.Vault>(from: TokenA.VaultStoragePath)
            ?? panic("Could not borrow reference to TokenA Vault")
    }
    
    execute {
        self.incrementFiSink.depositCapacity(
            from: self.tokenAVaultRef
        )
    }
}