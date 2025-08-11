import "FungibleToken"

import "SwapStack"
import "DeFiActions"

import "SwapRouter"
import "SwapConfig"
import "SwapFactory"
import "StableSwapFactory"
import "SwapInterfaces"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// IncrementFiPoolLiquidityConnectors
/// Connector for adding liquidity to IncrementFi pools using one token.
///
access(all) contract IncrementFiPoolLiquidityConnectors {

    /// An implementation of DeFiActions.Swapper connector that swaps token0 to token1 and adds liquidity
    /// to the pool using both tokens. It will then return the LP token. It is commonly called a
    /// "zap" operation in other protocols.
    ///
    access(all) struct Zapper : DeFiActions.Swapper {

        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?
        /// The pools token0 type
        access(self) let token0Type: Type
        /// The pools token1 type
        access(self) let token1Type: Type
        /// The pools LP token type
        access(self) let lpType: Type
        /// Stable pool mode flag
        access(self) let stableMode: Bool
        /// The address to access pair capabilities
        access(all) let pairAddress: Address

        init(
            token0Type: Type,
            token1Type: Type,
            stableMode: Bool,
            uniqueID: DeFiActions.UniqueIdentifier?
        ) {
            self.token0Type = token0Type
            self.token1Type = token1Type
            self.stableMode = stableMode
            self.uniqueID = uniqueID

            let token0Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: token0Type.identifier)
            let token1Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: token1Type.identifier)

            self.pairAddress = (stableMode)?
                StableSwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
                    ?? panic("nonexistent stable pair \(token0Key) -> \(token1Key)")
                :
                SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
                    ?? panic("nonexistent pair \(token0Key) -> \(token1Key)")

            let pairPublicRef = getAccount(self.pairAddress)
                .capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!
            self.lpType = pairPublicRef.getLpTokenVaultType()
        }

        /// Returns a list of ComponentInfo for each component in the stack
        ///
        /// @return a list of ComponentInfo for each inner DeFiActions component
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id() ?? nil,
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @return a copy of the struct's UniqueIdentifier
        ///
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        ///
        /// @param id: the UniqueIdentifier to set for this component
        ///
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inType(): Type {
            return self.token0Type
        }

        /// The type of Vault this Swapper provides when performing a swap
        /// In a zap operation, the outType is the LP token type
        access(all) view fun outType(): Type {
            return self.lpType
        }

        /// The estimated amount required to provide a Vault with the desired output balance
        ///
        /// NOTE: quoteIn operation is not implemented and only supported for UFix64.max
        /// Where it returns a placeholder quote with UFix64.max inAmount and outAmount
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            assert(forDesired == UFix64.max, message: "quoteIn operation not implemented")
            return SwapStack.BasicQuote(
                inType: self.inType(),
                outType: self.outType(),
                inAmount: UFix64.max,
                outAmount: UFix64.max
            )
        }

        /// The estimated amount delivered out for a provided input balance
        ///
        /// @param forProvided: the amount of the input token to provide
        /// @param reverse: if reverse is false, will estimate the amount of LP tokens received for a provided input balance
        ///                 if reverse is true, will estimate the amount of token0 received for a provided LP token balance
        ///
        /// @return a DeFiActions.Quote struct containing the estimated amount delivered out for a provided input balance
        ///
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {DeFiActions.Quote} {
            let pairPublicRef = self.getPairPublicRef()
            let token0Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.token0Type.identifier)
            let token1Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.token1Type.identifier)
            if (!reverse) {
                // Calculate how much to zap from token0 to token1
                let zappedAmount = self.calculateZappedAmount(forProvided: forProvided, pairPublicRef: pairPublicRef)

                // Calculate how much we get after swapping zappedAmount of token0 to token1
                let swappedAmount = pairPublicRef.getAmountOut(amountIn: zappedAmount, tokenInKey: token0Key)

                // Calculate lp tokens we're receiving
                let lpAmount = self.calculateLpAmount(
                    token0Amount: forProvided - zappedAmount,
                    token1Amount: swappedAmount,
                    token0Offset: Fix64(zappedAmount),
                    token1Offset: -Fix64(swappedAmount),
                    pairPublicRef: pairPublicRef
                )

                return SwapStack.BasicQuote(
                    inType: self.inType(),
                    outType: self.outType(),
                    inAmount: forProvided,
                    outAmount: lpAmount
                )
            } else {
                // Reverse operation: calculate how much token0Vault you get when providing LP tokens

                // Calculate how much token0 and token1 you get from removing liquidity
                let tokenAmounts = self.calculateTokenAmountsFromLp(lpAmount: forProvided, pairPublicRef: pairPublicRef)
                let token0Amount = tokenAmounts[0]
                let token1Amount = tokenAmounts[1]

                // Calculate how much token0 you get when swapping token1 back to token0
                // Note: The impact of removed liquidity on the swap price is not considered here
                // let swappedToken0Amount = pairPublicRef.getAmountOut(amountIn: token1Amount, tokenInKey: token1Key)
                let swappedToken0Amount = self.calculateSwapAmount(
                    amountIn: token1Amount,
                    token0Offset: -Fix64(token0Amount),
                    token1Offset: -Fix64(token1Amount),
                    pairPublicRef: pairPublicRef,
                    reverse: true
                )

                // Total token0 amount = direct token0 + swapped token0
                let totalToken0Amount = token0Amount + swappedToken0Amount

                return SwapStack.BasicQuote(
                    inType: self.outType(), // LP token type
                    outType: self.inType(), // token0 type
                    inAmount: forProvided,
                    outAmount: totalToken0Amount
                )
            }
        }

        /// Converts inToken to LP token
        access(all) fun swap(quote: {DeFiActions.Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let pairPublicRef = self.getPairPublicRef()
            let zappedAmount = self.calculateZappedAmount(forProvided: inVault.balance, pairPublicRef: pairPublicRef)

            // Swap
            let swapVaultIn <- inVault.withdraw(amount: zappedAmount)
            let token1Vault <- pairPublicRef.swap(vaultIn: <-swapVaultIn, exactAmountOut: nil)

            // Add liquidity
            let lpTokenVault <- pairPublicRef.addLiquidity(
                tokenAVault: <- inVault,
                tokenBVault: <- token1Vault
            )

            // Return the LP token vault
            return <-lpTokenVault
        }

        /// Converts back LP token to inToken
        access(all) fun swapBack(quote: {DeFiActions.Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let pairPublicRef = self.getPairPublicRef()

            // Remove liquidity
            let tokens <- pairPublicRef.removeLiquidity(lpTokenVault: <-residual)
            let token0Vault <- tokens[0].withdraw(amount: tokens[0].balance)
            let token1Vault <- tokens[1].withdraw(amount: tokens[1].balance)
            destroy tokens

            // Swap token1 to token0
            let swappedVault <- pairPublicRef.swap(vaultIn: <-token1Vault, exactAmountOut: nil)
            token0Vault.deposit(from: <-swappedVault)

            return <-token0Vault
        }

        /// Returns a reference to the pair public interface
        access(self) view fun getPairPublicRef(): &{SwapInterfaces.PairPublic} {
            return getAccount(self.pairAddress)
                .capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!
        }

        /// Calculates the zapped amount for a given provided amount
        /// This amount is swapped from token A to token B in order to add liquidity to the pool
        ///
        /// Based on https://github.com/IncrementFi/Swap/blob/main/src/scripts/query/query_zapped_amount.cdc
        ///
        /// @param forProvided: the total amount of the input token0
        /// @param pairPublicRef: a reference to the pair public interface
        ///
        /// @return the amount of token0 to convert to token1 before adding liquidity
        ///
        access(self) view fun calculateZappedAmount(
            forProvided: UFix64,
            pairPublicRef: &{SwapInterfaces.PairPublic},
        ): UFix64 {
            let pairInfo = pairPublicRef.getPairInfo()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            var token0Reserve = tokenReserves[0]
            var token1Reserve = tokenReserves[1]
            assert(token0Reserve != 0.0, message: "Cannot add liquidity zapped in a new pool.")
            var zappedAmount = 0.0
            if !self.stableMode {
                // Cal optimized zapped amount through dex
                let r0Scaled = SwapConfig.UFix64ToScaledUInt256(token0Reserve)
                let swapFeeRateBps = pairInfo[6] as! UInt64
                let fee = 1.0 - UFix64(swapFeeRateBps)/10000.0
                let kplus1SquareScaled = SwapConfig.UFix64ToScaledUInt256((1.0+fee)*(1.0+fee))
                let kScaled = SwapConfig.UFix64ToScaledUInt256(fee)
                let kplus1Scaled = SwapConfig.UFix64ToScaledUInt256(fee+1.0)
                let token0InScaled = SwapConfig.UFix64ToScaledUInt256(forProvided)
                let qScaled = SwapConfig.sqrt(
                    r0Scaled * r0Scaled / SwapConfig.scaleFactor * kplus1SquareScaled / SwapConfig.scaleFactor
                    + 4 * kScaled * r0Scaled / SwapConfig.scaleFactor * token0InScaled / SwapConfig.scaleFactor)
                zappedAmount = SwapConfig.ScaledUInt256ToUFix64(
                    (qScaled - r0Scaled*kplus1Scaled/SwapConfig.scaleFactor)*SwapConfig.scaleFactor/(kScaled*2)
                )
            } else {
                var desiredZappedAmount = 0.0
                if (token0Reserve > token1Reserve) {
                    desiredZappedAmount = forProvided * token1Reserve / token0Reserve
                } else {
                    desiredZappedAmount = forProvided * token0Reserve / token1Reserve
                }
                let token0Key = self.token0Type.identifier
                let desiredAmountOut = pairPublicRef.getAmountOut(amountIn: desiredZappedAmount, tokenInKey: token0Key)
                let propAmountOut = (forProvided - desiredZappedAmount) / (token0Reserve + desiredZappedAmount) * (token1Reserve - desiredAmountOut)
                var bias = 0.0
                if (desiredAmountOut > propAmountOut) {
                    bias = desiredAmountOut - propAmountOut
                } else {
                    bias = propAmountOut - desiredAmountOut
                }
                if (bias <= 0.0001) {
                    zappedAmount = desiredZappedAmount
                } else {
                    var minAmount = SwapConfig.ufix64NonZeroMin
                    var maxAmount = forProvided - SwapConfig.ufix64NonZeroMin
                    var midAmount = 0.0
                    if (desiredAmountOut > propAmountOut) {
                        maxAmount = desiredZappedAmount
                    } else {
                        minAmount = desiredZappedAmount
                    }
                    var epoch = 0
                    while (epoch < 36) {
                        midAmount = (minAmount + maxAmount) * 0.5;
                        if maxAmount - midAmount < SwapConfig.ufix64NonZeroMin {
                            break
                        }
                        let amountOut = pairPublicRef.getAmountOut(amountIn: midAmount, tokenInKey: token0Key)
                        let reserveAft0 = token0Reserve + midAmount
                        let reserveAft1 = token1Reserve - amountOut
                        let ratioUser = (forProvided - midAmount) / amountOut
                        let ratioPool = reserveAft0 / reserveAft1
                        var ratioBias = 0.0
                        if (ratioUser >= ratioPool) {
                            if (ratioUser - ratioPool) <= SwapConfig.ufix64NonZeroMin {
                                break
                            }
                            minAmount = midAmount
                        } else {
                            if (ratioPool - ratioUser) <= SwapConfig.ufix64NonZeroMin {
                                break
                            }
                            maxAmount = midAmount
                        }
                        epoch = epoch + 1
                    }
                    zappedAmount = midAmount
                }
            }
            return zappedAmount
        }

        /// Calculates the amount of LP tokens received for a given token0Amount and token1Amount
        ///
        /// Based on "addLiquidity" function in https://github.com/IncrementFi/Swap/blob/main/src/contracts/SwapPair.cdc
        ///
        /// @param token0Amount: the amount of token0 to add to the pool
        /// @param token1Amount: the amount of token1 to add to the pool
        /// @param token0Offset: the offset of token0 reserves, used to simulate the impact of a swap on the reserves
        /// @param token1Offset: the offset of token1 reserves, used to simulate the impact of a swap on the reserves
        /// @param pairPublicRef: a reference to the pair public interface
        ///
        /// @return the amount of LP tokens received
        ///
        access(self) view fun calculateLpAmount(
            token0Amount: UFix64,
            token1Amount: UFix64,
            token0Offset: Fix64,
            token1Offset: Fix64,
            pairPublicRef: &{SwapInterfaces.PairPublic},
        ): UFix64 {
            let pairInfo = pairPublicRef.getPairInfo()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            var token0Reserve = tokenReserves[0]
            var token1Reserve = tokenReserves[1]

            // Note: simulate zap swap impact on reserves
            token0Reserve = UFix64(Fix64(token0Reserve) + token0Offset)
            token1Reserve = UFix64(Fix64(token1Reserve) + token1Offset)

            let reserve0LastScaled = SwapConfig.UFix64ToScaledUInt256(token0Reserve)
            let reserve1LastScaled = SwapConfig.UFix64ToScaledUInt256(token1Reserve)

            let lpTokenSupply = pairInfo[5] as! UFix64

            var liquidity = 0.0
            var amount0Added = 0.0
            var amount1Added = 0.0
            if (token0Reserve == 0.0 && token1Reserve == 0.0) {
                var donateLpBalance = 0.0
                if self.stableMode {
                    donateLpBalance = 0.0001    // 1e-4
                } else {
                    donateLpBalance = 0.000001  // 1e-6
                }
                // When adding initial liquidity, the balance should not be below certain minimum amount
                assert(token0Amount > donateLpBalance && token1Amount > donateLpBalance, message:
                    "Token0 and token1 amounts must be greater than minimum donation amount"
                )
                /// Calculate rootK
                let e18: UInt256 = SwapConfig.scaleFactor
                let balance0Scaled = SwapConfig.UFix64ToScaledUInt256(token0Amount)
                let balance1Scaled = SwapConfig.UFix64ToScaledUInt256(token1Amount)
                var initialLpAmount = 0.0
                if self.stableMode {
                    let _p_scaled: UInt256 = SwapConfig.UFix64ToScaledUInt256(1.0)
                    let _k_scaled: UInt256 = SwapConfig.k_stable_p(balance0Scaled, balance1Scaled, _p_scaled)
                    initialLpAmount = SwapConfig.ScaledUInt256ToUFix64(SwapConfig.sqrt(SwapConfig.sqrt(_k_scaled / 2)))
                } else {
                    initialLpAmount = SwapConfig.ScaledUInt256ToUFix64(SwapConfig.sqrt(balance0Scaled * balance1Scaled / e18))
                }
                liquidity = initialLpAmount - donateLpBalance
            } else {
                var lptokenMintAmount0Scaled: UInt256 = 0
                var lptokenMintAmount1Scaled: UInt256 = 0

                /// Use UFIx64ToUInt256 in division & multiply to solve precision issues
                let inAmountAScaled = SwapConfig.UFix64ToScaledUInt256(token0Amount)
                let inAmountBScaled = SwapConfig.UFix64ToScaledUInt256(token1Amount)

                let totalSupplyScaled = SwapConfig.UFix64ToScaledUInt256(lpTokenSupply)

                lptokenMintAmount0Scaled = inAmountAScaled * totalSupplyScaled / reserve0LastScaled
                lptokenMintAmount1Scaled = inAmountBScaled * totalSupplyScaled / reserve1LastScaled

                /// Note: User should add proportional liquidity as any extra is added into pool.
                let mintLptokenAmountScaled = lptokenMintAmount0Scaled < lptokenMintAmount1Scaled ? lptokenMintAmount0Scaled : lptokenMintAmount1Scaled
                liquidity = SwapConfig.ScaledUInt256ToUFix64(mintLptokenAmountScaled)
            }
            return liquidity
        }

        /// Calculates the amount of token0 and token1 you get when removing liquidity with a given LP amount
        ///
        /// Based on "removeLiquidity" function in https://github.com/IncrementFi/Swap/blob/main/src/contracts/SwapPair.cdc
        ///
        /// @param lpAmount: the amount of LP tokens to remove
        /// @param pairPublicRef: a reference to the pair public interface
        ///
        /// @return an array where [0] = token0Amount, [1] = token1Amount
        ///
        access(self) view fun calculateTokenAmountsFromLp(
            lpAmount: UFix64,
            pairPublicRef: &{SwapInterfaces.PairPublic}
        ): [UFix64; 2] {
            let pairInfo = pairPublicRef.getPairInfo()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            let token0Reserve = SwapConfig.UFix64ToScaledUInt256(tokenReserves[0])
            let token1Reserve = SwapConfig.UFix64ToScaledUInt256(tokenReserves[1])

            let lpTokenSupply = pairInfo[5] as! UFix64

            // Calculate proportional amounts based on LP share
            let lpAmountScaled = SwapConfig.UFix64ToScaledUInt256(lpAmount)
            let lpTokenSupplyScaled = SwapConfig.UFix64ToScaledUInt256(lpTokenSupply)
            let token0Amount = SwapConfig.ScaledUInt256ToUFix64(token0Reserve * lpAmountScaled / lpTokenSupplyScaled)
            let token1Amount = SwapConfig.ScaledUInt256ToUFix64(token1Reserve * lpAmountScaled / lpTokenSupplyScaled)

            return [token0Amount, token1Amount]
        }

        /// Returns the reserves of the token0 and token1 in the pair
        ///
        /// @param pairPublicRef: a reference to the pair public interface
        ///
        /// @return an array where [0] = token0Reserve, [1] = token1Reserve
        ///
        access(self) view fun getTokenReserves(
            pairPublicRef: &{SwapInterfaces.PairPublic}
        ): [UFix64; 2] {
            let pairInfo = pairPublicRef.getPairInfo()
            var token0Reserve = 0.0
            var token1Reserve = 0.0
            let token0Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: self.token0Type.identifier)
            if token0Key == (pairInfo[0] as! String) {
                token0Reserve = (pairInfo[2] as! UFix64)
                token1Reserve = (pairInfo[3] as! UFix64)
            } else {
                token0Reserve = (pairInfo[3] as! UFix64)
                token1Reserve = (pairInfo[2] as! UFix64)
            }
            return [token0Reserve, token1Reserve]
        }

        /// Calculates the amount of token0 received when swapping token1 to token0 with custom reserve values
        /// If reverse is true, the amountIn is token1Amount
        /// If reverse is false, the amountIn is token0Amount
        ///
        /// @param amountIn: the amount of the input token
        /// @param token0Offset: the offset of token0 reserves, used to simulate the impact of a swap on the reserves
        /// @param token1Offset: the offset of token1 reserves, used to simulate the impact of a swap on the reserves
        /// @param pairPublicRef: a reference to the pair public interface
        /// @param reverse: if reverse is true, the amountIn is token1Amount
        ///                 if reverse is false, the amountIn is token0Amount
        ///
        /// @return the amount out of the swap operation
        ///
        access(self) view fun calculateSwapAmount(
            amountIn: UFix64,
            token0Offset: Fix64,
            token1Offset: Fix64,
            pairPublicRef: &{SwapInterfaces.PairPublic},
            reverse: Bool
        ): UFix64 {

            let pairInfo = pairPublicRef.getPairInfo()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            var token0Reserve = tokenReserves[0]
            var token1Reserve = tokenReserves[1]

            // Note: simulate zap swap impact on reserves
            token0Reserve = UFix64(Fix64(token0Reserve) + token0Offset)
            token1Reserve = UFix64(Fix64(token1Reserve) + token1Offset)

            var swappedToken0Amount = 0.0
            if (self.stableMode) {
                swappedToken0Amount = SwapConfig.getAmountOutStable(
                    amountIn: amountIn,
                    reserveIn: reverse ? token1Reserve : token0Reserve,
                    reserveOut: reverse ? token0Reserve : token1Reserve,
                    p: pairInfo[8] as! UFix64,
                    swapFeeRateBps: pairInfo[6] as! UInt64
                )
            } else {
                swappedToken0Amount = SwapConfig.getAmountOutVolatile(
                    amountIn: amountIn,
                    reserveIn: reverse ? token1Reserve : token0Reserve,
                    reserveOut: reverse ? token0Reserve : token1Reserve,
                    swapFeeRateBps: pairInfo[6] as! UInt64
                )
            }
            return swappedToken0Amount
        }
    }

}
