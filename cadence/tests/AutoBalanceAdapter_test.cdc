import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "DeFiActions"

import "TokenA"
import "TokenB"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let dfbAccount = Test.getAccount(0x0000000000000009)
access(all) let testTokenAccount = Test.getAccount(0x0000000000000010)

access(all) let tokenAIdentifier: String = Type<@TokenA.Vault>().identifier // MockOracle's unitOfAccount
access(all) let tokenBIdentifier: String = Type<@TokenB.Vault>().identifier
access(all) let tokenBStartPrice: UFix64 = 2.0
// due to UFix64 precision, some amounts may be a small fraction above/below exact calculations
// this value sets the error bars +/- expected
access(all) let varianceThreshold: UFix64 = 0.00000001

access(all) let autoBalancerStoragePath = /storage/autoBalancerTest
access(all) let autoBalancerPublicPath = /public/autoBalancerTest

access(all) var snapshot: UInt64 = 0

access(all) fun setup() {
    var err = Test.deployContract(
        name: "DeFiActionsUtils",
        path: "../contracts/utils/DeFiActionsUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "DeFiActionsMathUtils",
        path: "../contracts/utils/DeFiActionsMathUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())   err = Test.deployContract(
        name: "DeFiActions",
        path: "../contracts/interfaces/DeFiActions.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenStack",
        path: "../contracts/connectors/FungibleTokenStack.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
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
    err = Test.deployContract(
        name: "TokenB",
        path: "./contracts/TokenB.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "MockOracle",
        path: "./contracts/MockOracle.cdc",
        arguments: [tokenAIdentifier], // unitOfAccountIdentifier
    )
    Test.expect(err, Test.beNil())

    // set TokenB price in MockOracle
    let setRes = executeTransaction(
        "./transactions/mock-oracle/set_price.cdc",
        [tokenBIdentifier, tokenBStartPrice], // double the price of TokenA
        dfbAccount
    )
    Test.expect(setRes, Test.beSucceeded())

    snapshot = getCurrentBlockHeight()
}

access(all) fun test_SetupAutoBalancerSucceeds() {
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let evts = Test.eventsOfType(Type<DeFiActions.CreatedAutoBalancer>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DeFiActions.CreatedAutoBalancer
    Test.assertEqual(lowerThreshold, evt.lowerThreshold)
    Test.assertEqual(upperThreshold, evt.upperThreshold)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

access(all) fun test_SetRebalanceSinkSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let tokenBBalance = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)
    Test.assertEqual(0.0, tokenBBalance!)
}

access(all) fun test_SetRebalanceSourceSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    // setup user with TokenB Vault
    let vaultRes = executeTransaction(
            "./transactions/test-tokens/setup_vault.cdc",
            [tokenBIdentifier],
            user
        )
    Test.expect(vaultRes, Test.beSucceeded())

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_source_as_token_source.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setRes, Test.beSucceeded())

    let tokenBBalance = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)
    Test.assertEqual(0.0, tokenBBalance!)
}

access(all) fun test_ForceRebalanceToSinkSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    let mintAmount = 100.0
    let priceIncrease = 1.25

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // mint TokenB to the AutoBalancer
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: autoBalancerPublicPath
    )

    // ensure proper starting point based on the mint amount & starting price
    let autoBalancerBalanceBefore = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueBefore = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsBefore = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(mintAmount, autoBalancerBalanceBefore)
    Test.assertEqual(mintAmount * tokenBStartPrice, currentValueBefore)
    Test.assertEqual(currentValueBefore, valueOfDepositsBefore)

    // assert starting balance
    let sinkTargetBalanceBefore = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    Test.assertEqual(0.0, sinkTargetBalanceBefore)

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
            "./transactions/mock-oracle/set_price.cdc",
            [tokenBIdentifier, tokenBStartPrice * priceIncrease],
            dfbAccount
        )
    Test.expect(priceSetRes, Test.beSucceeded())

    // execute the rebalance - should push TokenB to rebalanceSink, directing tokens to user's TokenB Vault
    rebalance(signer: user, storagePath: autoBalancerStoragePath, force: true, beFailed: false)

    // ensure proper rebalance post-conditions
    let sinkTargetBalanceAfter = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(autoBalancerBalanceBefore, sinkTargetBalanceAfter + autoBalancerBalanceAfter) // value closure between VaultSink & AutoBalancer
    Test.assertEqual(autoBalancerBalanceBefore / priceIncrease, autoBalancerBalanceAfter) // balance increase proportional to price change
    Test.assertEqual(currentValueBefore, currentValueAfter) // rebalance targets valueOfDeposits
    Test.assertEqual(valueOfDepositsBefore, valueOfDepositsAfter) // rebalance targets valueOfDeposits

    // ensure events emitted with proper values
    let evts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DeFiActions.Rebalanced
    Test.assertEqual(true, evt.isSurplus) // rebalanced on deficit
    Test.assertEqual(sinkTargetBalanceAfter, evt.amount) // should be the amount transferred from AutoBalancer -> VaultSource
    Test.assertEqual(sinkTargetBalanceAfter * tokenBStartPrice * priceIncrease, evt.value) // correct value emission
    Test.assertEqual(tokenAIdentifier, evt.unitOfAccount)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

access(all) fun test_UnforcedRebalanceToSinkSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    let mintAmount = 100.0
    let priceIncrease = 1.25

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // mint TokenB to the AutoBalancer
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: autoBalancerPublicPath
    )

    // ensure proper starting point based on the mint amount & starting price
    let autoBalancerBalanceBefore = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueBefore = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsBefore = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(mintAmount, autoBalancerBalanceBefore)
    Test.assertEqual(mintAmount * tokenBStartPrice, currentValueBefore)
    Test.assertEqual(currentValueBefore, valueOfDepositsBefore)

    // assert starting balance
    let sinkTargetBalanceBefore = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    Test.assertEqual(0.0, sinkTargetBalanceBefore)

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
            "./transactions/mock-oracle/set_price.cdc",
            [tokenBIdentifier, tokenBStartPrice * priceIncrease],
            dfbAccount
        )
    Test.expect(priceSetRes, Test.beSucceeded())

    // execute the rebalance - should push TokenB to rebalanceSink, directing tokens to user's TokenB Vault
    rebalance(signer: user, storagePath: autoBalancerStoragePath, force: false, beFailed: false)

    // ensure proper rebalance post-conditions
    let sinkTargetBalanceAfter = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(autoBalancerBalanceBefore, sinkTargetBalanceAfter + autoBalancerBalanceAfter) // value closure between VaultSink & AutoBalancer
    Test.assertEqual(autoBalancerBalanceBefore / priceIncrease, autoBalancerBalanceAfter) // balance increase proportional to price change
    Test.assertEqual(currentValueBefore, currentValueAfter) // rebalance targets valueOfDeposits
    Test.assertEqual(valueOfDepositsBefore, valueOfDepositsAfter) // rebalance targets valueOfDeposits

    // ensure events emitted with proper values
    let evts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DeFiActions.Rebalanced
    Test.assertEqual(true, evt.isSurplus) // rebalanced on deficit
    Test.assertEqual(sinkTargetBalanceAfter, evt.amount) // should be the amount transferred from AutoBalancer -> VaultSource
    Test.assertEqual(sinkTargetBalanceAfter * tokenBStartPrice * priceIncrease, evt.value) // correct value emission
    Test.assertEqual(tokenAIdentifier, evt.unitOfAccount)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

access(all) fun test_ForceRebalanceFromSourceSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    let mintAmount = 100.0
    let priceDecrease = 0.25

    // setup user with TokenB Vault
    let vaultRes = executeTransaction(
            "./transactions/test-tokens/setup_vault.cdc",
            [tokenBIdentifier],
            user
        )
    Test.expect(vaultRes, Test.beSucceeded())

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_source_as_token_source.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // mint TokenB to the AutoBalancer
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: autoBalancerPublicPath
    )

    // ensure proper starting point based on the mint amount & starting price
    let autoBalancerBalanceBefore = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueBefore = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsBefore = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(mintAmount, autoBalancerBalanceBefore)
    Test.assertEqual(mintAmount * tokenBStartPrice, currentValueBefore)
    Test.assertEqual(currentValueBefore, valueOfDepositsBefore)

    // mint TokenB to the VaultSource target - the TokenB Vault in the user's account
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.VaultPublicPath
    )

    // assert starting balance
    let sourceTargetBalanceBefore = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    Test.assertEqual(mintAmount, sourceTargetBalanceBefore)

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
            "./transactions/mock-oracle/set_price.cdc",
            [tokenBIdentifier, tokenBStartPrice * (1.0 - priceDecrease)],
            dfbAccount
        )
    Test.expect(priceSetRes, Test.beSucceeded())

    // execute the rebalance - should push TokenB to rebalanceSink, directing tokens to user's TokenB Vault
    rebalance(signer: user, storagePath: autoBalancerStoragePath, force: true, beFailed: false)

    // ensure proper rebalance post-conditions
    let sourceTargetBalanceAfter = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    let sourceTargetDiff = sourceTargetBalanceBefore - sourceTargetBalanceAfter
    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(autoBalancerBalanceBefore, autoBalancerBalanceAfter - sourceTargetDiff) // value closure between VaultSource & AutoBalancer
    Test.assertEqual(autoBalancerBalanceBefore / (1.0 - priceDecrease), autoBalancerBalanceAfter) // balance increase proportional to price change
    Test.assert(equalWithinVariance(currentValueBefore, currentValueAfter)) // rebalance targets valueOfDeposits
    Test.assertEqual(valueOfDepositsBefore, valueOfDepositsAfter) // rebalance targets valueOfDeposits

    // ensure events emitted with proper values
    let evts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DeFiActions.Rebalanced
    Test.assertEqual(false, evt.isSurplus) // rebalanced on deficit
    Test.assertEqual(sourceTargetDiff, evt.amount) // should be the amount transferred from VaultSource -> AutoBalancer
    Test.assert(equalWithinVariance(evt.value, sourceTargetDiff * tokenBStartPrice * (1.0 - priceDecrease))) // correct value emission
    Test.assertEqual(tokenAIdentifier, evt.unitOfAccount)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

access(all) fun test_UnforcedRebalanceFromSourceSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    let mintAmount = 100.0
    let priceDecrease = 0.25

    // setup user with TokenB Vault
    let vaultRes = executeTransaction(
            "./transactions/test-tokens/setup_vault.cdc",
            [tokenBIdentifier],
            user
        )
    Test.expect(vaultRes, Test.beSucceeded())

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_source_as_token_source.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    // mint TokenB to the AutoBalancer
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: autoBalancerPublicPath
    )

    // ensure proper starting point based on the mint amount & starting price
    let autoBalancerBalanceBefore = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueBefore = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsBefore = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(mintAmount, autoBalancerBalanceBefore)
    Test.assertEqual(mintAmount * tokenBStartPrice, currentValueBefore)
    Test.assertEqual(currentValueBefore, valueOfDepositsBefore)

    // mint TokenB to the VaultSource target - the TokenB Vault in the user's account
    mintTestTokens(
        signer: testTokenAccount,
        recipient: user.address,
        amount: mintAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.VaultPublicPath
    )

    // assert starting balance
    let sourceTargetBalanceBefore = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    Test.assertEqual(mintAmount, sourceTargetBalanceBefore)

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
            "./transactions/mock-oracle/set_price.cdc",
            [tokenBIdentifier, tokenBStartPrice * (1.0 - priceDecrease)],
            dfbAccount
        )
    Test.expect(priceSetRes, Test.beSucceeded())

    // execute the rebalance - should push TokenB to rebalanceSink, directing tokens to user's TokenB Vault
    rebalance(signer: user, storagePath: autoBalancerStoragePath, force: false, beFailed: false)

    // ensure proper rebalance post-conditions
    let sourceTargetBalanceAfter = getBalance(address: user.address, vaultPublicPath: TokenB.VaultPublicPath)!
    let sourceTargetDiff = sourceTargetBalanceBefore - sourceTargetBalanceAfter
    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    Test.assertEqual(autoBalancerBalanceBefore, autoBalancerBalanceAfter - sourceTargetDiff) // value closure between VaultSource & AutoBalancer
    Test.assertEqual(autoBalancerBalanceBefore / (1.0 - priceDecrease), autoBalancerBalanceAfter) // balance increase proportional to price change
    Test.assert(equalWithinVariance(currentValueBefore, currentValueAfter)) // rebalance targets valueOfDeposits
    Test.assertEqual(valueOfDepositsBefore, valueOfDepositsAfter) // rebalance targets valueOfDeposits

    // ensure events emitted with proper values
    let evts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, evts.length)
    let evt = evts[0] as! DeFiActions.Rebalanced
    Test.assertEqual(false, evt.isSurplus) // rebalanced on deficit
    Test.assertEqual(sourceTargetDiff, evt.amount) // should be the amount transferred from VaultSource -> AutoBalancer
    Test.assert(equalWithinVariance(evt.value, sourceTargetDiff * tokenBStartPrice * (1.0 - priceDecrease))) // correct value emission
    Test.assertEqual(tokenAIdentifier, evt.unitOfAccount)
    Test.assertEqual(tokenBIdentifier, evt.vaultType)
    Test.assertEqual(nil, evt.uniqueID)
}

/* --- Helper --- */

access(all) fun equalWithinVariance(_ expected: UFix64, _ actual: UFix64): Bool {
    if expected == actual + varianceThreshold {
        return true
    } else if actual >= varianceThreshold { // protect underflow
        return expected == actual - varianceThreshold
    }
    return false
}
