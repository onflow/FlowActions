import "FungibleToken"

/// Returns the balance of the given account's bridged FUSDEV (euSDEV) share vault
///
/// @param account: The address of the account holding the share vault
///
access(all) fun main(account: Address): UFix64 {
    let vault = getAccount(account).capabilities.borrow<&{FungibleToken.Balance}>(
        /public/EVMVMBridgedToken_d069d989e2f44b70c65347d1853c0c67e10a9f8dVault
    ) ?? panic("Missing bridged share vault public capability")
    return vault.balance
}
