import "EVM"

access(all) fun getTypeArray(_ identifiers: [String]): [Type] {
    var types: [Type] = []
    for identifier in identifiers {
        let type = CompositeType(identifier)
            ?? panic("Invalid identifier: ".concat(identifier))
        types.append(type)
    }
    return types
}

/// Supports generic calls to EVM contracts that might have return values
///
access(all) fun main(
    fromAddressHex: String,
    toAddressHex: String,
    calldata: String,
    gasLimit: UInt64,
    value: UInt,
    typeIdentifiers: [String]
): [AnyStruct] {

    let evmAddress = EVM.addressFromString(toAddressHex)
    let fromAddress = EVM.addressFromString(fromAddressHex)

    let data = calldata.decodeHex()

    let evmResult = EVM.dryCall(
        from: fromAddress,
        to: evmAddress,
        data: data,
        gasLimit: gasLimit,
        value: EVM.Balance(attoflow: value)
    )

    if typeIdentifiers.length == 0 {
        return []
    } else {
        return EVM.decodeABI(types: getTypeArray(typeIdentifiers), data: evmResult.data)
    }
}
