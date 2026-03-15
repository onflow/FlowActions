import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "TokenA"
import "TokenB"

import "DeFiActions"
import "IncrementFiSwapConnectors"

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
    log("================== Setting up IncrementFiSwapConnectors test ==================")
    setupIncrementFiDependencies()

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
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
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
        name: "IncrementFiSwapConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiSwapConnectors.cdc",
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
        deadline: getCurrentBlockTimestamp() + 1000.0,
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
    let quote = amountsInRes.returnValue! as! {DeFiActions.Quote}
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
    let quote = amountsOutRes.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(inAmount, quote.inAmount)
}

access(all)
fun testPriceOracleGetPrice() {
    let path = [tokenAKey, tokenBKey]
    let priceOfBaseRes = executeScript(
        "../scripts/increment-fi-adapters/get_price.cdc",
        [tokenBIdentifier, tokenAIdentifier, path, tokenAIdentifier]
    )
    Test.expect(priceOfBaseRes, Test.beSucceeded())
    let priceOfBase = priceOfBaseRes.returnValue as! UFix64?
    Test.assert(priceOfBase != nil, message: "Price of base token should be non-nil")
    Test.assert(priceOfBase! > 0.0, message: "Price of base token should be positive")
    log(priceOfBase!)
    let priceOfQuoteRes = executeScript(
        "../scripts/increment-fi-adapters/get_price.cdc",
        [tokenBIdentifier, tokenAIdentifier, path, tokenBIdentifier]
    )
    Test.expect(priceOfQuoteRes, Test.beSucceeded())
    let priceOfQuote = priceOfQuoteRes.returnValue
    Test.assert(priceOfQuote != nil, message: "Price of quote token should be non-nil")
    Test.assertEqual(priceOfQuote, 1.0 as UFix64?)
}
