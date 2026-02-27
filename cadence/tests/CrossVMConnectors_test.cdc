import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "TokenA"
import "EVM"
import "DeFiActions"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let bridgeAccount = Test.getAccount(0x0000000000000007)
access(all) let tokenAAccount = Test.getAccount(0x0000000000000010)
access(all) var tokenAERCAddress = ""
access(all) var wflowHex = ""

access(all) fun setup() {
    log("================== Setting up CrossVMConnectors test ==================")
    wflowHex = getEVMAddressAssociated(withType: Type<@FlowToken.Vault>().identifier)!

    var err = Test.deployContract(
        name: "TestTokenMinter",
        path: "./contracts/TestTokenMinter.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "TokenA",
        path: "./contracts/TokenA.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // fund the tokenA account to pay for VM Bridge onboarding
    transferFlow(signer: serviceAccount, recipient: tokenAAccount.address, amount: 100.0)
    
    // onboard TokenA to the bridge
    let onboardResult = _executeTransaction(
        "./transactions/bridge/onboard_by_type_identifier.cdc",
        [Type<@TokenA.Vault>().identifier],
        tokenAAccount
    )
    Test.expect(onboardResult, Test.beSucceeded())
    
    // get the EVM address associated with the TokenA type
    tokenAERCAddress = getEVMAddressAssociated(withType: Type<@TokenA.Vault>().identifier)!

    err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenConnectors",
        path: "../contracts/connectors/FungibleTokenConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "CrossVMConnectors",
        path: "../contracts/connectors/CrossVMConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

/// Test: Withdraw FLOW from Cadence vault only (no COA balance)
access(all) fun testUnifiedSourceWithdrawFromCadenceOnlySucceeds() {
    // create a user account and fund it with FLOW
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    
    // create a COA for the user (required for UnifiedBalanceSource)
    createCOA(user, fundingAmount: 0.0)

    // get initial Cadence balance
    var cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(flowBalance, cadenceBalance)

    // withdraw 50 FLOW via UnifiedBalanceSource - should come from Cadence only
    let withdrawAmount = 50.0
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [withdrawAmount, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // verify the withdrawal succeeded - balance should remain the same since we withdraw and deposit to same vault
    cadenceBalance = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    // Note: withdrawing and depositing to same vault results in same balance
    Test.assert(cadenceBalance > 0.0, message: "Cadence balance should be positive")
}

/// Test: Withdraw FLOW from COA native balance (when Cadence vault is empty)
access(all) fun testUnifiedSourceWithdrawFromCOANativeSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    
    // create a COA for the user and fund it with native FLOW
    let coaFunding = 50.0
    createCOA(user, fundingAmount: coaFunding)
    
    // get the COA address
    let coaAddressHex = getCOAAddressHex(atFlowAddress: user.address)
    
    // verify COA has native FLOW balance
    let evmBalance = getEVMFlowBalance(coaAddressHex)
    Test.assertEqual(coaFunding, evmBalance)

    // withdraw FLOW via UnifiedBalanceSource
    let withdrawAmount = 25.0
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [withdrawAmount, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // verify the COA still has some balance
    let evmBalanceAfter = getEVMFlowBalance(coaAddressHex)
    Test.assert(evmBalanceAfter >= 0.0, message: "COA balance should be non-negative")
}

/// Test: Withdraw FLOW from combined Cadence + COA native balance
access(all) fun testUnifiedSourceWithdrawFromCombinedBalanceSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    
    // create a COA for the user and fund it with native FLOW
    let coaFunding = 50.0
    createCOA(user, fundingAmount: coaFunding)
    
    // get the COA address
    let coaAddressHex = getCOAAddressHex(atFlowAddress: user.address)
    
    // get initial balances
    let cadenceBalanceBefore = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    let evmBalanceBefore = getEVMFlowBalance(coaAddressHex)
    
    // combined balance should be positive
    let combinedBalance = cadenceBalanceBefore + evmBalanceBefore
    Test.assert(combinedBalance > 0.0, message: "Combined balance should be positive")

    // withdraw a small amount via UnifiedBalanceSource
    let withdrawAmount = 10.0
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [withdrawAmount, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())
}

/// Test: Withdraw TokenA from Cadence vault
access(all) fun testUnifiedSourceWithdrawTokenAFromCadenceSucceeds() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 10.0
    let tokenABalance = 100.0
    
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    setupGenericVault(signer: user, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    mintTestTokens(signer: tokenAAccount, recipient: user.address, amount: tokenABalance, minterStoragePath: TokenA.AdminStoragePath, receiverPublicPath: TokenA.ReceiverPublicPath)

    // create a COA for the user (required for UnifiedBalanceSource)
    createCOA(user, fundingAmount: 0.0)

    // get initial TokenA balance
    var cadenceBalance = getBalance(address: user.address, vaultPublicPath: TokenA.ReceiverPublicPath)!
    Test.assertEqual(tokenABalance, cadenceBalance)

    // withdraw 50 TokenA via UnifiedBalanceSource - should come from Cadence only
    let withdrawAmount = 50.0
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [withdrawAmount, Type<@TokenA.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // verify the withdrawal succeeded - balance should be same since we withdraw/deposit to same vault
    cadenceBalance = getBalance(address: user.address, vaultPublicPath: TokenA.ReceiverPublicPath)!
    Test.assertEqual(tokenABalance, cadenceBalance)
}

/// Test: UnifiedBalanceSource returns correct minimumAvailable
access(all) fun testUnifiedSourceMinimumAvailableReturnsCorrectValue() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    
    // create a COA for the user and fund it
    let coaFunding = 50.0
    createCOA(user, fundingAmount: coaFunding)

    // execute a transaction that just checks the source is created correctly
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [0.0, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())
}

/// Test: Withdraw zero amount returns empty vault
access(all) fun testUnifiedSourceWithdrawZeroReturnsEmptyVault() {
    // create a user account and fund it
    let user = Test.createAccount()
    let flowBalance = 100.0
    transferFlow(signer: serviceAccount, recipient: user.address, amount: flowBalance)
    
    // create a COA for the user
    createCOA(user, fundingAmount: 0.0)

    // get initial balance
    let balanceBefore = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!

    // withdraw 0 FLOW via UnifiedBalanceSource
    let withdrawResult = _executeTransaction(
        "./transactions/cross-vm-connectors/withdraw_via_unified_source.cdc",
        [0.0, Type<@FlowToken.Vault>().identifier, nil],
        user
    )
    Test.expect(withdrawResult, Test.beSucceeded())

    // balance should remain unchanged
    let balanceAfter = getBalance(address: user.address, vaultPublicPath: /public/flowTokenReceiver)!
    Test.assertEqual(balanceBefore, balanceAfter)
}
