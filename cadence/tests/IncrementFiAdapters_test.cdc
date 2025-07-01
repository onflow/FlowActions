import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "TokenA"
import "TokenB"

import "DFB"
import "IncrementFiAdapters"

access(all) let testTokenAccount = Test.getAccount(0x0000000000000010)
access(all) let pairCreatorAccount = Test.createAccount()
access(all) let serviceAccount = Test.serviceAccount()

access(all) let tokenAIdentifier = Type<@TokenA.Vault>().identifier // "A.<ADDRESS>.TokenA.Vault"
access(all) let tokenBIdentifier = Type<@TokenB.Vault>().identifier // "A.<ADDRESS>.TokenB.Vault"
// IncrementFi identifies tokens by their contract identifier - e.g. A.<ADDRESS>.TokenA for A.<ADDRESS>.TokenA.Vault
access(all) let tokenAKey = String.join(tokenAIdentifier.split(separator: ".").slice(from: 0, upTo: 3), separator: ".")
access(all) let tokenBKey = String.join(tokenBIdentifier.split(separator: ".").slice(from: 0, upTo: 3), separator: ".")

access(all)
fun setup() {
    setupIncrementFiDependencies()

    var err = Test.deployContract(
        name: "DFBUtils",
        path: "../contracts/utils/DFBUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DFB",
        path: "../contracts/interfaces/DFB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenStack",
        path: "../contracts/connectors/FungibleTokenStack.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "SwapStack",
        path: "../contracts/connectors/SwapStack.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "IncrementFiAdapters",
        path: "../contracts/adapters/IncrementFiAdapters.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    transferFlow(signer: serviceAccount, recipient: pairCreatorAccount.address, amount: 10.0)

    createSwapPair(
        signer: pairCreatorAccount,
        token0Identifier: tokenAIdentifier,
        token1Identifier: tokenBIdentifier,
        stableMode: false
    )

    setupGenericVault(signer: pairCreatorAccount, vaultIdentifier: tokenAIdentifier)
    setupGenericVault(signer: pairCreatorAccount, vaultIdentifier: tokenBIdentifier)
    mintTestTokens(
        signer: testTokenAccount,
        recipient: pairCreatorAccount.address,
        amount: 100.0,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )
    mintTestTokens(
        signer: testTokenAccount,
        recipient: pairCreatorAccount.address,
        amount: 200.0,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.ReceiverPublicPath
    )

    addLiquidity(
        signer: pairCreatorAccount,
        token0Key: tokenAKey,
        token1Key: tokenBKey,
        token0InDesired: 100.0,
        token1InDesired: 200.0,
        token0InMin: 0.0,
        token1InMin: 0.0,
        deadline: getCurrentBlockTimestamp(),
        token0VaultPath: TokenA.VaultStoragePath,
        token1VaultPath: TokenB.VaultStoragePath,
        stableMode: false
    )
}

access(all)
fun testAdapterGetAmountsInSucceeds() {
    let outAmount = 1.0
    let path = [tokenAKey, tokenBKey]
    let amountsInRes = executeScript(
            "../scripts/increment-fi-adapters/get_amounts_in.cdc",
            [outAmount, tokenAIdentifier, tokenBIdentifier, path]
        )
    Test.expect(amountsInRes, Test.beSucceeded())
    let quote = amountsInRes.returnValue! as! {DFB.Quote}
    Test.assertEqual(outAmount, quote.outAmount)
}

access(all)
fun testAdapterGetAmountsOutSucceeds() {
    let inAmount = 1.0
    let path = [tokenAKey, tokenBKey]
    let amountsOutRes = executeScript(
            "../scripts/increment-fi-adapters/get_amounts_out.cdc",
            [inAmount, tokenAIdentifier, tokenBIdentifier, path]
        )
    Test.expect(amountsOutRes, Test.beSucceeded())
    let quote = amountsOutRes.returnValue! as! {DFB.Quote}
    Test.assertEqual(inAmount, quote.inAmount)
}