import "FungibleToken"

import "SwapConnectors"
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
        /// Note: The returned quote is the best estimate for the input amount and the corresponding
        ///       output amount. The output amount may be slightly different from the desired output amount
        ///       due to the precision of the UFix64 type.
        ///       This function returns 0.0 for unachievable amounts.
        ///
        /// @param forDesired: the amount of the output token to receive
        /// @param reverse: if reverse is false, will estimate the amount of token0 to provide for a desired LP amount
        ///                 if reverse is true, will estimate the amount of LP tokens to provide for a desired token0 amount
        ///
        /// @return a DeFiActions.Quote struct containing the estimated amount required to provide a Vault with the desired output balance
        ///
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {DeFiActions.Quote} {
            // Handle zero amount case gracefully
            if (forDesired == 0.0) {
                return SwapConnectors.BasicQuote(
                    inType: reverse ? self.outType() : self.inType(),
                    outType: reverse ? self.inType() : self.outType(),
                    inAmount: 0.0,
                    outAmount: 0.0
                )
            }

            let pairPublicRef = self.getPairPublicRef()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            let token0Reserve = tokenReserves[0]
            let token1Reserve = tokenReserves[1]
            assert(token0Reserve > 0.0 && token1Reserve > 0.0, message: "Pool must have positive reserves")

            let pairInfo = pairPublicRef.getPairInfo()
            let lpTokenSupply = pairInfo[5] as! UFix64
            assert(lpTokenSupply > 0.0, message: "Pool must have positive LP token supply")

            // The number of epochs to run the binary search for
            // It takes ~64 iterations to exhaust UFix64 precision
            let estimationEpochs = 64

            // Use binary search to find the optimal input amount
            // Start with reasonable bounds based on current reserves
            var minInput = SwapConfig.ufix64NonZeroMin
            var maxInput = 0.0
            if (!reverse) {
                let maxLpMintAmount = self.getMaxLpMintAmount(pairPublicRef: pairPublicRef)
                // Unachievable
                if forDesired > maxLpMintAmount {
                    return SwapConnectors.BasicQuote(
                        inType: self.inType(),
                        outType: self.outType(),
                        inAmount: 0.0,
                        outAmount: forDesired
                    )
                }

                // Top bound to calculate how much token0 we'd need to provide to get the desired LP amount
                maxInput = UFix64.max
            } else {
                let maxToken0Returned = self.getMaxToken0Returned(pairPublicRef: pairPublicRef)
                // Unachievable
                if forDesired > maxToken0Returned {
                    return SwapConnectors.BasicQuote(
                        inType: self.outType(),
                        outType: self.inType(),
                        inAmount: 0.0,
                        outAmount: forDesired
                    )
                }

                // Top bound to calculate how much LP tokens we'd need to provide to get the desired token0 amount
                maxInput = lpTokenSupply
            }

            // Binary search to find the input amount that produces the desired output
            var bestResult = 0.0
            var bestInput = 0.0
            var bestDiff = 0.0
            var epoch = 0
            while (epoch < estimationEpochs) {
                let midInput = minInput * 0.5 + maxInput * 0.5

                // Calculate how much tokens we'd get from this input
                let result = self.quoteOut(forProvided: midInput, reverse: reverse).outAmount

                // Track the best result we've seen
                // Note: We look for numbers that are less than the desired amount.
                let currentDiff = result <= forDesired ? forDesired - result : UFix64.max
                if (bestResult == 0.0 || currentDiff < bestDiff) {
                    bestDiff = currentDiff
                    bestResult = result
                    bestInput = midInput
                }

                if (result > forDesired) {
                    maxInput = midInput
                } else if (result < forDesired) {
                    minInput = midInput
                } else {
                    break
                }

                // Precision check, we can't be more precise than this for midInput
                if (maxInput - minInput <= SwapConfig.ufix64NonZeroMin) {
                    break
                }

                epoch = epoch + 1
            }

            // Final validation
            assert(bestInput > 0.0, message: "Failed to calculate valid input amount")
            assert(bestResult > 0.0, message: "Failed to calculate valid result")

            return SwapConnectors.BasicQuote(
                inType: reverse ? self.outType() : self.inType(),
                outType: reverse ? self.inType() : self.outType(),
                inAmount: bestInput,
                outAmount: bestResult
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
            // Handle zero amount case gracefully
            if (forProvided == 0.0) {
                return SwapConnectors.BasicQuote(
                    inType: reverse ? self.outType() : self.inType(),
                    outType: reverse ? self.inType() : self.outType(),
                    inAmount: 0.0,
                    outAmount: 0.0
                )
            }

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
                    token0Offset: zappedAmount,
                    token1Offset: swappedAmount,
                    pairPublicRef: pairPublicRef
                )

                return SwapConnectors.BasicQuote(
                    inType: self.inType(),
                    outType: self.outType(),
                    inAmount: forProvided,
                    outAmount: lpAmount
                )
            } else {
                // Reverse operation: calculate how much token0Vault you get when providing LP tokens

                let lpSupply = pairPublicRef.getPairInfo()[5] as! UFix64
                // Unachievable
                if forProvided > lpSupply {
                    return SwapConnectors.BasicQuote(
                        inType: self.inType(),
                        outType: self.outType(),
                        inAmount: forProvided,
                        outAmount: 0.0
                    )
                }

                // Calculate how much token0 and token1 you get from removing liquidity
                let tokenAmounts = self.calculateTokenAmountsFromLp(lpAmount: forProvided, pairPublicRef: pairPublicRef)
                let token0Amount = tokenAmounts[0]
                let token1Amount = tokenAmounts[1]

                // Calculate how much token0 you get when swapping token1 back to token0
                let swappedToken0Amount = self.calculateSwapAmount(
                    amountIn: token1Amount,
                    token0Offset: -Fix64(token0Amount),
                    token1Offset: -Fix64(token1Amount),
                    pairPublicRef: pairPublicRef,
                    reverse: true
                )

                // Total token0 amount = direct token0 + swapped token0
                let totalToken0Amount = token0Amount + swappedToken0Amount

                return SwapConnectors.BasicQuote(
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
                let reserve0Scaled = SwapConfig.UFix64ToScaledUInt256(token0Reserve)
                let reserve1Scaled = SwapConfig.UFix64ToScaledUInt256(token1Reserve)
                let forProvidedScaled = SwapConfig.UFix64ToScaledUInt256(forProvided)
                if (token0Reserve > token1Reserve) {
                    desiredZappedAmount = SwapConfig.ScaledUInt256ToUFix64(
                        forProvidedScaled * reserve1Scaled / reserve0Scaled
                    )
                } else {
                    desiredZappedAmount = SwapConfig.ScaledUInt256ToUFix64(
                        forProvidedScaled * reserve0Scaled / reserve1Scaled
                    )
                }
                let token0Key = self.token0Type.identifier
                var desiredAmountOut = pairPublicRef.getAmountOut(amountIn: desiredZappedAmount, tokenInKey: token0Key)
                var propAmountOut = 0.0
                var minAmount = SwapConfig.ufix64NonZeroMin
                var maxAmount = forProvided - SwapConfig.ufix64NonZeroMin
                var midAmount = 0.0
                if desiredAmountOut <= token1Reserve {
                    propAmountOut = (forProvided - desiredZappedAmount) / (token0Reserve + desiredZappedAmount) * (token1Reserve - desiredAmountOut)
                    var bias = 0.0
                    if (desiredAmountOut > propAmountOut) {
                        bias = desiredAmountOut - propAmountOut
                    } else {
                        bias = propAmountOut - desiredAmountOut
                    }
                    if (bias <= 0.0001) {
                        return desiredZappedAmount
                    } else {
                        if (desiredAmountOut > propAmountOut) {
                            maxAmount = desiredZappedAmount
                        } else {
                            minAmount = desiredZappedAmount
                        }
                    }
                } else {
                    maxAmount = desiredZappedAmount
                }
                var epoch = 0
                while (epoch < 36) {
                    midAmount = minAmount * 0.5 + maxAmount * 0.5;
                    if maxAmount - midAmount < SwapConfig.ufix64NonZeroMin {
                        break
                    }
                    let amountOut = pairPublicRef.getAmountOut(amountIn: midAmount, tokenInKey: token0Key)
                    let reserveAft0 = token0Reserve + midAmount
                    if amountOut <= token1Reserve {
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
                    } else {
                        maxAmount = midAmount
                    }

                    epoch = epoch + 1
                }
                zappedAmount = midAmount
            }
            return zappedAmount
        }

        /// Calculates the amount of LP tokens received for a given token0Amount and token1Amount
        ///
        /// Based on "addLiquidity" function in https://github.com/IncrementFi/Swap/blob/main/src/contracts/SwapPair.cdc
        ///
        /// @param token0Amount: the amount of token0 to add to the pool
        /// @param token1Amount: the amount of token1 to add to the pool
        /// @param token0Offset: the offset of token0 reserves, used to simulate the impact of a swap on the reserves (added)
        /// @param token1Offset: the offset of token1 reserves, used to simulate the impact of a swap on the reserves (subtracted)
        /// @param pairPublicRef: a reference to the pair public interface
        ///
        /// @return the amount of LP tokens received
        ///
        access(self) view fun calculateLpAmount(
            token0Amount: UFix64,
            token1Amount: UFix64,
            token0Offset: UFix64,
            token1Offset: UFix64,
            pairPublicRef: &{SwapInterfaces.PairPublic},
        ): UFix64 {
            let pairInfo = pairPublicRef.getPairInfo()
            let tokenReserves = self.getTokenReserves(pairPublicRef: pairPublicRef)
            var token0Reserve = tokenReserves[0]
            var token1Reserve = tokenReserves[1]

            // Note: simulate zap swap impact on reserves
            // Zapping always swaps token0 -> token1
            token0Reserve = token0Reserve + token0Offset
            token1Reserve = token1Reserve - token1Offset

            let reserve0LastScaled = SwapConfig.UFix64ToScaledUInt256(token0Reserve)
            let reserve1LastScaled = SwapConfig.UFix64ToScaledUInt256(token1Reserve)

            let lpTokenSupply = pairInfo[5] as! UFix64

            assert(token0Reserve > 0.0 && token1Reserve > 0.0, message: "Token0 and token1 reserves must be greater than 0.0")

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
            let liquidity = SwapConfig.ScaledUInt256ToUFix64(mintLptokenAmountScaled)
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
            // Handle negative offsets carefully to prevent underflow
            let token0ReserveWithOffset = Fix64(token0Reserve) + token0Offset
            let token1ReserveWithOffset = Fix64(token1Reserve) + token1Offset

            // Insufficient liquidity
            if token0ReserveWithOffset <= 0.0 || token1ReserveWithOffset <= 0.0 {
                return 0.0
            }

            // Ensure reserves don't go below minimum values
            token0Reserve = UFix64(token0ReserveWithOffset)
            token1Reserve = UFix64(token1ReserveWithOffset)

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

        // Returns the maximum amount of LP tokens that can be minted
        // It's bound by the reserves of token1 that can be swapped to token0
        access(self) fun getMaxLpMintAmount(
            pairPublicRef: &{SwapInterfaces.PairPublic},
        ): UFix64 {
            let quote = self.quoteOut(forProvided: UFix64.max, reverse: false)
            return quote.outAmount
        }

        // Returns the maximum amount of token0 that can be returned by providing all LP tokens
        access(self) fun getMaxToken0Returned(
            pairPublicRef: &{SwapInterfaces.PairPublic},
        ): UFix64 {
            let pairInfo = pairPublicRef.getPairInfo()
            let lpTokenSupply = pairInfo[5] as! UFix64
            let quote = self.quoteOut(forProvided: lpTokenSupply - SwapConfig.ufix64NonZeroMin, reverse: true)
            return quote.outAmount
        }
    }

}
