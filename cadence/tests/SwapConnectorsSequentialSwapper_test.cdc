import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "TokenA"
import "TokenB"
import "TokenC"

import "DeFiActions"
import "IncrementFiSwapConnectors"

access(all) let testTokenAccount = Test.getAccount(0x0000000000000010)
access(all) let serviceAccount = Test.serviceAccount()

access(all) let tokenAIdentifier = Type<@TokenA.Vault>().identifier // "A.<ADDRESS>.TokenA.Vault"
access(all) let tokenBIdentifier = Type<@TokenB.Vault>().identifier // "A.<ADDRESS>.TokenB.Vault"
access(all) let tokenCIdentifier = Type<@TokenC.Vault>().identifier // "A.<ADDRESS>.TokenC.Vault"

access(all)
fun setup() {
    log("================== Setting up SwapConnectorsSequentialSwapper test ==================")
    // deploy test token contracts
    var err = Test.deployContract(
        name: "TestTokenMinter",
        path: "./contracts/TestTokenMinter.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "TokenA",
        path: "./contracts/TokenA.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "TokenB",
        path: "./contracts/TokenB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "TokenC",
        path: "./contracts/TokenC.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
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
        name: "MockSwapper",
        path: "./contracts/MockSwapper.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    transferFlow(signer: serviceAccount, recipient: testTokenAccount.address, amount: 10.0)
}

access(all)
fun testConnectorMockSwapSucceeds() {
    let amountIn = 10.0
    let priceRatio1 = 0.5
    let priceRatio2 = 0.2
    let mockSwapperConfigs: [{String: AnyStruct}] = [
        {
            "inVault": Type<@TokenA.Vault>(),
            "outVault": Type<@TokenB.Vault>(),
            "inVaultPath": TokenA.VaultStoragePath,
            "outVaultPath": TokenB.VaultStoragePath,
            "priceRatio": priceRatio1
        }, {
            "inVault": Type<@TokenB.Vault>(),
            "outVault": Type<@TokenC.Vault>(),
            "inVaultPath": TokenB.VaultStoragePath,
            "outVaultPath": TokenC.VaultStoragePath,
            "priceRatio": priceRatio2
        }
    ]
    let inType = Type<@TokenA.Vault>()
    let outType = Type<@TokenC.Vault>()
    let expectedOut = amountIn * priceRatio1 * priceRatio2

    let quoteOut = executeScript(
            "./scripts/sequential-swapper/mock_quote.cdc",
            [testTokenAccount.address, mockSwapperConfigs, amountIn, true, false] // out=true, reverse=false
        )
    Test.expect(quoteOut, Test.beSucceeded())
    let actualQuoteOut = quoteOut.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(inType, actualQuoteOut.inType)
    Test.assertEqual(outType, actualQuoteOut.outType)
    Test.assertEqual(amountIn, actualQuoteOut.inAmount)
    Test.assertEqual(expectedOut, actualQuoteOut.outAmount)

    let quoteIn = executeScript(
            "./scripts/sequential-swapper/mock_quote.cdc",
            [testTokenAccount.address, mockSwapperConfigs, expectedOut, false, false] // out=false, reverse=false
        )
    Test.expect(quoteIn, Test.beSucceeded())
    let actualQuoteIn = quoteIn.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(amountIn, actualQuoteIn.inAmount)

    let amountOutRes = executeScript(
            "./scripts/sequential-swapper/mock_swap.cdc",
            [testTokenAccount.address, mockSwapperConfigs, amountIn]
        )
    Test.expect(amountOutRes, Test.beSucceeded())
    let actualOut = amountOutRes.returnValue! as! UFix64
    Test.assertEqual(expectedOut, actualOut)
}

access(all)
fun testConnectorMockSwapBackSucceeds() {
    log("testConnectorMockSwapBackSucceeds() =================================================")
    let amountIn = 10.0
    let priceRatio1 = 0.5
    let priceRatio2 = 0.2
    let mockSwapperConfigs: [{String: AnyStruct}] = [
        {
            "inVault": Type<@TokenA.Vault>(),
            "outVault": Type<@TokenB.Vault>(),
            "inVaultPath": TokenA.VaultStoragePath,
            "outVaultPath": TokenB.VaultStoragePath,
            "priceRatio": priceRatio1
        }, {
            "inVault": Type<@TokenB.Vault>(),
            "outVault": Type<@TokenC.Vault>(),
            "inVaultPath": TokenB.VaultStoragePath,
            "outVaultPath": TokenC.VaultStoragePath,
            "priceRatio": priceRatio2
        }
    ]
    // default direction is inType -> outType
    let inType = Type<@TokenA.Vault>()
    let outType = Type<@TokenC.Vault>()
    let expectedOut = amountIn / priceRatio1 / priceRatio2

    log("inAmount: \(amountIn)")
    log("expectedOut: \(expectedOut)")

    let quoteOut = executeScript(
            "./scripts/sequential-swapper/mock_quote.cdc",
            [testTokenAccount.address, mockSwapperConfigs, amountIn, true, true] // out=true, reverse=true
        )
    Test.expect(quoteOut, Test.beSucceeded())
    let actualQuoteOut = quoteOut.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(inType, actualQuoteOut.outType) // reverse direction
    Test.assertEqual(outType, actualQuoteOut.inType) // reverse direction
    Test.assertEqual(amountIn, actualQuoteOut.inAmount)
    Test.assertEqual(expectedOut, actualQuoteOut.outAmount)

    let quoteIn = executeScript(
            "./scripts/sequential-swapper/mock_quote.cdc",
            [testTokenAccount.address, mockSwapperConfigs, expectedOut, false, true] // out=false, reverse=true
        )
    Test.expect(quoteIn, Test.beSucceeded())
    let actualQuoteIn = quoteIn.returnValue! as! {DeFiActions.Quote}
    Test.assertEqual(amountIn, actualQuoteIn.inAmount)

    let amountOutRes = executeScript(
            "./scripts/sequential-swapper/mock_swap_back.cdc",
            [testTokenAccount.address, mockSwapperConfigs, amountIn]
        )
    Test.expect(amountOutRes, Test.beSucceeded())
    let actualOut = amountOutRes.returnValue! as! UFix64
    Test.assertEqual(expectedOut, actualOut)
    log("testConnectorMockSwapBackSucceeds() =================================================")
}
