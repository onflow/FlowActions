import "FungibleToken"
import "FungibleTokenMetadataViews"

/// Returns an account's balance of a FungibleToken Vault by resolving the token type's FTVaultData
/// to find the correct public path.
///
/// @param address: the address of the account
/// @param vaultTypeIdentifier: the full type identifier of the Vault (e.g., "A.1654653399040a61.FlowToken.Vault")
///
access(all)
fun main(address: Address, vaultTypeIdentifier: String): UFix64? {
    let vaultType = CompositeType(vaultTypeIdentifier)
    if vaultType == nil {
        return nil
    }

    let contractAddress = vaultType!.address
    if contractAddress == nil {
        return nil
    }

    let contractName = vaultType!.contractName
    if contractName == nil {
        return nil
    }

    let ftContract = getAccount(contractAddress!).contracts.borrow<&{FungibleToken}>(name: contractName!)
    if ftContract == nil {
        return nil
    }

    let data = ftContract!.resolveContractView(
        resourceType: vaultType!,
        viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
    ) as! FungibleTokenMetadataViews.FTVaultData?

    if data == nil {
        return nil
    }

    return getAccount(address).capabilities.borrow<&{FungibleToken.Vault}>(data!.receiverPath)?.balance
}
