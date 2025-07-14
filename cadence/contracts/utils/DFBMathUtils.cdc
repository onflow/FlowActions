/// DFBMathUtils
///
/// This contract contains mathematical utility methods for DeFiBlocks components
/// using UInt256 for high-precision fixed-point arithmetic.
///
access(all) contract DFBMathUtils {

    /// Constant for 10^18 (used for 18-decimal fixed-point math)
    access(all) let e18: UInt256
    /// Constant for 10^8 (UFix64 precision)
    access(all) let e8: UInt256
    /// Standard decimal precision for internal calculations
    access(all) let decimals: UInt8

    /************************
     * CONVERSION UTILITIES *
     ************************/

    /// Converts a UFix64 value to UInt256 with 18 decimal precision
    ///
    /// @param value: The UFix64 value to convert
    /// @return: The UInt256 value scaled to 18 decimals
    access(all) view fun toUInt256(_ value: UFix64): UInt256 {
        return self.ufix64ToUInt256(value, decimals: 18)
    }

    /// Converts a UInt256 value with 18 decimal precision to UFix64
    ///
    /// @param value: The UInt256 value to convert
    /// @return: The UFix64 value
    access(all) view fun toUFix64(_ value: UInt256): UFix64 {
        return self.uint256ToUFix64(value, decimals: 18)
    }

    /// Converts a UFix64 to a UInt256 with specified decimal precision
    ///
    /// @param value: The UFix64 value to convert
    /// @param decimals: The number of decimal places for the UInt256
    /// @return: The UInt256 value
    access(all) view fun ufix64ToUInt256(_ value: UFix64, decimals: UInt8): UInt256 {
        let scaledValue = value.toBigEndianBytes()
        let integerPart = UInt256(UInt64.fromBigEndianBytes(scaledValue)!) / self.e8
        
        // Extract fractional part
        let fractionalBytes = value.toBigEndianBytes()
        let fractionalUInt64 = UInt64.fromBigEndianBytes(fractionalBytes)! % UInt64(self.e8)
        let fractionalPart = UInt256(fractionalUInt64)
        
        // Scale to target decimals
        let multiplier = self.pow(10, to: decimals)
        let scaledInteger = integerPart * multiplier
        let scaledFractional = (fractionalPart * multiplier) / self.e8
        
        return scaledInteger + scaledFractional
    }

    /// Converts a UInt256 to a UFix64 with specified decimal precision
    ///
    /// @param value: The UInt256 value to convert
    /// @param decimals: The number of decimal places in the UInt256
    /// @return: The UFix64 value
    access(all) view fun uint256ToUFix64(_ value: UInt256, decimals: UInt8): UFix64 {
        pre {
            value / self.pow(10, to: decimals) <= UInt256(UFix64.max / 1.0): "Value too large to fit in UFix64"
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

    /// Multiplies two 18-decimal fixed-point numbers
    ///
    /// @param x: First operand (scaled by 10^18)
    /// @param y: Second operand (scaled by 10^18)
    /// @return: Product scaled by 10^18
    access(all) view fun mul(_ x: UInt256, _ y: UInt256): UInt256 {
        return (x * y) / self.e18
    }

    /// Divides two 18-decimal fixed-point numbers
    ///
    /// @param x: Dividend (scaled by 10^18)
    /// @param y: Divisor (scaled by 10^18)
    /// @return: Quotient scaled by 10^18
    access(all) view fun div(_ x: UInt256, _ y: UInt256): UInt256 {
        pre {
            y > 0: "Division by zero"
        }
        return (x * self.e18) / y
    }

    /// Multiplies a fixed-point number by a scalar
    ///
    /// @param x: Fixed-point number (scaled by 10^18)
    /// @param y: Scalar value (not scaled)
    /// @return: Product scaled by 10^18
    access(all) view fun mulScalar(_ x: UInt256, _ y: UInt256): UInt256 {
        return x * y
    }

    /// Divides a fixed-point number by a scalar
    ///
    /// @param x: Fixed-point number (scaled by 10^18)
    /// @param y: Scalar value (not scaled)
    /// @return: Quotient scaled by 10^18
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
    access(all) view fun pow(_ base: UInt256, to: UInt8): UInt256 {
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
        self.e18 = 1_000_000_000_000_000_000
        self.e8 = 100_000_000
        self.decimals = 18
    }
} 