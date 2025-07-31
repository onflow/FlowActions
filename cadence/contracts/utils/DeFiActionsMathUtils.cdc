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

    access(all)
    enum RoundingMode: UInt8 {
        access(all)
        case RoundDown

        access(all)
        case RoundUp

        access(all)
        case RoundHalfUp // normal rounding

        access(all)
        case RoundEven
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
        let scaledValue: UInt128 = UInt128(rawUInt64) * self.pow(10, to: self.scaleFactor)

        return scaledValue
    }

    /// Converts a UInt128 value with 24 decimal precision to UFix64
    ///
    /// @param value: The UInt128 value to convert
    /// @return: The UFix64 value
    access(all) view fun toUFix64(_ value: UInt128, _ roundingMode: RoundingMode): UFix64 {
        let divisor = self.pow(10, to: self.scaleFactor)

        var integerPart = value / self.e24
        var fractionalPart = value % self.e24 / divisor
        let remainder = (value % self.e24) % divisor

        if self.shouldRoundUp(roundingMode, fractionalPart, remainder, divisor) {
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

    // Helper to determine rounding condition
    access(self) view fun shouldRoundUp(
        _ roundingMode: RoundingMode, 
        _ fractionalPart: UInt128, 
        _ remainder: UInt128, 
        _ divisor: UInt128
    ): Bool {
        switch roundingMode {
        case self.RoundingMode.RoundUp:
            return remainder > UInt128(0)

        case self.RoundingMode.RoundHalfUp:
            return remainder >= divisor / UInt128(2)

        case self.RoundingMode.RoundEven:
            return remainder > divisor / UInt128(2) ||
            (remainder == divisor / UInt128(2) && fractionalPart % UInt128(2) != UInt128(0))
        }
        return false
    }

    // Helper to handle overflow assertion
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

    access(all) view fun divWithRounding(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundHalfUp)
    }

    access(all) view fun divWithRoundingUp(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundUp)
    }

    access(all) view fun divWithRoundingDown(_ x: UFix64, _ y: UFix64): UFix64 {
        return self.divUFix64(x, y, self.RoundingMode.RoundDown)
    }
    /*******************
    * HELPER METHODS  *
    *******************/

    /// Rounds a UInt128 value with 24 decimal precision to a UFix64 value (8 decimals)
    ///
    /// Example: 1e24 -> 1.0, 123456000000000000000 -> 1.23456000, 123456789012345678901 -> 1.23456789
    /// Example: 123456789999999999999 -> 1.23456790
    ///
    /// @param value: The UInt128 value to convert and round
    /// @return: The UFix64 value, rounded to the nearest 8 decimals
    access(all) view fun toUFix64Round(_ value: UInt128): UFix64 {
        return self.toUFix64(value, self.RoundingMode.RoundHalfUp)
    } 

    access(all) view fun toUFix64RoundDown(_ value: UInt128): UFix64 {
        return self.toUFix64(value, self.RoundingMode.RoundDown)
    }

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
        self.scaleFactor = self.decimals - self.ufix64Decimals
    }
} 
