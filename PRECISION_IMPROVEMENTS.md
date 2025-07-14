# DeFiBlocks Precision Improvements

## Overview

This document describes the precision improvements made to DeFiBlocks components using UInt256 calculations, following the pattern established in TidalProtocol.

## Components Added

### 1. DFBMathUtils Contract

A utility contract providing high-precision mathematical operations using UInt256 with 18-decimal fixed-point arithmetic.

**Key Features:**
- Conversion utilities between UFix64 and UInt256
- Fixed-point multiplication and division with 18-decimal precision
- Scalar operations for non-scaled values
- Helper functions for power and digit calculations

### 2. DFBv2 Contract with AutoBalancerV2

An enhanced version of the AutoBalancer that uses UInt256 internally for all calculations while maintaining the same external interface.

**Improvements:**
- `_valueOfDeposits` now stored as UInt256 with 18-decimal precision
- All price calculations use UInt256 multiplication
- Rebalance calculations maintain precision for small value differences
- Proportional withdrawal calculations are more accurate

### 3. AutoBalancerV2Adapter

Demonstrates practical usage patterns and provides utility functions for common DeFi calculations:
- Compound value calculations
- Weighted average price calculations
- Percentage change calculations
- Safe ratio calculations

## Benefits

### 1. Improved Precision
- UFix64 has 8 decimal places of precision
- UInt256 with 18-decimal fixed-point provides 10 additional decimal places
- Reduces rounding errors in multiplication and division

### 2. Consistency with TidalProtocol
- Uses the same mathematical approach as TidalProtocol
- Facilitates integration between protocols
- Standardizes precision handling across the ecosystem

### 3. Better Handling of Edge Cases
- Small value differences are preserved
- Accumulation of small deposits maintains accuracy
- Compound calculations don't lose precision over time

## Usage Example

```cadence
import "DFBv2"
import "DFBMathUtils"

// Create a high-precision AutoBalancer
let balancer <- DFBv2.createAutoBalancerV2(
    oracle: myOracle,
    vault: <-myVault,
    rebalanceRange: [0.95, 1.05],
    rebalanceSink: mySink,
    rebalanceSource: mySource,
    uniqueID: nil
)

// All calculations now use UInt256 internally
let currentValue = balancer.currentValue()  // Returns UFix64 for compatibility
let valueOfDeposits = balancer.valueOfDeposits()  // Internally tracked as UInt256
```

## Migration Guide

### For AutoBalancer Users

1. Replace `DFB.AutoBalancer` with `DFBv2.AutoBalancerV2`
2. Use `DFBv2.createAutoBalancerV2()` factory function
3. External interface remains the same - no changes to method calls
4. Internal precision improvements are automatic

### For Custom Calculations

Use `DFBMathUtils` for any calculations requiring high precision:

```cadence
// Instead of:
let value = price * amount

// Use:
let uintPrice = DFBMathUtils.toUInt256(price)
let uintAmount = DFBMathUtils.toUInt256(amount)
let uintValue = DFBMathUtils.mul(uintPrice, uintAmount)
let value = DFBMathUtils.toUFix64(uintValue)
```

## Testing

The `AutoBalancerV2_test.cdc` file demonstrates:
- Precision comparisons between UFix64 and UInt256
- Accumulation of small deposits
- Rebalance calculation accuracy
- Proportional withdrawal precision
- Fixed-point math operations

## Future Considerations

1. **Gradual Migration**: The original AutoBalancer remains available for backward compatibility
2. **Performance**: UInt256 operations may have slightly higher gas costs but provide significantly better precision
3. **Standardization**: Consider adopting UInt256 calculations as the standard for all DeFiBlocks components

## Conclusion

These precision improvements ensure that DeFiBlocks components can handle the full range of DeFi use cases with minimal precision loss, making them suitable for high-value operations and long-term value tracking. 