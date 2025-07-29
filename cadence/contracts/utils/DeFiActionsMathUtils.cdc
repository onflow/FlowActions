/// DFBMathUtils
///
/// This contract contains mathematical utility methods for DeFiBlocks components
/// using UInt256 for high-precision fixed-point arithmetic.
///
access(all) contract DeFiActionsMathUtils {

    /// Constant for 10^24 (used for 24-decimal fixed-point math)
    access(all) let e24: UInt256
    /// Constant for 10^8 (UFix64 precision)
    access(all) let e8: UInt256
    /// Standard decimal precision for internal calculations
    access(all) let decimals: UInt8
    /// UFix64 decimal precision for internal calculations
    access(self) let ufix64Decimals: UInt8

    /************************
    * CONVERSION UTILITIES *
    ************************/

    /// Converts a UFix64 value to UInt256 with 24 decimal precision
    ///
    /// @param value: The UFix64 value to convert
    /// @return: The UInt256 value scaled to 24 decimals
    access(all) view fun toUInt256(_ value: UFix64): UInt256 {
        let rawUInt64 = UInt64.fromBigEndianBytes(value.toBigEndianBytes())!
        let scaleFactor = self.decimals - self.ufix64Decimals
        let scaledValue: UInt256 = UInt256(rawUInt64) * self.pow(10, to: scaleFactor)

        return scaledValue
    }

    /// Converts a UInt256 value with 24 decimal precision to UFix64
    ///
    /// @param value: The UInt256 value to convert
    /// @return: The UFix64 value
    access(all) view fun toUFix64(_ value: UInt256): UFix64 {
        let scaleFactor = self.decimals - self.ufix64Decimals
        let divisor = self.pow(10, to: scaleFactor)
        let integerPart = value / self.e24
        let fractionalPart = value % self.e24 / divisor

        assert(
            integerPart <= UInt256(UFix64.max),
            message: "Scaled value ".concat(integerPart.toString()).concat(" exceeds max UFix64 value")
        )

        let scaled = UFix64(integerPart) + UFix64(fractionalPart)/UFix64(self.e8)

        // Convert to UFix64 — `scaled` is now at 1e8 base so fractional precision is preserved
        return UFix64(scaled)
    }

    /// Converts a UInt256 to a UFix64 with specified decimal precision
    ///
    /// @param value: The UInt256 value to convert
    /// @param decimals: The number of decimal places in the UInt256
    /// @return: The UFix64 value
    access(all) view fun uint256ToUFix64(_ value: UInt256, decimals: UInt8): UFix64 {
        pre {
            value / self.pow(10, to: decimals) <= UInt256(UFix64.max): "Value too large to fit in UFix64"
        }

        let divisor = self.pow(10, to: decimals)
        let integerPart = value / divisor
        let fractionalPart = value % divisor
        let fractionalUFix = self.uint256FractionalToScaledUFix64Decimals(fractionalPart, decimals: decimals)

        return UFix64(integerPart) + fractionalUFix
    }

    /***********************
    * FIXED POINT MATH   *
    ***********************/

    /// Multiplies two 24-decimal fixed-point numbers
    ///
    /// @param x: First operand (scaled by 10^24)
    /// @param y: Second operand (scaled by 10^24)
    /// @return: Product scaled by 10^24
    access(all) view fun mul(_ x: UInt256, _ y: UInt256): UInt256 {
        return (x * y) / self.e24
    }

    /// Divides two 24-decimal fixed-point numbers
    ///
    /// @param x: Dividend (scaled by 10^24)
    /// @param y: Divisor (scaled by 10^24)
    /// @return: Quotient scaled by 10^24
    access(all) view fun div(_ x: UInt256, _ y: UInt256): UInt256 {
        pre {
            y > 0: "Division by zero"
        }
        return (x * self.e24) / y
    }


    /// Rounds a UInt256 value with 24 decimal precision to a UFix64 value (8 decimals)
    ///
    /// Example: 1e24 -> 1.0, 123456000000000000000 -> 1.23456000, 123456789012345678901 -> 1.23456789
    /// Example: 123456789999999999999 -> 1.23456790
    ///
    /// @param value: The UInt256 value to convert and round
    /// @return: The UFix64 value, rounded to the nearest 8 decimals
    access(all) view fun roundToUFix64(_ value: UInt256): UFix64 {
        let decimalsFrom: UInt8 = self.decimals
        let decimalsTo: UInt8 = 8
        let scaleDown = self.pow(UInt256(10), to: decimalsFrom - decimalsTo) // 10^10
        // Step 1: reduce to 8 decimal scale safely
        let quotient = value / scaleDown
        let remainder = value % scaleDown

        var rounded = quotient
        if remainder >= (scaleDown / UInt256(2)) {
            rounded = rounded + UInt256(1)
        }

        // Step 2: Now rounded is an integer with 8 decimals *built-in*.
        // Instead of casting it directly (which may overflow),
        // we first separate whole part and decimal part.
        let wholePart = rounded / UInt256(100_000_000)        // integer part
        let decimalPart = rounded % UInt256(100_000_000)      // fractional 8 decimals
        // Step 3: Ensure final result fits into UFix64
        let asUFix64 = UFix64(wholePart) + (UFix64(decimalPart) / UFix64(100_000_000))
        return asUFix64
    }

    access(all) fun divUFix64(_ x: UFix64, _ y: UFix64): UFix64 {
        pre {
            y > 0.0: "Division by zero"
        }
        let uintX: UInt256 = self.toUInt256(x)
        let uintY: UInt256 = self.toUInt256(y)
        let uintResult = self.div(uintX, uintY)
        let result = self.roundToUFix64(uintResult)

        return result

    }

    /// Multiplies a fixed-point number by a scalar
    ///
    /// @param x: Fixed-point number (scaled by 10^24)
    /// @param y: Scalar value (not scaled)
    /// @return: Product scaled by 10^24
    access(all) view fun mulScalar(_ x: UInt256, _ y: UInt256): UInt256 {
        return x * y
    }

    /// Divides a fixed-point number by a scalar
    ///
    /// @param x: Fixed-point number (scaled by 10^24)
    /// @param y: Scalar value (not scaled)
    /// @return: Quotient scaled by 10^24
    access(all) view fun divScalar(_ x: UInt256, _ y: UInt256): UInt256 {
        pre {
            y > 0: "Division by zero"
        }
        return x / y
    }

    /*******************
    * HELPER METHODS  *
    *******************/

    /// Raises base to the power of exponent
    ///
    /// @param base: The base number
    /// @param to: The exponent
    /// @return: base^to
    access(self) view fun pow(_ base: UInt256, to: UInt8): UInt256 {
        if to == 0 {
            return 1
        }

        var r = base
        var exp: UInt8 = 1
        while exp < to {
            r = r * base
            exp = exp + 1
        }

        return r
    }

    /// Converts fractional part to UFix64 decimal representation
    access(all) view fun uint256FractionalToScaledUFix64Decimals(_ value: UInt256, decimals: UInt8): UFix64 {
        pre {
            self.getNumberOfDigits(value) <= decimals: "Fractional digits exceed the defined decimal places"
        }
        post {
            result < 1.0: "Resulting scaled fractional exceeds 1.0"
        }

        var fractional = value
        // Truncate to 8 decimal places (UFix64 max precision)
        if decimals >= 8 {
            fractional = fractional / self.pow(10, to: decimals - 8)
        }
        if fractional == 0 {
            return 0.0
        }

        // Scale the fractional part
        let fractionalMultiplier = self.ufixPow(0.1, to: decimals < 8 ? decimals : 8)
        return UFix64(fractional) * fractionalMultiplier
    }

    /// Returns the number of digits in a UInt256
    access(all) view fun getNumberOfDigits(_ value: UInt256): UInt8 {
        var tmp = value
        var digits: UInt8 = 0
        while tmp > 0 {
            tmp = tmp / 10
            digits = digits + 1
        }
        return digits
    }

    /// Raises UFix64 base to power
    access(all) view fun ufixPow(_ base: UFix64, to: UInt8): UFix64 {
        if to == 0 {
            return 1.0
        }

        var r = base
        var exp: UInt8 = 1
        while exp < to {
            r = r * base
            exp = exp + 1
        }

        return r
    }

    init() {
        self.e24 = 1_000_000_000_000_000_000_000_000
        self.e8 = 100_000_000
        self.decimals = 24
        self.ufix64Decimals = 8
    }
} 
