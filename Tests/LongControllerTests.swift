import Testing
import Foundation
import SnapFlexCore
@testable import SnapFlex

@MainActor @Suite struct LongControllerTests {
    @Test func presetSessionAutoFinishes() async throws {
        let controller = try #require(LongExposureController())
        var result: Data?? = nil
        controller.start(mode: .preset(seconds: 2), blend: .nd) { result = .some($0) }
        #expect(controller.isExposing)
        try await Task.sleep(for: .seconds(2.6))
        #expect(result != nil)          // finished
        #expect(result! == nil)         // no frames accumulated → discard
        #expect(!controller.isExposing)
    }

    @Test func shutterTapCancelsPreset() async throws {
        let controller = try #require(LongExposureController())
        var result: Data?? = nil
        controller.start(mode: .preset(seconds: 30), blend: .nd) { result = .some($0) }
        try await Task.sleep(for: .milliseconds(300))
        controller.shutterTapped()
        try await Task.sleep(for: .milliseconds(300))
        #expect(result != nil && result! == nil)
        #expect(!controller.isExposing)
    }

    @Test func interruptedFinalizesSession() async throws {
        let controller = try #require(LongExposureController())
        var result: Data?? = nil
        controller.start(mode: .preset(seconds: 30), blend: .nd) { result = .some($0) }
        try await Task.sleep(for: .milliseconds(300))
        controller.interrupted()
        try await Task.sleep(for: .milliseconds(300))
        #expect(result != nil && result! == nil)   // <1s → discard, but finalized exactly once
        #expect(!controller.isExposing)
    }
}
