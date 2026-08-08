import CoreVideo
import Foundation
import Observation
import SnapFlexCore

@Observable @MainActor
final class CameraEngine {
    private let device: CameraDeviceProtocol
    private let overlayDriver: OverlayFrameDriver?
    private let realDevice: RealCameraDevice?

    private(set) var values = ManualValues(iso: nil, shutterSeconds: nil,
                                           focusPosition: nil, wbKelvin: nil, evBias: 0)
    private(set) var ranges = ParameterRanges(iso: 1...1, shutterSeconds: 1...1,
                                              evBias: 0...0, zoom: 1...1)
    private(set) var activeLens: LensKind = .wide
    private(set) var availableLenses: [LensKind] = []
    private(set) var capabilities = DeviceCapabilities(supportsProRAW: false,
                                                       supportsBayerRAW: false)
    private(set) var status: SessionStatus = .notRunning
    private(set) var lastCapture: [CaptureResource]?
    private(set) var histogramBins: [UInt32]?

    var formatSelection = FormatSelection(raw: .proRAW, heifCompanion: true)
    var bracketCount: Int?          // nil = off; 3 or 5
    var bracketStepEV: Float = 1.0
    var flashOn = false
    var overlaySettings: OverlaySettings = .allOff {
        didSet {
            overlayDriver?.settings = overlaySettings
            updateFrameTap()
        }
    }
    var longMode: LongMode = .off
    var longBlend: LongBlend = .nd

    /// Set by the app wiring (Task 5); invoked on videoQueue with each camera frame
    /// while a long-exposure session is running.
    var longFrameTap: ((CVPixelBuffer) -> Void)?
    private(set) var longExposureRunning = false
    private var frameTapActive = false
    /// The (overlay, long) configuration baked into the currently installed handler.
    private var installedTap: (overlay: Bool, long: Bool) = (false, false)

    private var didLockAE = false

    init(device: CameraDeviceProtocol, overlayDriver: OverlayFrameDriver? = nil) {
        self.device = device
        self.overlayDriver = overlayDriver
        self.realDevice = device as? RealCameraDevice
        device.onStatusChange = { [weak self] newStatus in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.status = newStatus }
            } else {
                Task { @MainActor in self?.status = newStatus }
            }
        }
        device.onControlEvent = { [weak self] event in
            Task { @MainActor in self?.handleControlEvent(event) }
        }
        if let overlayDriver {
            overlayDriver.onHistogram = { [weak self] bins in
                Task { @MainActor in self?.histogramBins = bins }
            }
        }
        updateFrameTap()
    }

    func start() {
        device.start()
        refreshFromDevice()
        if formatSelection.raw == .proRAW && !capabilities.supportsProRAW {
            formatSelection.raw = capabilities.supportsBayerRAW ? .bayer : .off
        }
    }

    func stop() { device.stop() }

    private func handleControlEvent(_ event: CameraControlEvent) {
        guard !longExposureRunning else { return }
        switch event {
        case .iso(let value): setISO(value)
        case .shutterSeconds(let seconds): setShutter(seconds)
        case .evBias(let bias): setEVBias(bias)
        }
    }

    private func refreshFromDevice() {
        ranges = device.ranges
        activeLens = device.activeLens
        availableLenses = device.availableLenses
        capabilities = device.capabilities
    }

    // MARK: - Exposure

    func setISO(_ iso: Float?) {
        values.iso = iso
        applyExposure()
    }

    func setShutter(_ seconds: Double?) {
        values.shutterSeconds = seconds
        applyExposure()
    }

    func setEVBias(_ bias: Float) {
        values.evBias = bias
        applyExposure()
    }

    /// Custom exposure requires both ISO and shutter; fill the missing one from range midpoint.
    private func applyExposure() {
        values = clamped(values, to: ranges)
        switch (values.iso, values.shutterSeconds) {
        case (nil, nil):
            device.setExposure(iso: nil, shutterSeconds: nil, bias: values.evBias)
        case (let iso?, nil):
            device.setExposure(iso: iso, shutterSeconds: midShutter(), bias: values.evBias)
        case (nil, let shutter?):
            device.setExposure(iso: midISO(), shutterSeconds: shutter, bias: values.evBias)
        case (let iso?, let shutter?):
            device.setExposure(iso: iso, shutterSeconds: shutter, bias: values.evBias)
        }
    }

    private func midShutter() -> Double {
        (ranges.shutterSeconds.lowerBound * ranges.shutterSeconds.upperBound).squareRoot()
    }

    private func midISO() -> Float {
        (ranges.iso.lowerBound * ranges.iso.upperBound).squareRoot()
    }

    // MARK: - Focus / WB / Lens / Zoom

    func setFocus(_ position: Float?) {
        values.focusPosition = position
        if let position { device.lockFocus(position: min(max(position, 0), 1)) }
        else { device.setAutoFocus() }
    }

    func setWhiteBalance(kelvin: Int?) {
        values.wbKelvin = kelvin
        values = clamped(values, to: ranges)
        device.setWhiteBalance(kelvin: values.wbKelvin)
    }

    func selectLens(_ lens: LensKind) {
        device.switchTo(lens)
        refreshFromDevice()
        values = clamped(values, to: ranges)
        // Re-apply manual values so the new lens matches published state.
        if values.iso != nil || values.shutterSeconds != nil { applyExposure() }
        if let focus = values.focusPosition { device.lockFocus(position: focus) }
        if values.wbKelvin != nil { device.setWhiteBalance(kelvin: values.wbKelvin) }
    }

    func setZoom(_ factor: Double) {
        device.setZoom(min(max(factor, ranges.zoom.lowerBound), ranges.zoom.upperBound))
    }

    // MARK: - Capture

    func capture(onResult: @escaping ([CaptureResource]) -> Void) {
        let bracketing = bracketCount.map { count in
            BracketingPlan.make(
                count: count, stepEV: bracketStepEV,
                base: exposureBase(), ranges: ranges)
        }
        let recipe = CaptureRecipe.make(selection: formatSelection,
                                        capabilities: capabilities,
                                        bracketing: bracketing)
        device.capture(recipe: recipe, flashOn: flashOn) { [weak self] resources in
            Task { @MainActor in
                self?.lastCapture = resources
                onResult(resources)
            }
        }
    }

    private func exposureBase() -> ExposureBase {
        if let iso = values.iso, let shutter = values.shutterSeconds {
            return .manual(iso: iso, shutterSeconds: shutter)
        }
        return .auto
    }

    // MARK: - Long Exposure

    func prepareLongExposure() {
        if values.iso == nil || values.shutterSeconds == nil {
            device.lockAutoExposure()
            didLockAE = true
        }
    }

    func endLongExposure() {
        if didLockAE {
            device.unlockAutoExposure()
            didLockAE = false
        }
        if values.iso != nil || values.shutterSeconds != nil {
            applyExposure()   // restore custom exposure the lock overrode
        }
    }

    /// Begin routing camera frames to `tap` (in addition to the overlay driver, if active).
    func beginLongFrames(tap: @escaping (CVPixelBuffer) -> Void) {
        longFrameTap = tap
        longExposureRunning = true
        updateFrameTap()
    }

    func endLongFrames() {
        longExposureRunning = false
        longFrameTap = nil
        updateFrameTap()
    }

    // MARK: - Frame fan-out

    /// Reinstalls the device's video frame handler whenever the desired fan-out
    /// configuration (overlay enabled / long-exposure running) changes, so the
    /// closure installed on the device always matches current engine state.
    /// Frames arrive on videoQueue, so the closure captures its targets directly
    /// at install time rather than reading mutable engine state from the queue.
    private func updateFrameTap() {
        let overlayEnabled = overlaySettings.anyEnabled
        let longRunning = longExposureRunning
        let desired = overlayEnabled || longRunning
        guard (overlayEnabled, longRunning) != installedTap else { return }
        frameTapActive = desired
        installedTap = (overlayEnabled, longRunning)
        guard let realDevice else { return }
        guard desired else {
            realDevice.setVideoFrameHandler(nil)
            return
        }
        let overlayDriver = overlayEnabled ? self.overlayDriver : nil
        let tap = longRunning ? self.longFrameTap : nil
        realDevice.setVideoFrameHandler { pixelBuffer in
            overlayDriver?.ingest(pixelBuffer)
            tap?(pixelBuffer)
        }
    }
}
