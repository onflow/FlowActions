import Test

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

access(all)
fun transferFlow(signer: Test.TestAccount, recipient: Address, amount: UFix64) {
    let transferResult = _executeTransaction(
        "../transactions/flow-token/transfer_flow.cdc",
        [recipient, amount],
        signer
    )
    Test.expect(transferResult, Test.beSucceeded())
}