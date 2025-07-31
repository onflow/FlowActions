import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "IncrementFiStack"
import "Staking"
import "TokenA"
import "SwapConfig"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let incrementFiStakingAccount = Test.getAccount(Type<Staking>().address!)
access(all) var poolStartTimestamp: UFix64 = 0.0
access(all) let startHeight = getCurrentBlockHeight()

// Mock pool configuration values
access(all) let mockRps: UFix64 = 1.0
access(all) let mockSessionInterval: UFix64 = 1.0
access(all) let mockAdminSeedAmount: UFix64 = 1000.0
access(all) let mockLimitAmount: UFix64 = 1000000.0

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
        amount: mockAdminSeedAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    ) 

    // Create a staking pool
    let stakingTokenType = Type<@TokenA.Vault>()
    let rewardInfo = Staking.RewardInfo(
        rewardPerSession: mockRps,
        sessionInterval: mockSessionInterval,
        rewardTokenKey: SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier),
        startTimestamp: getCurrentBlockTimestamp()
    )
    createStakingPool(
        incrementFiStakingAccount,
        mockLimitAmount,
        stakingTokenType,
        [rewardInfo],
        mockAdminSeedAmount
    )

    poolStartTimestamp = getCurrentBlockTimestamp()

    var err = Test.deployContract(
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
        name: "IncrementFiStack",
        path: "../contracts/connectors/IncrementFiStack.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testSink() {
    let user = Test.createAccount()

    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: 200.0,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )

    let pid: UInt64 = 0
    let saveResult = executeTransaction(
        "../transactions/increment-fi-stack/save_pool_sink.cdc",
        [pid],
        user
    )
    Test.expect(saveResult.error, Test.beNil())

    let tokenStakedEvents = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEvents.length, Test.equal(1))

    let tokenStakedEvent = tokenStakedEvents[0] as! Staking.TokenStaked
    Test.expect(
        tokenStakedEvent.tokenKey,
        Test.equal(SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier))
    )
    Test.expect(
        tokenStakedEvent.operator,
        Test.equal(user.address)
    )
    Test.expect(
        tokenStakedEvent.amount,
        Test.equal(200.0)
    )
    Test.expect(
        tokenStakedEvent.pid,
        Test.equal(pid)
    )
}

access(all) fun testSource() {
    let user = Test.createAccount()
    let depositAmount: UFix64 = 200.0

    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: depositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    ) 

    let pid: UInt64 = 0
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_pool.cdc",
        [pid, depositAmount],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Simulate time passing to allow rewards to accumulate
    Test.moveTime(by: 10.0)
    Test.commitBlock()

    result = executeTransaction(
        "./transactions/increment-fi/create_pool_rewards_source.cdc",
        [pid, /storage/incrementFiRewardsSource],
        user
    )
    Test.expect(result.error, Test.beNil())

    let rewardClaimedEvents = Test.eventsOfType(Type<Staking.RewardClaimed>())
    Test.expect(rewardClaimedEvents.length, Test.equal(1))

    let rewardClaimedEvent = rewardClaimedEvents[0] as! Staking.RewardClaimed

    let elapsed = getCurrentBlockTimestamp() - poolStartTimestamp
    // We are the only staker, so we should receive all rewards
    let expectedAmount = mockRps * elapsed
    let expectedRPS = expectedAmount / depositAmount

    Test.expect(
        rewardClaimedEvent.pid,
        Test.equal(pid)
    )
    Test.expect(
        rewardClaimedEvent.tokenKey,
        Test.equal(SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier))
    )
    Test.expect(
        rewardClaimedEvent.amount,
        Test.equal(expectedAmount)
    )
    Test.expect(
        rewardClaimedEvent.userRPSAfter,
        Test.equal(expectedRPS)
    )
}