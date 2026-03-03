import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FlowToken"
import "UniswapV3SwapConnectors"
import "EVM"
import "EVMAbiHelpers"

access(all) let serviceAccount = Test.serviceAccount()

access(all) let uniV2DeployerAccount = Test.createAccount()
access(all) var uniV2DeployerCOAHex = ""

access(all) var tokenAHex = ""
access(all) var tokenBHex = ""
access(all) var wflowHex = ""
access(all) var uniV2RouterHex = ""

access(all)
fun setup() {
    log("================== Setting up UniswapV3SwapConnectors test ==================")
    wflowHex = getEVMAddressAssociated(withType: Type<@FlowToken.Vault>().identifier)!

    // TODO: remove this step once the VM bridge templates are updated for test env
    // see https://github.com/onflow/flow-go/issues/8184
    tempUpsertBridgeTemplateChunks(serviceAccount)
    
    transferFlow(signer: serviceAccount, recipient: uniV2DeployerAccount.address, amount: 10.0)
    createCOA(uniV2DeployerAccount, fundingAmount: 1.0) 
    
    uniV2DeployerCOAHex = getCOAAddressHex(atFlowAddress: uniV2DeployerAccount.address)

    uniV2RouterHex = setupUniswapV2(uniV2DeployerAccount, feeToSetter: uniV2DeployerCOAHex, wflowAddress: wflowHex)

    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "SwapConnectors",
        path: "../contracts/connectors/SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "EVMAbiHelpers",
        path: "../contracts/utils/EVMAbiHelpers.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    deployEVMAmountUtils()
    err = Test.deployContract(
        name: "UniswapV3SwapConnectors",
        path: "../contracts/connectors/evm/UniswapV3SwapConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all)
fun testSetupSucceeds() {
    log("UniswapV3SwapConnectors deployment success")
}

access(all) fun test_tuple_abi_encoding_decoding() {
    let tokenA = "F376A6849184571fEEdD246a1Ba2D331cfe56c8c"
    let tokenB = "339d413CCEfD986b1B3647A9cfa9CBbE70A30749"
    let tokenC = "d6949BB9C896566331A00e0f9a433Ae9dE88E13D"
    let poolFee = "d413CC"
    let path = "\(tokenA)\(poolFee)\(tokenB)\(poolFee)\(tokenC)".decodeHex()
    let recipient = EVM.addressFromString("0xD97BAeE86C61e8CCFD19329118004661C45c2aA7")
    let amountIn: UInt256 = 101_250_500
    let amountOutMinimum: UInt256 = 888_200_400

    let argsBlob = encodeTuple_bytes_addr_u256_u256(
        path: path,
        recipient: recipient,
        amountOne: amountIn,
        amountTwo: amountOutMinimum
    )
    let head = EVMAbiHelpers.abiWord(32)
    let selector: [UInt8] = [0xb8, 0x58, 0x18, 0x3f]
    let expectedCallData = selector.concat(head).concat(argsBlob)

    let exactInputParams = UniswapV3SwapConnectors.ExactInputSingleParams(
        path: EVM.EVMBytes(value: path),
        recipient: recipient,
        amountIn: amountIn,
        amountOutMinimum: amountOutMinimum
    )
    let callData = EVM.encodeABIWithSignature(
        "exactInput((bytes,address,uint256,uint256))",
        [exactInputParams]
    )

    assert(expectedCallData == callData, message: "diff in tuple ABI encoding/decoding")

    let values = EVM.decodeABIWithSignature(
        "exactInput((bytes,address,uint256,uint256))",
        types: [Type<UniswapV3SwapConnectors.ExactInputSingleParams>()],
        data: callData
    )
    assert(values.length == 1)

    let decodedExactInputParams = values[0] as! UniswapV3SwapConnectors.ExactInputSingleParams
    assert(decodedExactInputParams.path.value == exactInputParams.path.value)
    assert(decodedExactInputParams.recipient.bytes == exactInputParams.recipient.bytes)
    assert(decodedExactInputParams.amountIn == exactInputParams.amountIn)
    assert(decodedExactInputParams.amountOutMinimum == exactInputParams.amountOutMinimum)
}

access(self)
fun encodeTuple_bytes_addr_u256_u256(
    path: [UInt8],
    recipient: EVM.EVMAddress,
    amountOne: UInt256,
    amountTwo: UInt256
): [UInt8] {
    let tupleHeadSize = 32 * 4

    var head: [[UInt8]] = []
    var tail: [[UInt8]] = []

    // 1) bytes path (dynamic) -> pointer to tail, relative to start of this tuple blob
    head.append(EVMAbiHelpers.abiWord(UInt256(tupleHeadSize)))
    tail.append(EVMAbiHelpers.abiDynamicBytes(path))

    head.append(EVMAbiHelpers.abiAddress(recipient))

    head.append(EVMAbiHelpers.abiUInt256(amountOne))

    head.append(EVMAbiHelpers.abiUInt256(amountTwo))

    return EVMAbiHelpers.concat(head).concat(EVMAbiHelpers.concat(tail))
}
