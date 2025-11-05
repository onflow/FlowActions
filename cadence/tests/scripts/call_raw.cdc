import "EVM"

/// Supports generic calls to EVM contracts that might have return values
///
access(all) fun main(
    fromAddressHex: String,
    toAddressHex: String,
    calldata: String,
    gasLimit: UInt64,
    value: UInt
): EVM.Result {

    let evmAddress = EVM.addressFromString(toAddressHex)
    let fromAddress = EVM.addressFromString(fromAddressHex)

    let data = calldata.decodeHex()

    return EVM.dryCall(
        from: fromAddress,
        to: evmAddress,
        data: data,
        gasLimit: gasLimit,
        value: EVM.Balance(attoflow: value)
    )
}
