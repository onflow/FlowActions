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
        access(all) fun withdrawAvailable(): @{FungibleToken.Vault} {
            post {
                result.getType() == self.getSourceType():
                "Source \(self.getType().identifier) should return \(self.getSourceType().identifier) but returned \(result.getType().identifier)"
            }
        }
    }

    access(all) struct Stack {
        access(self) let sinks: {Type: {Sink}}
        access(self) let sources: {Type: {Source}}
        access(self) let coaCapability: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>

        init(
            sinks: {Type: {Sink}},
            sources: {Type: {Source}},
            coaCapability: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
        ) {
            self.sinks = sinks
            self.sources = sources
            self.coaCapability = coaCapability
        }

        access(all) view fun getSinkTypes(): [Type] {
            return self.sinks.keys
        }

        access(all) view fun getSourceTypes(): [Type] {
            return self.sources.keys
        }

        access(all) view fun checkCOA(): Bool {
            return self.borrowCOA() != nil
        }

        access(all) view fun getCOAAddress(): EVM.EVMAddress? {
            return self.borrowCOA()?.address()
        }

        access(self) view fun borrowCOA(): auth(EVM.Call) &EVM.CadenceOwnedAccount? {
            return self.coaCapability.borrow()
        }
    }
}
