import "EVM"
import "FungibleToken"

access(all) contract StackFiInterfaces {
    access(all) struct interface Sink {
        access(all) view fun getSinkType(): Type
        access(all) fun minimumCapacity(): UFix64
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            pre {
                from.getType() == self.getSinkType():
                "Sink \(self.getType().identifier) only accepts \(self.getSinkType().identifier) but received \(from.getType().identifier)"
            }
        }
    }

    access(all) struct interface Source {
        access(all) view fun getSourceType(): Type
        access(all) fun minimumAvailable(): UFix64
        access(all) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            post {
                result.getType() == self.getSourceType():
                "Source \(self.getType().identifier) should return \(self.getSourceType().identifier) but returned \(result.getType().identifier)"
            }
        }
    }
}
