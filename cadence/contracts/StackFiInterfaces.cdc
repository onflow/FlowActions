import "EVM"
import "FungibleToken"

access(all) contract StackFiInterfaces {
    access(all) struct interface Sink {
        access(all) view fun getSinkType(): Type
        access(all) fun minimumCapacity(): UFix64
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
    }

    access(all) struct interface Source {
        access(all) view fun getSourceType(): Type
        access(all) fun minimumAvailable(): UFix64
        access(all) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault}
    }
}
