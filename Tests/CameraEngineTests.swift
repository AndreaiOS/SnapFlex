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
}
