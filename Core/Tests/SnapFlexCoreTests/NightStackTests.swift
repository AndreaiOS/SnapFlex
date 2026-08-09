import Testing
@testable import SnapFlexCore

@Suite struct NightStackTests {
    @Test func averagesTwoFrames() {
        var acc = NightAccumulator(byteCount: 4)
        let added1 = acc.add(frame: [0, 100, 200, 255])
        let added2 = acc.add(frame: [10, 120, 250, 255])
        #expect(added1)
        #expect(added2)
        #expect(acc.framesAdded == 2)
        #expect(acc.average() == [5, 110, 225, 255])
    }

    @Test func rejectsMismatchedLength() {
        var acc = NightAccumulator(byteCount: 4)
        let added = acc.add(frame: [1, 2])
        #expect(added == false)
        #expect(acc.framesAdded == 0)
    }

    @Test func emptyAverageIsNil() {
        #expect(NightAccumulator(byteCount: 4).average() == nil)
    }

    @Test func roundsAverage() {
        var acc = NightAccumulator(byteCount: 1)
        _ = acc.add(frame: [1])
        _ = acc.add(frame: [2])
        #expect(acc.average() == [2])   // (3 + 1) / 2 rounds to 2
    }
}
