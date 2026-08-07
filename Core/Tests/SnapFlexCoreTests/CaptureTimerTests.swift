import Testing
@testable import SnapFlexCore

@Suite struct CaptureTimerTests {
    @Test func zeroDurationFiresImmediately() {
        var timer = CaptureTimer(duration: 0)
        timer.start()
        #expect(timer.state == .fired)
    }

    @Test func countsDownThenFires() {
        var timer = CaptureTimer(duration: 3)
        timer.start()
        #expect(timer.state == .counting(remaining: 3))
        timer.tick()
        timer.tick()
        #expect(timer.state == .counting(remaining: 1))
        timer.tick()
        #expect(timer.state == .fired)
    }

    @Test func cancelResetsToIdle() {
        var timer = CaptureTimer(duration: 10)
        timer.start()
        timer.tick()
        timer.cancel()
        #expect(timer.state == .idle)
    }

    @Test func tickWhileIdleDoesNothing() {
        var timer = CaptureTimer(duration: 3)
        timer.tick()
        #expect(timer.state == .idle)
    }
}
