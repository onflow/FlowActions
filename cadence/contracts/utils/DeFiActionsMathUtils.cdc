/// DeFiActionsMathUtils
///
/// This contract contains mathematical utility methods for DeFiActions components
/// using UInt128 for high-precision fixed-point arithmetic.
///
access(all) contract DeFiActionsMathUtils {

    /// Constant for 10^24 (used for 24-decimal fixed-point math)
    access(all) let e24: UInt128
    /// Constant for 10^8 (UFix64 precision)
    access(all) let e8: UInt128
    /// Standard decimal precision for internal calculations
    access(all) let decimals: UInt8
    /// UFix64 decimal precision for internal calculations
    access(self) let ufix64Decimals: UInt8
    /// Scale factor for UInt128 <-> UFix64 conversions
    access(self) let scaleFactor: UInt128 

    access(all) enum RoundingMode: UInt8 {
        /// Rounds down to the nearest decimal
        access(all) case RoundDown
        /// Rounds up to the nearest decimal
        access(all) case RoundUp
        /// Normal rounding: < 5 - round down | >= 5 - round up
        access(all) case RoundHalfUp
        /// TODO: comment about rounding pattern
        access(all) case RoundEven
    }

    /************************
    * CONVERSION UTILITIES *
    ************************/

    /// Converts a UFix64 value to UInt128 with 24 decimal precision
    ///
    /// @param value: The UFix64 value to convert
    /// @return: The UInt128 value scaled to 24 decimals
    access(all) view fun toUInt128(_ value: UFix64): UInt128 {
        let rawUInt64 = UInt64.fromBigEndianBytes(value.toBigEndianBytes())!
        let scaledValue: UInt128 = UInt128(rawUInt64) * self.scaleFactor

        return scaledValue
    }

    /// Converts a UInt128 value with 24 decimal precision to UFix64
    ///
    /// @param value: The UInt128 value to convert
    /// @return: The UFix64 value
    access(all) view fun toUFix64(_ value: UInt128, _ roundingMode: RoundingMode): UFix64 {
        var integerPart = value / self.e24
        var fractionalPart = value % self.e24 / self.scaleFactor
        let remainder = (value % self.e24) % self.scaleFactor

        if self.shouldRoundUp(roundingMode, fractionalPart, remainder) {
            fractionalPart = fractionalPart + UInt128(1)

            if fractionalPart >= self.e8 {
                fractionalPart = fractionalPart - self.e8
                integerPart = integerPart + UInt128(1)
            }
        }


        self.assertWithinUFix64Bounds(integerPart, fractionalPart, value)

        let scaled = UFix64(integerPart) + UFix64(fractionalPart)/UFix64(self.e8)

        // Convert to UFix64 — `scaled` is now at 1e8 base so fractional precision is preserved
        return UFix64(scaled)
    }

    /// Helper to determine rounding condition
    access(self) view fun shouldRoundUp(
        _ roundingMode: RoundingMode, 
        _ fractionalPart: UInt128, 
        _ remainder: UInt128, 
    ): Bool {
        switch roundingMode {
        case self.RoundingMode.RoundUp:
            return remainder > UInt128(0)

        case self.RoundingMode.RoundHalfUp:
            return remainder >= self.scaleFactor / UInt128(2)

        case self.RoundingMode.RoundEven:
            return remainder > self.scaleFactor / UInt128(2) ||
            (remainder == self.scaleFactor / UInt128(2) && fractionalPart % UInt128(2) != UInt128(0))
        }
        return false
    }

    /// Helper to handle overflow assertion
    access(self) view fun assertWithinUFix64Bounds(
        _ integerPart: UInt128, 
        _ fractionalPart: UInt128, 
        _ originalValue: UInt128
    ) {
        assert(
            integerPart <= UInt128(UFix64.max),
            message: "Integer part \(integerPart.toString()) exceeds UFix64 max"
        )

        let MAX_FRACTIONAL_PART = self.toUInt128(0.09551616)
        assert(
            integerPart != UInt128(UFix64.max) || fractionalPart < MAX_FRACTIONAL_PART,
            message: "Fractional part \(fractionalPart.toString()) of scaled integer value \(originalValue.toString()) exceeds max UFix64"
        )
    }

    /***********************
    * FIXED POINT MATH   *
    ***********************/

    /// Multiplies two 24-decimal fixed-point numbers
    ///
    /// @param x: First operand (scaled by 10^24)
    /// @param y: Second operand (scaled by 10^24)
    /// @return: Product scaled by 10^24
    access(all) view fun mul(_ x: UInt128, _ y: UInt128): UInt128 {
        return UInt128(UInt256(x) * UInt256(y) / UInt256(self.e24))
    }

    /// Divides two 24-decimal fixed-point numbers
    ///
    /// @param x: Dividend (scaled by 10^24)
    /// @param y: Divisor (scaled by 10^24)
    /// @return: Quotient scaled by 10^24
    access(all) view fun div(_ x: UInt128, _ y: UInt128): UInt128 {
        pre {
            y > 0: "Division by zero"
        }
        return UInt128((UInt256(x) * UInt256(self.e24)) / UInt256(y))
    }

    /// Divides two UFix64 values with configurable rounding mode.
    ///
    /// Converts both UFix64 inputs to internal UInt128 (24-decimal fixed-point),
    /// performs division, then converts the result back to UFix64, applying the chosen rounding mode.
    ///
    /// @param x: Dividend (UFix64)
    /// @param y: Divisor (UFix64)
    /// @param roundingMode: Rounding mode to use (RoundHalfUp, RoundUp, RoundDown, etc.)
    /// @return: UFix64 quotient, rounded per roundingMode
    access(self) view fun divUFix64(_ x: UFix64, _ y: UFix64, _ roundingMode: RoundingMode): UFix64 {
        pre {
            y > 0.0: "Division by zero"
        }
        let uintX: UInt128 = self.toUInt128(x)
        let uintY: UInt128 = self.toUInt128(y)
        let uintResult = self.div(uintX, uintY)
        let result = self.toUFix64(uintResult, roundingMode)

        return result
    }

    /// Divide two UFix64 values and round to the nearest (ties go up).
    ///
    /// Equivalent to dividing with standard financial "round to nearest" mode.
    access(all) view fun divUFix64WithRounding(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundHalfUp)
    }

    /// Divide two UFix64 values and always round up (ceiling).
    ///
    /// Use for cases where over-estimation is safer (e.g., fee calculations).
    access(all) view fun divUFix64WithRoundingUp(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundUp)
    }

    /// Divide two UFix64 values and always round down (truncate/floor).
    ///
    /// Use for cases where under-estimation is safer (e.g., payout calculations).
    access(all) view fun divUFix64WithRoundingDown(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundDown)
    }

    /*******************
    * HELPER METHODS  *
    *******************/

    /// Rounds a UInt128 value (24 decimals) to a UFix64 value (8 decimals) using round-to-nearest (ties go up).
    ///
    /// Example conversions:
    ///   1e24   -> 1.0
    ///   123456000000000000000 -> 1.23456000
    ///   123456789012345678901 -> 1.23456789
    ///   123456789999999999999 -> 1.23456790  (shows rounding)
    ///
    /// @param value: The UInt128 value to convert and round
    /// @return: The UFix64 value, rounded to the nearest 8 decimals
    access(all) view fun toUFix64Round(_ value: UInt128): UFix64 {
        // Use standard round-half-up (nearest neighbor; ties round away from zero)
        return self.toUFix64(value, self.RoundingMode.RoundHalfUp)
    } 

    /// Rounds a UInt128 value (24 decimals) to UFix64 (8 decimals), always rounding down (truncate).
    ///
    /// Use when you want to avoid overestimating user balances or payouts.
    access(all) view fun toUFix64RoundDown(_ value: UInt128): UFix64 {
        return self.toUFix64(value, self.RoundingMode.RoundDown)
    }

    /// Rounds a UInt128 value (24 decimals) to UFix64 (8 decimals), always rounding up (ceiling).
    ///
    /// Use when you want to avoid underestimating liabilities or fees.
    access(all) view fun toUFix64RoundUp(_ value: UInt128): UFix64 {
        return self.toUFix64(value, self.RoundingMode.RoundUp)
    }

    /// Raises base to the power of exponent
    ///
    /// @param base: The base number
    /// @param to: The exponent
    /// @return: base^to
    access(self) view fun pow(_ base: UInt128, to: UInt8): UInt128 {
        if to == 0 {
            return 1
        }

        var accum = base
        var exp: UInt8 = to
        var r: UInt128 = 1
        while exp != 0 {
            if exp & 1 == 1 {
                r = r * UInt128(accum)
            }
            accum = accum * accum
            exp = exp / 2
        }

        return r
    }

    init() {
        self.e24 = 1_000_000_000_000_000_000_000_000
        self.e8 = 100_000_000
        self.decimals = 24
        self.ufix64Decimals = 8
        self.scaleFactor = self.pow(10, to: self.decimals - self.ufix64Decimals)
    }
} 
