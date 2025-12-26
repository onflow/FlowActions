import Test

import "FlowEVMBridgeUtils"
import "EVMAmountUtils"

access(all)
fun setup() {
    log("================== Setting up EVMAmountUtils test ==================")
    let err = Test.deployContract(
        name: "EVMAmountUtils",
        path: "../contracts/utils/EVMAmountUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all)
fun testSetupSucceeds() {
    log("EVMAmountUtils deployment success")
}

/* Rounding tests */

access(all) fun roundTrip(_ x: UFix64, decimals: UInt8): UInt256 {
    return FlowEVMBridgeUtils.ufix64ToUInt256(value: x, decimals: decimals)
}

access(all) fun quantum(decimals: UInt8): UInt256 {
    if decimals <= 8 { return UInt256(1) }
    return FlowEVMBridgeUtils.pow(base: 10, exponent: decimals - 8)
}

access(all) fun test_decimals_le_8_exact_roundtrip_in_and_out() {
    let decimals: UInt8 = 6
    let amt: UInt256 = UInt256(123_456_789) // 123.456789 with 6 decimals

    let uIn = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: decimals)
    let uOut = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: decimals)

    assert(roundTrip(uIn, decimals: decimals) == amt, message: "in: round-trip should equal original when decimals<=8")
    assert(roundTrip(uOut, decimals: decimals) == amt, message: "out: round-trip should equal original when decimals<=8")
}

access(all) fun test_decimals_gt_8_out_is_floor_to_quantum() {
    let decimals: UInt8 = 18
    let q = quantum(decimals: decimals)

    let amt: UInt256 = UInt256(1000) * q + UInt256(123)

    let uOut = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: decimals)
    let back = roundTrip(uOut, decimals: decimals)

    assert(back <= amt, message: "out: round-trip must be <= original (floor)")
    assert(amt - back < q, message: "out: should only drop by < quantum")
    assert(back == amt - (amt % q), message: "out: must floor to multiple of quantum")
}

access(all) fun test_decimals_gt_8_in_is_ceil_to_quantum_minimal() {
    let decimals: UInt8 = 18
    let q = quantum(decimals: decimals)

    let amt: UInt256 = UInt256(1000) * q + UInt256(123)

    let uIn = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: decimals)
    let back = roundTrip(uIn, decimals: decimals)

    assert(back >= amt, message: "in: round-trip must be >= original (ceil)")
    assert(back - amt < q, message: "in: should only increase by < quantum")
    assert(back == amt + (q - (amt % q)), message: "in: must ceil to next multiple of quantum")
}

access(all) fun test_decimals_gt_8_in_exact_if_already_multiple_of_quantum() {
    let decimals: UInt8 = 18
    let q = quantum(decimals: decimals)

    let amt: UInt256 = UInt256(1000) * q
    let uIn = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: decimals)
    let back = roundTrip(uIn, decimals: decimals)

    assert(back == amt, message: "in: if already quantum-multiple, must not change")
}

access(all) fun test_decimals_gt_8_out_exact_if_already_multiple_of_quantum() {
    let decimals: UInt8 = 18
    let q = quantum(decimals: decimals)

    let amt: UInt256 = UInt256(1000) * q
    let uOut = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: decimals)
    let back = roundTrip(uOut, decimals: decimals)

    assert(back == amt, message: "out: if already quantum-multiple, must not change")
}

access(all) fun test_zero_amount_returns_zero() {
    let amt: UInt256 = UInt256(0)

    // Test with decimals <= 8
    let uIn6 = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: 6)
    let uOut6 = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: 6)
    assert(uIn6 == 0.0, message: "in: zero amount should return 0.0 for decimals 6")
    assert(uOut6 == 0.0, message: "out: zero amount should return 0.0 for decimals 6")

    // Test with decimals > 8
    let uIn18 = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: 18)
    let uOut18 = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: 18)
    assert(uIn18 == 0.0, message: "in: zero amount should return 0.0 for decimals 18")
    assert(uOut18 == 0.0, message: "out: zero amount should return 0.0 for decimals 18")
}

access(all) fun test_decimals_eq_8_exact_roundtrip() {
    let decimals: UInt8 = 8
    let amt: UInt256 = UInt256(12345678901234) // 123456.78901234 with 8 decimals

    let uIn = EVMAmountUtils.toCadenceInWithDecimals(amt, decimals: decimals)
    let uOut = EVMAmountUtils.toCadenceOutWithDecimals(amt, decimals: decimals)

    assert(roundTrip(uIn, decimals: decimals) == amt, message: "in: round-trip should equal original when decimals=8")
    assert(roundTrip(uOut, decimals: decimals) == amt, message: "out: round-trip should equal original when decimals=8")
}
