import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "DeFiActions"
import "FlowTransactionScheduler"

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

    // set the rebalanceSink targetting the TokenB Vault
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

access(all) fun test_RecurringRebalanceToSinkSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    transferFlow(signer: serviceAccount, recipient: user.address, amount: 100.0)
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
    // set the rebalanceSink targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let interval: UInt64 = 10
    let executionEffort: UInt64 = 1_000
    let priority: UInt8 = 2 // High
    let forceRebalance = true
    // set the recurring config which also schedules the next execution based on the configured interval
    let configRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_recurring_config.cdc",
            [autoBalancerStoragePath, interval, priority, executionEffort, forceRebalance],
            user
        )
    Test.expect(configRes, Test.beSucceeded())

    // get the scheduled transaction scheduled event
    var now = getCurrentBlockTimestamp()
    var schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assertEqual(1, schedEvts.length)
    var schedEvt = schedEvts[schedEvts.length - 1] as! FlowTransactionScheduler.Scheduled
    Test.assertEqual(user.address, schedEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, schedEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, schedEvt.executionEffort)
    Test.assertEqual(priority, schedEvt.priority)
    let txnID = schedEvt.id

    // get the scheduled transaction IDs
    var scheduledTransactionIDs = getAutoBalancerScheduledTransactionIDs(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(1, scheduledTransactionIDs.length)
    Test.assertEqual(txnID, scheduledTransactionIDs[0])

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

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
        "./transactions/mock-oracle/set_price.cdc",
        [tokenBIdentifier, tokenBStartPrice * priceIncrease],
        dfbAccount
    )

    Test.moveTime(by: 11.0)

    // get schedule transaction executed event
    var execEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Executed>())
    Test.assertEqual(1, execEvts.length)
    let execEvt = execEvts[execEvts.length - 1] as! FlowTransactionScheduler.Executed
    Test.assertEqual(txnID, execEvt.id)
    Test.assertEqual(user.address, execEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, execEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, execEvt.executionEffort)
    Test.assertEqual(priority, execEvt.priority)

    let startValue = mintAmount * tokenBStartPrice
    let newValue = mintAmount * priceIncrease * tokenBStartPrice
    let valueIncrease = newValue - startValue

    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    // ensure the rebalance was executed
    let rebalanceEvts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, rebalanceEvts.length)
    let rebalanceEvt = rebalanceEvts[rebalanceEvts.length - 1] as! DeFiActions.Rebalanced
    Test.assertEqual(true, rebalanceEvt.isSurplus)
    Test.assertEqual(autoBalancerBalanceBefore - autoBalancerBalanceAfter, rebalanceEvt.amount)
    Test.assertEqual(valueIncrease, rebalanceEvt.value)

    // ensure the next scheduled transaction was scheduled
    now = getCurrentBlockTimestamp()
    schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assertEqual(2, schedEvts.length)
    
    schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    schedEvt = schedEvts[schedEvts.length - 1] as! FlowTransactionScheduler.Scheduled
    Test.assertEqual(user.address, schedEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, schedEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, schedEvt.executionEffort)
    Test.assertEqual(priority, schedEvt.priority)
    let newTxnID = schedEvt.id
    Test.assert(txnID != newTxnID)

    // get the scheduled transaction IDs - should have cleaned up the first one
    scheduledTransactionIDs = getAutoBalancerScheduledTransactionIDs(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(1, scheduledTransactionIDs.length)
    Test.assert(scheduledTransactionIDs[0] == newTxnID)
}

access(all) fun test_RecurringRebalanceFromSourceSucceeds() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    transferFlow(signer: serviceAccount, recipient: user.address, amount: 100.0)
    let lowerThreshold = 0.9
    let upperThreshold = 1.1

    let mintAmount = 100.0
    let priceDecrease = 0.75

    // setup the AutoBalancer
    let setupRes = executeTransaction(
            "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
            [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())
    // setup the user's TokenB Vault
    let vaultRes = executeTransaction(
            "./transactions/test-tokens/setup_vault.cdc",
            [tokenBIdentifier],
            user
        )
    Test.expect(vaultRes, Test.beSucceeded())
    // set the rebalanceSource targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_source_as_token_source.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let interval: UInt64 = 10
    let executionEffort: UInt64 = 1_000
    let priority: UInt8 = 2 // High
    let forceRebalance = true
    // set the recurring config which also schedules the next execution based on the configured interval
    let configRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_recurring_config.cdc",
            [autoBalancerStoragePath, interval, priority, executionEffort, forceRebalance],
            user
        )
    Test.expect(configRes, Test.beSucceeded())

    // get the scheduled transaction scheduled event
    var now = getCurrentBlockTimestamp()
    var schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assertEqual(1, schedEvts.length)
    var schedEvt = schedEvts[schedEvts.length - 1] as! FlowTransactionScheduler.Scheduled
    Test.assertEqual(user.address, schedEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, schedEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, schedEvt.executionEffort)
    Test.assertEqual(priority, schedEvt.priority)
    let txnID = schedEvt.id

    // get the scheduled transaction IDs
    var scheduledTransactionIDs = getAutoBalancerScheduledTransactionIDs(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(1, scheduledTransactionIDs.length)
    Test.assertEqual(txnID, scheduledTransactionIDs[0])

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

    // set TokenB price in the mock oracle
    let priceSetRes = executeTransaction(
        "./transactions/mock-oracle/set_price.cdc",
        [tokenBIdentifier, tokenBStartPrice * priceDecrease],
        dfbAccount
    )

    Test.moveTime(by: 11.0)

    // get schedule transaction executed event
    var execEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Executed>())
    Test.assertEqual(1, execEvts.length)
    let execEvt = execEvts[execEvts.length - 1] as! FlowTransactionScheduler.Executed
    Test.assertEqual(txnID, execEvt.id)
    Test.assertEqual(user.address, execEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, execEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, execEvt.executionEffort)
    Test.assertEqual(priority, execEvt.priority)

    let startValue = mintAmount * tokenBStartPrice
    let newValue = mintAmount * priceDecrease * tokenBStartPrice
    let valueDecrease = startValue - newValue

    let autoBalancerBalanceAfter = getAutoBalancerBalance(address: user.address, publicPath: autoBalancerPublicPath)!
    let currentValueAfter = getAutoBalancerCurrentValue(address: user.address, publicPath: autoBalancerPublicPath)!
    let valueOfDepositsAfter = getAutoBalancerValueOfDeposits(address: user.address, publicPath: autoBalancerPublicPath)!

    // ensure the rebalance was executed
    let rebalanceEvts = Test.eventsOfType(Type<DeFiActions.Rebalanced>())
    Test.assertEqual(1, rebalanceEvts.length)
    let rebalanceEvt = rebalanceEvts[rebalanceEvts.length - 1] as! DeFiActions.Rebalanced
    Test.assertEqual(false, rebalanceEvt.isSurplus)
    Test.assertEqual(autoBalancerBalanceBefore - autoBalancerBalanceAfter, rebalanceEvt.amount)
    Test.assertEqual(valueDecrease, rebalanceEvt.value)

    // ensure the next scheduled transaction was scheduled
    now = getCurrentBlockTimestamp()
    schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assertEqual(2, schedEvts.length)
    
    schedEvts = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    schedEvt = schedEvts[schedEvts.length - 1] as! FlowTransactionScheduler.Scheduled
    Test.assertEqual(user.address, schedEvt.transactionHandlerOwner)
    Test.assertEqual(Type<@DeFiActions.AutoBalancer>().identifier, schedEvt.transactionHandlerTypeIdentifier)
    Test.assertEqual(executionEffort, schedEvt.executionEffort)
    Test.assertEqual(priority, schedEvt.priority)
    let newTxnID = schedEvt.id
    Test.assert(txnID != newTxnID)

    // get the scheduled transaction IDs - should have cleaned up the first one
    scheduledTransactionIDs = getAutoBalancerScheduledTransactionIDs(address: user.address, publicPath: autoBalancerPublicPath)!
    Test.assertEqual(1, scheduledTransactionIDs.length)
    Test.assert(scheduledTransactionIDs[0] == newTxnID)
}

access(all) fun test_AttemptToSetRecurringConfigForDifferentAutoBalancerFails() {
    Test.reset(to: snapshot)
    let user = Test.createAccount()
    transferFlow(signer: serviceAccount, recipient: user.address, amount: 100.0)
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
    // set the rebalanceSink targetting the TokenB Vault
    let setRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_rebalance_sink_as_token_sink.cdc",
            [tokenBIdentifier, nil, autoBalancerStoragePath],
            user
        )
    Test.expect(setupRes, Test.beSucceeded())

    let interval: UInt64 = 10
    let executionEffort: UInt64 = 1_000
    let priority: UInt8 = 2 // High
    let forceRebalance = true
    // set the recurring config which also schedules the next execution based on the configured interval
    let configRes = executeTransaction(
            "../transactions/auto-balance-adapter/set_recurring_config.cdc",
            [autoBalancerStoragePath, interval, priority, executionEffort, forceRebalance],
            user
        )
    Test.expect(configRes, Test.beSucceeded())

    let attacker = Test.createAccount()
    let attackerSetupRes = executeTransaction(
        "../transactions/auto-balance-adapter/create_auto_balancer.cdc",
        [tokenAIdentifier, nil, lowerThreshold, upperThreshold, tokenBIdentifier, autoBalancerStoragePath, autoBalancerPublicPath],
        attacker
    )
    Test.expect(attackerSetupRes, Test.beSucceeded())

    let attackerConfigRes = executeTransaction(
        "./transactions/attempt_copy_auto_balancer_config.cdc",
        [user.address, autoBalancerPublicPath, autoBalancerStoragePath],
        attacker
    )
    Test.expect(attackerConfigRes, Test.beFailed())
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
