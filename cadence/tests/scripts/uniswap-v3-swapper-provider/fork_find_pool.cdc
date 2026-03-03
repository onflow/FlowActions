import "EVM"

/// Queries the Uniswap V3 factory to check if a pool exists for the given pair and fee tier.
/// Returns the pool address hex string, or "0x0000000000000000000000000000000000000000" if no pool.
///
access(all) fun main(
    signerAddress: Address,
    factoryHex: String,
    token0Hex: String,
    token1Hex: String,
    feeTier: UInt256
): String {
    let account = getAuthAccount<auth(Storage, IssueStorageCapabilityController) &Account>(signerAddress)
    let coaCap = account.capabilities.storage.issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)
    let coa = coaCap.borrow() ?? panic("No COA")

    let factory = EVM.addressFromString(factoryHex)
    let token0 = EVM.addressFromString(token0Hex)
    let token1 = EVM.addressFromString(token1Hex)

    let calldata = EVM.encodeABIWithSignature(
        "getPool(address,address,uint24)",
        [token0, token1, feeTier]
    )

    let res = coa.dryCall(
        to: factory,
        data: calldata,
        gasLimit: 120_000,
        value: EVM.Balance(attoflow: 0)
    )

    if res.status != EVM.Status.successful {
        return "CALL_FAILED"
    }

    let decoded = EVM.decodeABI(types: [Type<EVM.EVMAddress>()], data: res.data)
    if decoded.length == 0 {
        return "NO_RESULT"
    }

    let poolAddr = decoded[0] as! EVM.EVMAddress
    return poolAddr.toString()
}
