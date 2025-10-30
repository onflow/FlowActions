import Test
import BlockchainHelpers
import "test_helpers.cdc"

import "FungibleToken"
import "FlowToken"
import "TokenA"
import "TokenB"
import "SwapConfig"
import "SwapFactory"

import "DeFiActions"
import "IncrementFiStakingConnectors"
import "Staking"

access(all) let serviceAccount = Test.serviceAccount()
access(all) let incrementFiStakingAccount = Test.getAccount(Type<Staking>().address!)
access(all) let startHeight = getCurrentBlockHeight()
access(all) var stakingTokenType: Type? = nil
access(all) var tokenAKey: String? = nil
access(all) var tokenBKey: String? = nil

// Test configuration constants
access(all) let testDepositAmount: UFix64 = 100.0
access(all) let testTimeAdvanceSeconds: Fix64 = 10.0

// Pool configuration values
access(all) let testRps: UFix64 = 1.0
access(all) let testSessionInterval: UFix64 = 1.0
access(all) let testAdminSeedAmount: UFix64 = 1000.0
access(all) let testLimitAmount: UFix64 = 1000000.0
access(all) let testPairCreatorSeedAmount: UFix64 = 1000000.0

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
    err = Test.deployContract(
        name: "IncrementFiFlashloanConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiFlashloanConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "IncrementFiPoolLiquidityConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiPoolLiquidityConnectors.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "IncrementFiStakingConnectors",
        path: "../contracts/connectors/increment-fi/IncrementFiStakingConnectors.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())

    // Add funds to the pair creator account
    transferFlow(
        signer: serviceAccount,
        recipient: incrementFiStakingAccount.address,
        amount: testPairCreatorSeedAmount,
    )

    tokenAKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier)
    tokenBKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenB.Vault>().identifier)

    // Create a swap pair
    createSwapPair(
        signer: incrementFiStakingAccount,
        token0Identifier: Type<@TokenA.Vault>().identifier,
        token1Identifier: Type<@TokenB.Vault>().identifier,
        stableMode: true,
    )

    setupGenericVault(signer: incrementFiStakingAccount, vaultIdentifier: Type<@TokenA.Vault>().identifier)
    setupGenericVault(signer: incrementFiStakingAccount, vaultIdentifier: Type<@TokenB.Vault>().identifier)
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: incrementFiStakingAccount.address,
        amount: 10000.0,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenB>().address!),
        recipient: incrementFiStakingAccount.address,
        amount: 10000.0,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.ReceiverPublicPath
    )

    // Stable mode pool
    addLiquidity(
        signer: incrementFiStakingAccount,
        token0Key: tokenAKey!,
        token1Key: tokenBKey!,
        token0InDesired: 500.0,
        token1InDesired: 500.0,
        token0InMin: 0.0,
        token1InMin: 0.0,
        deadline: getCurrentBlockTimestamp() + 1000.0,
        token0VaultPath: TokenA.VaultStoragePath,
        token1VaultPath: TokenB.VaultStoragePath,
        stableMode: true,
    )

    // Get the LP token type
    let lpTokenTypeIdentifier = "A.".concat(
        (Test.eventsOfType(Type<SwapFactory.PairCreated>())[0] as! SwapFactory.PairCreated).pairAddress
            .toString()
            .slice(from: 2, upTo: incrementFiStakingAccount.address.toString().length)
            .concat(".SwapPair.Vault")
    )

    stakingTokenType = CompositeType(lpTokenTypeIdentifier)!

    // Create a staking pool for LP token
    let rewardInfo = Staking.RewardInfo(
        rewardPerSession: testRps,
        sessionInterval: testSessionInterval,
        rewardTokenKey: SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: Type<@TokenA.Vault>().identifier),
        startTimestamp: getCurrentBlockTimestamp()
    )
    createStakingPool(
        incrementFiStakingAccount,
        testLimitAmount,
        stakingTokenType!,
        [rewardInfo],
        /storage/tokenAVault,
        testDepositAmount
    )
}

access(all) fun testRestakeRewards() {
    let user = Test.createAccount()

    // Setup user vault and mint test tokens
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenA.Vault>().identifier
    )
    setupGenericVault(
        signer: user,
        vaultIdentifier: Type<@TokenB.Vault>().identifier
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenA>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenA.AdminStoragePath,
        receiverPublicPath: TokenA.ReceiverPublicPath
    )
    mintTestTokens(
        signer: Test.getAccount(Type<TokenB>().address!),
        recipient: user.address,
        amount: testDepositAmount,
        minterStoragePath: TokenB.AdminStoragePath,
        receiverPublicPath: TokenB.ReceiverPublicPath
    )

    // Add liquidity to the swap pair
    addLiquidity(
        signer: user,
        token0Key: tokenAKey!,
        token1Key: tokenBKey!,
        token0InDesired: testDepositAmount,
        token1InDesired: testDepositAmount,
        token0InMin: 0.0,
        token1InMin: 0.0,
        deadline: getCurrentBlockTimestamp() + 1000.0,
        token0VaultPath: TokenA.VaultStoragePath,
        token1VaultPath: TokenB.VaultStoragePath,
        stableMode: true,
    )

    // Deposit into the staking pool
    let pid: UInt64 = 0
    var result = executeTransaction(
        "./transactions/increment-fi/deposit_staking_pool.cdc",
        [pid, 100.0, stakingTokenType!],
        user
    )
    Test.expect(result.error, Test.beNil())

    let depositTimestamp = getCurrentBlockTimestamp()

    // Verify that a tokens staked event was emitted with correct values
    let tokenStakedEventsDeposit = Test.eventsOfType(Type<Staking.TokenStaked>())
    Test.expect(tokenStakedEventsDeposit.length, Test.equal(1))
    let tokenStakedEventDeposit = tokenStakedEventsDeposit[0] as! Staking.TokenStaked
    Test.expect(tokenStakedEventDeposit.tokenKey, Test.equal(SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: stakingTokenType!.identifier)))
    Test.expect(tokenStakedEventDeposit.operator, Test.equal(user.address))
    Test.expect(tokenStakedEventDeposit.amount, Test.equal(100.0))

    // Simulate time passing to allow rewards to accumulate
    Test.commitBlock()
    Test.moveTime(by: testTimeAdvanceSeconds)

    // Restake rewards
    result = executeTransaction(
        "../transactions/increment-fi/restake_rewards.cdc",
        [pid],
        user
    )
    Test.expect(result.error, Test.beNil())

    // Verify the token staked event was emitted with correct values
    let tokenStakedEventsRestake = Test.eventsOfType(Type<Staking.TokenStaked>())
    let tokenStakedEventRestake = tokenStakedEventsRestake[tokenStakedEventsRestake.length - 1] as! Staking.TokenStaked

    Test.expect(tokenStakedEventRestake.tokenKey, Test.equal(SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: stakingTokenType!.identifier)))
    Test.expect(tokenStakedEventRestake.operator, Test.equal(user.address))
    Test.expect(tokenStakedEventRestake.amount, Test.beGreaterThan(4.99)) // ~5.0 for 10s
    Test.expect(tokenStakedEventRestake.pid, Test.equal(pid))
}