import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "TokenA"
import "SwapConfig"

import "DeFiActions"
import "IncrementFiStakingConnectors"
import "Staking"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let incrementFiStakingAccount = Test.getAccount(Type<Staking>().address!)
access(all) let startHeight = getCurrentBlockHeight()

// Test configuration constants
access(all) let testDepositAmount: UFix64 = 200.0
access(all) let testTimeAdvanceSeconds: Fix64 = 10.0

// Pool configuration values
access(all) let testRps: UFix64 = 1.0
access(all) let testSessionInterval: UFix64 = 1.0
access(all) let testAdminSeedAmount: UFix64 = 1000.0
access(all) let testLimitAmount: UFix64 = 1000000.0

access(all) fun beforeEach() {
    // Reset the blockchain state before each test
    // We cannot reset to the same block height, so we need to
    // commit a block first to ensure that the state is clean.
    Test.commitBlock()
    Test.reset(to: startHeight)

    setupIncrementFiDependencies()

    // Mint test tokens to the increment fi staking account
    setupGenericVault(
        signer: incrementFiStakingAccount,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: incrementFiStakingAccount.address,
        amount: testAdminSeedAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    // Create a staking pool
    let rewardInfo = Staking.RewardInfo(
        rewardPerSession: testRps,
        sessionInterval: testSessionInterval,
        rewardTokenKey: SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier),
        startTimestamp: getCurrentBlockTimestamp()
    )
    createStakingPool(
        incrementFiStakingAccount,
        testLimitAmount,
        Type<@TokenA.Vault>(),
        [rewardInfo],
        /storage/tokenAVault,
        testAdminSeedAmount,
    )
    
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
        name: "IncrementFiStakingConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiStakingConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSink() {
    let user = Test.createAccount()

    // Setup user vault and mint test tokens
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    let result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify the staking event was emitted with correct values
    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(1))

    let tokenStakedEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    let expectedTokenKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier)

    Test.expect(tokenStakedEvent.tokenKey, Test.equal(expectedTokenKey))
    Test.expect(tokenStakedEvent.operator, Test.equal(user.address))
    Test.expect(tokenStakedEvent.amount, Test.equal(testDepositAmount))
    Test.expect(tokenStakedEvent.pid, Test.equal(pid))
}

access(all) fun testSource() {
    let user = Test.createAccount()

    // Setup user vault and mint test tokens
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0

    // First deposit tokens into the staking pool
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool.cdc",
        [pid, testDepositAmount, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())
    let depositTimestamp = getCurrentBlockTimestamp()

    // Simulate time passing to allow rewards to accumulate
    Test.moveTime(by: testTimeAdvanceSeconds)
    Test.commitBlock()

    // Create and test the rewards source
    result = executeTransaction(
        "./transactions/increment-fi/withdraw_pool_rewards_source.cdc",
        [pid],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify the reward claimed event was emitted with correct values
    let rewardClaimedEvents = Test.eventsOfType(Type<Staking.RewardClaimed>())
    Test.expect(rewardClaimedEvents.length, Test.equal(1))

    let rewardClaimedEvent = rewardClaimedEvents[0] as! Staking.RewardClaimed
    let expectedTokenKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier)

    let elapsed = getCurrentBlockTimestamp() - depositTimestamp
    // We are the only staker, so we should receive all rewards
    let expectedRewardAmount = testRps * elapsed
    let expectedRPS = expectedRewardAmount / testDepositAmount

    Test.expect(rewardClaimedEvent.pid, Test.equal(pid))
    Test.expect(rewardClaimedEvent.tokenKey, Test.equal(expectedTokenKey))
    Test.expect(rewardClaimedEvent.amount, Test.equal(expectedRewardAmount))
    Test.expect(rewardClaimedEvent.userRPSAfter, Test.equal(expectedRPS))
}

access(all) fun testSinkAtCapacityLimit() {
    let user = Test.createAccount()
    let stakeAmount = testLimitAmount // Stake exactly at the pool limit

    // Setup user vault and mint test tokens equal to pool limit
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: stakeAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    let result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify the full amount was staked
    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(1))

    let tokenStakedEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    Test.expect(tokenStakedEvent.amount, Test.equal(stakeAmount))
    Test.expect(tokenStakedEvent.pid, Test.equal(pid))
}

access(all) fun testSinkMultipleUsers() {
    let user1 = Test.createAccount()
    let user2 = Test.createAccount()
    // Each user can stake up to testLimitAmount individually
    let user1StakeAmount = testLimitAmount * 0.8 // 800000.0
    let user2StakeAmount = testLimitAmount * 0.5 // 500000.0

    // Setup first user
    setupGenericVault(
        signer: user1,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user1.address,
        amount: user1StakeAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user1
    )
    Test.expect(result.error, Test.beNil())

    // Setup second user
    setupGenericVault(
        signer: user2,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user2.address,
        amount: user2StakeAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user2
    )
    Test.expect(result.error, Test.beNil())

    // Both users should be able to stake their full amounts since limits are per-user
    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(2))

    let firstStakeEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    let secondStakeEvent = tokenStakedEvents[1] as! Staking.TokenStaked

    // The transaction deposits the entire vault balance, so amounts should match what we minted
    Test.expect(firstStakeEvent.amount, Test.equal(user1StakeAmount))
    Test.expect(secondStakeEvent.amount, Test.equal(user2StakeAmount))
    Test.expect(firstStakeEvent.operator, Test.equal(user1.address))
    Test.expect(secondStakeEvent.operator, Test.equal(user2.address))
}

access(all) fun testSinkWithUserAtCapacityLimit() {
    let user = Test.createAccount()

    // Setup user and stake up to their full limit
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testLimitAmount, // Full user limit
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify user has staked their full limit
    let firstStakeEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(firstStakeEvents.length, Test.equal(1))
    let firstStakeEvent = firstStakeEvents[0] as! Staking.TokenStaked
    Test.expect(firstStakeEvent.amount, Test.equal(testLimitAmount))

    // User tries to stake more when they're already at their limit
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Should still have exactly one staking event since the sink deposits 0 when at capacity
    let allStakeEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(allStakeEvents.length, Test.equal(1))

    let tokenStakedEvent = allStakeEvents[0] as! Staking.TokenStaked
    Test.expect(tokenStakedEvent.amount, Test.equal(testLimitAmount))
    Test.expect(tokenStakedEvent.operator, Test.equal(user.address))
}

access(all) fun testMinimumCapacityCalculation() {
    let user = Test.createAccount()
    let partialStakeAmount = testLimitAmount * 0.3 // 30% of pool capacity

    // Setup user and stake partial amount
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: partialStakeAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    let result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify the staking worked and check remaining capacity
    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(1))

    let tokenStakedEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    Test.expect(tokenStakedEvent.amount, Test.equal(partialStakeAmount))

    // The remaining capacity should be testLimitAmount - partialStakeAmount
    let expectedRemainingCapacity = testLimitAmount - partialStakeAmount

    // Note: We can't directly test minimumCapacity() without creating the connector object,
    // but we can verify the behavior by testing another stake that should fit exactly
    let user2 = Test.createAccount()
    setupGenericVault(
        signer: user2,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user2.address,
        amount: expectedRemainingCapacity,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let result2 = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool_sink.cdc",
        [pid, Type<@TokenA.Vault>()],
        user2
    )
    Test.expect(result2.error, Test.beNil())

    // Should now have exactly filled the pool
    let allStakeEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(allStakeEvents.length, Test.equal(2))

    let secondStakeEvent = allStakeEvents[1] as! Staking.TokenStaked
    Test.expect(secondStakeEvent.amount, Test.equal(expectedRemainingCapacity))
}

access(all) fun testSourceAvailableCalculation() {
    let user = Test.createAccount()

    // Setup user vault and mint stake tokens
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0

    // Deposit tokens into the staking pool
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool.cdc",
        [pid, testDepositAmount, Type<@TokenA.Vault>()],
        user
    )
    Test.expect(result.error, Test.beNil())

    let depositTimestamp = getCurrentBlockTimestamp()

    // Immediately attempt to withdraw rewards; should be zero available and emit no events
    result = executeTransaction(
        "./transactions/increment-fi/withdraw_pool_rewards_source.cdc",
        [pid],
        user
    )
    Test.expect(result.error, Test.beNil())

    var rewardClaimedEvents = Test.eventsOfType(Type<Staking.RewardClaimed>())
    Test.expect(rewardClaimedEvents.length, Test.equal(0))

    // Advance time to accrue rewards
    Test.moveTime(by: testTimeAdvanceSeconds)
    Test.commitBlock()

    // Withdraw rewards and try to withdraw more afterwards
    let results = Test.executeTransactions([
        // Withdraw accrued rewards; should equal rps * elapsed
        Test.Transaction(
            code: Test.readFile("./transactions/increment-fi/withdraw_pool_rewards_source.cdc"),
            authorizers: [user.address],
            signers: [user],
            arguments: [pid],
        ),
        // Try to withdraw more than available; should return empty vault
        Test.Transaction(
            code: Test.readFile("./transactions/increment-fi/withdraw_pool_rewards_source.cdc"),
            authorizers: [user.address],
            signers: [user],
            arguments: [pid],
        )
    ])
    Test.expect(results.length, Test.equal(2))
    Test.expect(results[0].error, Test.beNil())
    Test.expect(results[1].error, Test.beNil())

    // Verify that the reward claimed was only emitted once for the first transaction
    rewardClaimedEvents = Test.eventsOfType(Type<Staking.RewardClaimed>())
    Test.expect(rewardClaimedEvents.length, Test.equal(1))

    let rewardClaimedEvent = rewardClaimedEvents[0] as! Staking.RewardClaimed
    let expectedTokenKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier)

    let elapsed = getCurrentBlockTimestamp() - depositTimestamp
    let expectedRewardAmount = testRps * elapsed
    let expectedRPS = expectedRewardAmount / testDepositAmount

    Test.expect(rewardClaimedEvent.pid, Test.equal(pid))
    Test.expect(rewardClaimedEvent.tokenKey, Test.equal(expectedTokenKey))
    Test.expect(rewardClaimedEvent.amount, Test.equal(expectedRewardAmount))
    Test.expect(rewardClaimedEvent.userRPSAfter, Test.equal(expectedRPS))
}