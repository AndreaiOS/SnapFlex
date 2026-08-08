import Testing
@testable import SnapFlexCore

@Suite struct LongExposureTests {
    @Test func modeCyclesThroughAllStates() {
        var mode = LongMode.off
        var seen: [LongMode] = []
        for _ in 0..<6 { mode = mode.next; seen.append(mode) }
        #expect(seen == [.preset(seconds: 2), .preset(seconds: 5), .preset(seconds: 15),
                         .preset(seconds: 30), .bulb, .off])
    }

    @Test func presetAutoFinishesAndSaves() {
        var session = LongExposureSession(mode: .preset(seconds: 2))
        session.tick(1.9)
        #expect(session.phase == .exposing(elapsed: 1.9))
        #expect(session.progress == 0.95)
        session.tick(0.2)
        #expect(session.phase == .finished(save: true))
    }

    @Test func presetShutterTapCancelsWithoutSaving() {
        var session = LongExposureSession(mode: .preset(seconds: 15))
        session.tick(5)
        session.shutterTapped()
        #expect(session.phase == .finished(save: false))
    }

    @Test func bulbStopsAndSavesAfterOneSecond() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(3)
        #expect(session.progress == nil)
        session.shutterTapped()
        #expect(session.phase == .finished(save: true))
    }

    @Test func bulbUnderOneSecondDiscards() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(0.5)
        session.shutterTapped()
        #expect(session.phase == .finished(save: false))
    }

    @Test func bulbAutoFinishesAtCap() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(LongMode.bulbCapSeconds + 1)
        #expect(session.phase == .finished(save: true))
    }

    @Test func interruptionSavesWhenLongEnough() {
        var session = LongExposureSession(mode: .preset(seconds: 30))
        session.tick(4)
        session.interrupted()
        #expect(session.phase == .finished(save: true))
        var short = LongExposureSession(mode: .preset(seconds: 30))
        short.tick(0.3)
        short.interrupted()
        #expect(short.phase == .finished(save: false))
    }

    @Test func ticksAfterFinishAreNoOps() {
        var session = LongExposureSession(mode: .preset(seconds: 2))
        session.tick(5)
        let done = session
        session.tick(1)
        session.shutterTapped()
        #expect(session == done)
    }
}
