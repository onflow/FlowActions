#test_fork(network: "mainnet-fork", height: 142104481)

import Test

import "EVM"
import "DeFiActions"

// testing account
access(all) let testAccount = Test.getAccount(0x443472749ebdaac8)
// FUSDEV MorphoERC4626 vault (underlying asset: PYUSD0)
access(all) let morphoERC4626VaultEVMAddressHex = "0xd069d989e2F44B70c65347d1853C0c67e10a9F8D"


/* --- Test Helpers --- */

access(all)
fun _executeScript(_ path: String, _ args: [AnyStruct]): Test.ScriptResult {
    return Test.executeScript(Test.readFile(path), args)
}

access(all)
fun _executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    )
    return Test.executeTransaction(txn)
}


// until the contracts are deployed to mainnet, deploy them manually
access(all) fun setup() {
    log("==== Deploy missing contracts ====")
    var err = Test.deployContract(
        name: "ERC4626Utils",
        path: "../contracts/utils/ERC4626Utils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "EVMAmountUtils",
        path: "../contracts/connectors/evm/EVMAmountUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "MorphoERC4626SinkConnectors",
        path: "../contracts/connectors/evm/morpho/MorphoERC4626SinkConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "MorphoERC4626SwapConnectors",
        path: "../contracts/connectors/evm/morpho/MorphoERC4626SwapConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testQuoteIn() {
    let quoteInResult = _executeScript(
        "./scripts/morpho/quote_in.cdc",
        [
            testAccount.address,
            morphoERC4626VaultEVMAddressHex,
            1.0
        ]
    )
    Test.expect(quoteInResult, Test.beSucceeded())
    let quote = quoteInResult.returnValue! as! {DeFiActions.Quote}
    assert(quote.inAmount > 1.0, message: "Share should be at least 1.0 PYUSD0")
}

access(all) fun testSwap() {
    let swapRes = _executeTransaction(
        "./transactions/morpho/swap.cdc",
        [
            morphoERC4626VaultEVMAddressHex,
            1.0
        ],
        testAccount
    )
    Test.expect(swapRes, Test.beSucceeded())

    let swapBackRes = _executeTransaction(
        "./transactions/morpho/swap_back.cdc",
        [
            morphoERC4626VaultEVMAddressHex,
            0.99920692 // @TODO investigage losses 
        ],
        testAccount
    )
    Test.expect(swapBackRes, Test.beSucceeded())
}
