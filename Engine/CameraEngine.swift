import Foundation
import Observation
import SnapFlexCore

@Observable @MainActor
final class CameraEngine {
    private let device: CameraDeviceProtocol
    private let overlayDriver: OverlayFrameDriver?

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
        didSet { overlayDriver?.settings = overlaySettings }
    }

    init(device: CameraDeviceProtocol, overlayDriver: OverlayFrameDriver? = nil) {
        self.device = device
        self.overlayDriver = overlayDriver
        device.onStatusChange = { [weak self] newStatus in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.status = newStatus }
            } else {
                Task { @MainActor in self?.status = newStatus }
            }
        }
        if let overlayDriver, let realDevice = device as? RealCameraDevice {
            overlayDriver.bind { handler in realDevice.setVideoFrameHandler(handler) }
            overlayDriver.onHistogram = { [weak self] bins in
                Task { @MainActor in self?.histogramBins = bins }
            }
        }
    }

    func start() {
        device.start()
        refreshFromDevice()
    }

    func stop() { device.stop() }

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
}
