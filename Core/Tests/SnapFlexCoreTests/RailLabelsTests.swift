import Testing
@testable import SnapFlexCore

@Suite struct RailLabelsTests {
    @Test func timerLabels() {
        #expect(RailLabels.timer(0) == "—")
        #expect(RailLabels.timer(3) == "3s")
        #expect(RailLabels.timer(10) == "10s")
    }
    @Test func bracketLabels() {
        #expect(RailLabels.bracket(nil) == "—")
        #expect(RailLabels.bracket(3) == "BKT 3")
    }
    @Test func longLabels() {
        #expect(RailLabels.long(.off) == "—")
        #expect(RailLabels.long(.preset(seconds: 15)) == "15s")
        #expect(RailLabels.long(.bulb) == "BULB")
    }
    @Test func pipelineSummary() {
        #expect(RailLabels.pipeline(raw: .bayer, heifCompanion: true, processing: .standard) == "RAW+HEIF · STD")
        #expect(RailLabels.pipeline(raw: .off, heifCompanion: true, processing: .max) == "HEIF · MAX")
        #expect(RailLabels.pipeline(raw: .proRAW, heifCompanion: false, processing: .zero) == "ProRAW · 0AI")
    }
}
