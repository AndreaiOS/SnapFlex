// Core/Tests/SnapFlexCoreTests/ETTRTests.swift
import Testing
@testable import SnapFlexCore

@Suite struct ETTRTests {
    func histogram(_ pairs: [(Int, UInt32)], count: Int = 192) -> [UInt32] {
        var bins = [UInt32](repeating: 0, count: count)
        for (index, value) in pairs { bins[index] = value }
        return bins
    }

    @Test func clippedHistogramStepsDown() {
        let bins = histogram([(100, 900), (191, 100)])   // 10% in top bins
        #expect(ETTR.adjustment(bins: bins) == -0.3)
    }

    @Test func darkHistogramStepsUp() {
        let bins = histogram([(50, 1000)])               // headroom unused
        #expect(ETTR.adjustment(bins: bins) == 0.3)
    }

    @Test func convergedHistogramReturnsZero() {
        let bins = histogram([(185, 1000)])              // bright, not clipped
        #expect(ETTR.adjustment(bins: bins) == 0)
    }

    @Test func emptyHistogramReturnsZero() {
        #expect(ETTR.adjustment(bins: [UInt32](repeating: 0, count: 192)) == 0)
        #expect(ETTR.adjustment(bins: []) == 0)
    }
}
