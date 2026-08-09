import Foundation
import Testing
import SnapFlexCore
@testable import SnapFlex

@MainActor @Suite struct CameraEngineTests {
    func makeEngine() -> (CameraEngine, FakeCameraDevice) {
        let device = FakeCameraDevice()
        let engine = CameraEngine(device: device)
        engine.start()
        return (engine, device)
    }

    @Test func controlEventsUpdateEngineState() async throws {
        let (engine, device) = makeEngine()
        device.onControlEvent?(.iso(400))
        device.onControlEvent?(.shutterSeconds(1.0 / 60))
        device.onControlEvent?(.evBias(1.5))
        try await Task.sleep(for: .milliseconds(100))   // events hop through Task { @MainActor }
        #expect(engine.values.iso == 400)
        #expect(engine.values.shutterSeconds == 1.0 / 60)
        #expect(engine.values.evBias == 1.5)
    }

    @Test func startPublishesDeviceState() {
        let (engine, device) = makeEngine()
        #expect(engine.status == .running)
        #expect(engine.ranges == device.rangesByLens[.wide]!)
        #expect(engine.availableLenses == [.ultraWide, .wide, .telephoto])
    }

    @Test func settingISOAloneSuppliesMidRangeShutter() {
        let (engine, device) = makeEngine()
        engine.setISO(400)
        let applied = device.appliedExposures.last!
        #expect(applied.iso == 400)
        #expect(applied.shutter != nil)   // engine filled in a concrete shutter
        #expect(engine.values.iso == 400)
    }

    @Test func lensSwitchClampsManualValuesWithoutReset() {
        let (engine, device) = makeEngine()
        engine.setISO(3000)
        engine.setShutter(1.0)
        engine.selectLens(.ultraWide)
        #expect(engine.values.iso == 2016)          // clamped, still manual
        #expect(engine.values.shutterSeconds == 0.5)
        #expect(engine.ranges == device.rangesByLens[.ultraWide]!)
        // clamped values re-applied to the device
        let applied = device.appliedExposures.last!
        #expect(applied.iso == 2016)
    }

    @Test func clearingISOAndShutterReturnsToAuto() {
        let (engine, device) = makeEngine()
        engine.setISO(400)
        engine.setShutter(1.0/60)
        engine.setISO(nil)
        engine.setShutter(nil)
        let applied = device.appliedExposures.last!
        #expect(applied.iso == nil && applied.shutter == nil)
        #expect(engine.values.iso == nil)
    }

    @Test func captureBuildsRecipeFromSelection() {
        let (engine, device) = makeEngine()
        engine.formatSelection = FormatSelection(raw: .proRAW, heifCompanion: true)
        engine.capture { _ in }
        #expect(device.capturedRecipes.last ==
                CaptureRecipe(raw: .proRAW, includeProcessed: true, bracketing: nil))
    }

    @Test func captureCarriesProcessingLevel() {
        let (engine, device) = makeEngine()
        engine.formatSelection = FormatSelection(raw: .off, heifCompanion: false)
        engine.processingLevel = .max
        engine.capture { _ in }
        #expect(device.capturedRecipes.last?.processing == .max)
    }

    @Test func captureWithBracketingUsesManualBaseWhenManual() {
        let (engine, device) = makeEngine()
        engine.formatSelection = FormatSelection(raw: .off, heifCompanion: false)
        engine.setISO(100)
        engine.setShutter(1.0/120)
        engine.bracketCount = 3
        engine.bracketStepEV = 1.0
        engine.capture { _ in }
        guard case .manual(let exposures)? = device.capturedRecipes.last?.bracketing else {
            Issue.record("expected manual bracketing"); return
        }
        #expect(exposures.count == 3)
        #expect(exposures[1].shutterSeconds == 1.0/120)
    }

    @Test func overlaySettingsPublishWithoutDriver() {
        let (engine, _) = makeEngine()
        var settings = OverlaySettings.allOff
        settings.histogramEnabled = true
        engine.overlaySettings = settings
        #expect(engine.overlaySettings.histogramEnabled)
        #expect(engine.histogramBins == nil)
    }

    @Test func prepareLongLocksAEOnlyWhenAuto() {
        let (engine, device) = makeEngine()
        engine.prepareLongExposure()
        #expect(device.lockCalls == 1)
        engine.endLongExposure()
        #expect(device.unlockCalls == 1)
    }

    @Test func prepareLongKeepsManualExposure() {
        let (engine, device) = makeEngine()
        engine.setISO(100)
        engine.setShutter(1.0 / 60)
        engine.prepareLongExposure()
        #expect(device.lockCalls == 0)
        engine.endLongExposure()
        #expect(device.unlockCalls == 0)
    }

    @Test func endLongReappliesPartialManualExposure() {
        let (engine, device) = makeEngine()
        engine.setISO(400)                    // partial manual: shutter still auto
        engine.prepareLongExposure()
        #expect(device.lockCalls == 1)        // OR condition: partial manual still locks AE
        engine.endLongExposure()
        #expect(device.unlockCalls == 1)
        let applied = device.appliedExposures.last!
        #expect(applied.iso == 400)           // custom exposure re-applied after unlock
    }

    @Test func controlEventsIgnoredDuringLongExposure() async throws {
        let (engine, device) = makeEngine()
        engine.beginLongFrames { _ in }
        device.onControlEvent?(.iso(800))
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.values.iso == nil)
        engine.endLongFrames()
    }

    // MARK: - Night Stack

    /// Solid-color RGBA8 (premultipliedLast), alpha forced opaque since HEIF encoding
    /// discards alpha (verified in NightStackerTests) — a non-opaque alpha would make the
    /// per-channel tolerance check below meaningless for that channel.
    private static func solidRGBA(width: Int, height: Int, value: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = value
            bytes[i + 1] = value
            bytes[i + 2] = value
            bytes[i + 3] = 255
        }
        return bytes
    }

    @Test func captureNightStackAveragesFramesAndRestoresAE() async throws {
        let (engine, device) = makeEngine()
        let width = 2, height = 2
        // Alternating 64/192 frames (4 of each across 8 frames) average to exactly 128 —
        // unlike identical stubbed frames, this distinguishes real averaging from a bug
        // that just passes through the last captured frame (which would read back ~192).
        let low = Self.solidRGBA(width: width, height: height, value: 64)
        let high = Self.solidRGBA(width: width, height: height, value: 192)
        let lowEncoded = try #require(NightStacker.encodeHEIF(rgba: low, width: width, height: height))
        let highEncoded = try #require(NightStacker.encodeHEIF(rgba: high, width: width, height: height))
        device.stubbedCaptureDataSequence = [lowEncoded, highEncoded]
        engine.formatSelection = FormatSelection(raw: .proRAW, heifCompanion: true)
        engine.processingLevel = .max

        var progressCalls: [(Int, Int)] = []
        var completed = false
        var result: Data?
        engine.captureNightStack(onProgress: { progressCalls.append(($0, $1)) }) { data in
            result = data
            completed = true
        }
        try await Task.sleep(for: .milliseconds(500))

        #expect(completed)
        let data = try #require(result)
        let decoded = try #require(NightStacker.decodeRGBA8(data))
        #expect(decoded.width == width)
        #expect(decoded.height == height)
        for (i, byte) in decoded.bytes.enumerated() {
            let expected = i % 4 == 3 ? 255 : 128   // alpha channel stays opaque
            #expect(abs(Int(byte) - expected) <= 3)
        }
        #expect(progressCalls.map(\.0) == Array(1...NightStack.frameCount))
        #expect(progressCalls.allSatisfy { $0.1 == NightStack.frameCount })
        #expect(device.capturedRecipes.count == NightStack.frameCount)
        #expect(device.capturedRecipes.allSatisfy { $0.raw == RAWKind.none && $0.processing == .zero })
        // Forced recipe must not mutate published UI state.
        #expect(engine.formatSelection == FormatSelection(raw: .proRAW, heifCompanion: true))
        #expect(engine.processingLevel == .max)
        // AE was locked (device starts fully auto) then restored.
        #expect(device.lockCalls == 1)
        #expect(device.unlockCalls == 1)
    }

    @Test func captureNightStackAbortsOnEmptyResourcesMidStack() async throws {
        let (engine, device) = makeEngine()
        let rgba = Self.solidRGBA(width: 2, height: 2, value: 64)
        let encoded = try #require(NightStacker.encodeHEIF(rgba: rgba, width: 2, height: 2))
        device.stubbedCaptureData = encoded
        device.failCaptureAtIndex = 3

        var completed = false
        var result: Data?
        engine.captureNightStack(onProgress: { _, _ in }) { data in
            result = data
            completed = true
        }
        try await Task.sleep(for: .milliseconds(500))

        #expect(completed)
        #expect(result == nil)
        #expect(device.unlockCalls == 1)   // AE still restored on abort
        #expect(device.capturedRecipes.count == 4)   // chain actually stops at the failure
    }

    @Test func secondCaptureNightStackWhileRunningRejectsWithoutDisturbingFirst() async throws {
        let (engine, device) = makeEngine()
        let rgba = Self.solidRGBA(width: 2, height: 2, value: 128)
        let encoded = try #require(NightStacker.encodeHEIF(rgba: rgba, width: 2, height: 2))
        device.stubbedCaptureData = encoded

        var firstCompleted = false
        var firstResult: Data?
        engine.captureNightStack(onProgress: { _, _ in }) { data in
            firstResult = data
            firstCompleted = true
        }

        var secondCompleted = false
        var secondResult: Data?
        engine.captureNightStack(onProgress: { _, _ in }) { data in
            secondResult = data
            secondCompleted = true
        }

        // The second call is rejected synchronously, before touching AE, and without
        // disturbing the first stack's in-flight state.
        #expect(secondCompleted)
        #expect(secondResult == nil)
        #expect(device.lockCalls == 1)

        try await Task.sleep(for: .milliseconds(500))

        #expect(firstCompleted)
        #expect(firstResult != nil)
        #expect(device.capturedRecipes.count == NightStack.frameCount)   // exactly 8, not interleaved
        #expect(device.unlockCalls == 1)
    }

    @Test func prepareLongExposureNoOpsWhileNightStackRunning() async throws {
        let (engine, device) = makeEngine()
        let rgba = Self.solidRGBA(width: 2, height: 2, value: 128)
        let encoded = try #require(NightStacker.encodeHEIF(rgba: rgba, width: 2, height: 2))
        device.stubbedCaptureData = encoded

        var completed = false
        engine.captureNightStack(onProgress: { _, _ in }) { _ in completed = true }
        #expect(device.lockCalls == 1)   // the night stack's own lock

        engine.prepareLongExposure()
        #expect(device.lockCalls == 1)   // no re-lock while the stack owns AE

        try await Task.sleep(for: .milliseconds(500))
        #expect(completed)
    }
}
