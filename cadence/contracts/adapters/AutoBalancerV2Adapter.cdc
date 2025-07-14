import "FungibleToken"
import "DFB"
import "DFBv2"
import "DFBMathUtils"

/// AutoBalancerV2Adapter
///
/// This contract demonstrates how to adapt the high-precision AutoBalancerV2
/// for use in DeFi protocols that require accurate value tracking.
///
access(all) contract AutoBalancerV2Adapter {

    /// Factory function to create a high-precision AutoBalancer
    ///
    /// @param oracle: Price oracle for value calculations
    /// @param vault: Initial vault to deposit
    /// @param lowerThreshold: Lower rebalance threshold (e.g., 0.95 for 5% below)
    /// @param upperThreshold: Upper rebalance threshold (e.g., 1.05 for 5% above)
    /// @param rebalanceSink: Optional sink for excess value
    /// @param rebalanceSource: Optional source for deficit value
    /// @return: A new AutoBalancerV2 resource
    ///
    access(all) fun createPrecisionAutoBalancer(
        oracle: {DFB.PriceOracle},
        vault: @{FungibleToken.Vault},
        lowerThreshold: UFix64,
        upperThreshold: UFix64,
        rebalanceSink: {DFB.Sink}?,
        rebalanceSource: {DFB.Source}?
    ): @DFBv2.AutoBalancerV2 {
        return <- DFBv2.createAutoBalancerV2(
            oracle: oracle,
            vault: <-vault,
            rebalanceRange: [lowerThreshold, upperThreshold],
            rebalanceSink: rebalanceSink,
            rebalanceSource: rebalanceSource,
            uniqueID: nil
        )
    }

    /// Example: Calculate compound value with high precision
    ///
    /// This demonstrates how UInt256 calculations prevent precision loss
    /// in compound calculations that would accumulate errors with UFix64.
    ///
    access(all) fun calculateCompoundValue(
        principal: UFix64,
        rate: UFix64,
        periods: UInt64
    ): UFix64 {
        // Convert to UInt256 for precision
        var uintValue = DFBMathUtils.toUInt256(principal)
        let uintRate = DFBMathUtils.toUInt256(1.0 + rate)
        
        // Compound for each period
        var i: UInt64 = 0
        while i < periods {
            uintValue = DFBMathUtils.mul(uintValue, uintRate)
            i = i + 1
        }
        
        // Convert back to UFix64
        return DFBMathUtils.toUFix64(uintValue)
    }

    /// Example: Calculate weighted average price with precision
    ///
    /// Useful for calculating average entry prices across multiple deposits
    ///
    access(all) fun calculateWeightedAveragePrice(
        amounts: [UFix64],
        prices: [UFix64]
    ): UFix64 {
        pre {
            amounts.length == prices.length: "Arrays must have same length"
            amounts.length > 0: "Arrays must not be empty"
        }
        
        var totalValue: UInt256 = 0
        var totalAmount: UInt256 = 0
        
        var i = 0
        while i < amounts.length {
            let uintAmount = DFBMathUtils.toUInt256(amounts[i])
            let uintPrice = DFBMathUtils.toUInt256(prices[i])
            let value = DFBMathUtils.mul(uintAmount, uintPrice)
            
            totalValue = totalValue + value
            totalAmount = totalAmount + uintAmount
            i = i + 1
        }
        
        // Weighted average = total value / total amount
        let avgPrice = DFBMathUtils.div(totalValue, totalAmount)
        return DFBMathUtils.toUFix64(avgPrice)
    }

    /// Example: Calculate percentage change with precision
    ///
    /// Returns the percentage change between two values
    ///
    access(all) fun calculatePercentageChange(
        oldValue: UFix64,
        newValue: UFix64
    ): UFix64 {
        if oldValue == 0.0 {
            return 0.0
        }
        
        let uintOld = DFBMathUtils.toUInt256(oldValue)
        let uintNew = DFBMathUtils.toUInt256(newValue)
        
        // Calculate (new - old) / old * 100
        var difference: UInt256 = 0
        var isNegative = false
        
        if uintNew >= uintOld {
            difference = uintNew - uintOld
        } else {
            difference = uintOld - uintNew
            isNegative = true
        }
        
        // Convert 100 to UInt256 with proper scaling
        let hundred = DFBMathUtils.toUInt256(100.0)
        
        // (difference / old) * 100
        let percentageUInt = DFBMathUtils.mul(
            DFBMathUtils.div(difference, uintOld),
            hundred
        )
        
        let percentage = DFBMathUtils.toUFix64(percentageUInt)
        
        // Note: Cadence doesn't have negative numbers, so we just return the absolute value
        // In a real implementation, you might want to return a struct with sign information
        return percentage
    }

    /// Example: Safe ratio calculation
    ///
    /// Calculates a ratio while handling edge cases and maintaining precision
    ///
    access(all) fun calculateRatio(
        numerator: UFix64,
        denominator: UFix64
    ): UFix64? {
        if denominator == 0.0 {
            return nil
        }
        
        let uintNum = DFBMathUtils.toUInt256(numerator)
        let uintDen = DFBMathUtils.toUInt256(denominator)
        
        let ratio = DFBMathUtils.div(uintNum, uintDen)
        return DFBMathUtils.toUFix64(ratio)
    }
} 