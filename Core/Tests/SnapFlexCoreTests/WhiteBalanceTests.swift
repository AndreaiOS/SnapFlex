// Core/Tests/SnapFlexCoreTests/WhiteBalanceTests.swift
import Testing
@testable import SnapFlexCore

@Suite struct WhiteBalanceTests {
    @Test func gainsClampIntoDeviceLimits() {
        let gains = WBGains(red: 0.5, green: 1.0, blue: 9.7)
        let clamped = gains.clamped(maxGain: 4.0)
        #expect(clamped == WBGains(red: 1.0, green: 1.0, blue: 4.0))
    }

    @Test func inRangeGainsUntouched() {
        let gains = WBGains(red: 2.1, green: 1.0, blue: 1.8)
        #expect(gains.clamped(maxGain: 4.0) == gains)
    }
}
