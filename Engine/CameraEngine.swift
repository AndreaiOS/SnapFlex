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
    var processingLevel: ProcessingLevel = .standard
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
    var nightEnabled = false

    /// Set by the app wiring (Task 5); invoked on videoQueue with each camera frame
    /// while a long-exposure session is running.
    var longFrameTap: ((CVPixelBuffer) -> Void)?
    private(set) var longExposureRunning = false
    private(set) var nightStackRunning = false
    private var frameTapActive = false
    /// The (overlay, long) configuration baked into the currently installed handler.
    private var installedTap: (overlay: Bool, long: Bool) = (false, false)

    private var didLockAE = false

    init(device: CameraDeviceProtocol, overlayDriver: OverlayFrameDriver? = nil) {
        self.device = device
        self.overlayDriver = overlayDriver
        self.realDevice = device as? RealCameraDevice
        device.onStatusChange = { [weak self] newStatus in
            let apply: @MainActor () -> Void = {
                self?.status = newStatus
                // Ranges/capabilities are only trustworthy once the session is
                // configured; start()/switchTo() no longer block for them.
                if newStatus == .running { self?.syncAfterDeviceChange() }
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated { apply() }
            } else {
                Task { @MainActor in apply() }
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
        syncAfterDeviceChange()
    }

    /// Re-reads device state and downgrades an unsupported format choice.
    /// Called optimistically at start and again on every `.running` callback.
    private func syncAfterDeviceChange() {
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
                                        bracketing: bracketing,
                                        processing: processingLevel)
        deviceCapture(recipe: recipe, flashOn: flashOn) { [weak self] resources in
            if resources.isEmpty {
                Log.capture.error("capture returned no resources")
            } else {
                Log.capture.info("capture delivered \(resources.count) resource(s)")
            }
            self?.lastCapture = resources
            onResult(resources)
        }
    }

    /// Sends `recipe` straight to the device, bypassing published UI state (formatSelection,
    /// processingLevel, bracketCount) entirely — used by `capture(onResult:)` and by
    /// `captureNightStack`, which forces its own recipe without touching those published
    /// values. Does not update `lastCapture`; callers that want that publish it themselves.
    private func deviceCapture(recipe: CaptureRecipe, flashOn: Bool,
                               onResult: @escaping ([CaptureResource]) -> Void) {
        device.capture(recipe: recipe, flashOn: flashOn) { resources in
            Task { @MainActor in onResult(resources) }
        }
    }

    private func exposureBase() -> ExposureBase {
        if let iso = values.iso, let shutter = values.shutterSeconds {
            return .manual(iso: iso, shutterSeconds: shutter)
        }
        return .auto
    }

    // MARK: - Long Exposure

    /// No-ops while a night stack is in flight — LONG must not start mid-stack (it would
    /// re-lock AE over the stack's lock and, on stack completion, `restoreAEAfterLock`
    /// would unlock AE out from under the still-running LONG session and clear `didLockAE`
    /// so LONG's own `endLongExposure` later no-ops).
    func prepareLongExposure() {
        guard !nightStackRunning else { return }
        lockAEIfAuto()
    }

    /// No-ops while a night stack is in flight — mirrors `prepareLongExposure`'s guard so a
    /// LONG session torn down mid-stack can't unlock AE out from under the stack's remaining
    /// frames; the stack's own `finishNightStack` is responsible for restoring AE.
    func endLongExposure() {
        guard !nightStackRunning else { return }
        restoreAEAfterLock()
    }

    /// Shared by `prepareLongExposure` and `captureNightStack`: locks AE when either ISO or
    /// shutter is auto (i.e. the session isn't fully manual), remembering to unlock it later.
    private func lockAEIfAuto() {
        if values.iso == nil || values.shutterSeconds == nil {
            device.lockAutoExposure()
            didLockAE = true
        }
    }

    /// Shared by `endLongExposure` and `captureNightStack`: undoes `lockAEIfAuto` and
    /// re-applies any manual exposure the lock overrode.
    private func restoreAEAfterLock() {
        if didLockAE {
            device.unlockAutoExposure()
            didLockAE = false
        }
        if values.iso != nil || values.shutterSeconds != nil {
            applyExposure()   // restore custom exposure the lock overrode
        }
    }

    // MARK: - Night Stack

    /// Captures `NightStack.frameCount` frames sequentially with a forced NIGHT recipe
    /// (no RAW, `.zero` processing) and averages them into a single HEIF. MainActor entry;
    /// does not mutate `formatSelection`/`processingLevel`. `onProgress` fires after each
    /// frame is captured; `completion` fires once with the stacked HEIF, or nil on any
    /// capture/decode failure or dimension mismatch (AE is still restored in that case).
    /// Rejects (`completion(nil)`, no AE touch) if LONG is running or a stack is already
    /// in flight — `nightStackRunning` holds exclusivity for the whole multi-second stack,
    /// not just at entry, so a second call can't interleave captures or unlock AE under
    /// the first.
    func captureNightStack(onProgress: @escaping (Int, Int) -> Void,
                           completion: @escaping (Data?) -> Void) {
        guard !longExposureRunning else { completion(nil); return }
        guard !nightStackRunning else {
            Log.night.error("night stack rejected: already running")
            completion(nil)
            return
        }
        nightStackRunning = true
        Log.night.info("night stack started (\(NightStack.frameCount) frames)")
        lockAEIfAuto()
        let recipe = CaptureRecipe(raw: .none, includeProcessed: true,
                                   bracketing: nil, processing: .zero)
        captureNightFrame(index: 0, recipe: recipe, session: NightStackSession(),
                          onProgress: onProgress, completion: completion)
    }

    private func captureNightFrame(index: Int, recipe: CaptureRecipe, session: NightStackSession,
                                   onProgress: @escaping (Int, Int) -> Void,
                                   completion: @escaping (Data?) -> Void) {
        deviceCapture(recipe: recipe, flashOn: false) { [weak self] resources in
            guard let self else { return }
            guard let data = resources.first(where: { $0.kind == .processedHEIF })?.data else {
                self.finishNightStack(nil, completion: completion)
                return
            }
            onProgress(index + 1, NightStack.frameCount)
            self.addNightFrame(data, index: index, recipe: recipe, session: session,
                               onProgress: onProgress, completion: completion)
        }
    }

    /// Decode + accumulate run off the main actor (Task.detached) so an ~48MB HEIF decode
    /// never hitches the preview; only the small state hop back to MainActor touches engine
    /// state. `session` is safe to hand to the detached task because captures are strictly
    /// sequential — see `NightStackSession`.
    private func addNightFrame(_ data: Data, index: Int, recipe: CaptureRecipe,
                               session: NightStackSession,
                               onProgress: @escaping (Int, Int) -> Void,
                               completion: @escaping (Data?) -> Void) {
        let isLastFrame = index + 1 == NightStack.frameCount
        Task.detached {
            let added = session.decodeAndAdd(data)
            let output = (added && isLastFrame) ? session.encodedHEIF() : nil
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard added else {
                    self.finishNightStack(nil, completion: completion)
                    return
                }
                if isLastFrame {
                    self.finishNightStack(output, completion: completion)
                } else {
                    self.captureNightFrame(index: index + 1, recipe: recipe, session: session,
                                          onProgress: onProgress, completion: completion)
                }
            }
        }
    }

    private func finishNightStack(_ data: Data?, completion: @escaping (Data?) -> Void) {
        restoreAEAfterLock()
        nightStackRunning = false
        completion(data)
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

/// Decodes and accumulates NIGHT-stack frames off the main actor. `CameraEngine` hands each
/// instance to `Task.detached` once per frame, but never touches two frames concurrently: a
/// frame's capture is only kicked off after the previous frame's `decodeAndAdd` returned, so
/// this class is never accessed from two tasks at once despite carrying no internal lock.
/// `@unchecked Sendable` documents that sequential-only-access invariant rather than enforcing
/// it structurally.
private final class NightStackSession: @unchecked Sendable {
    private var accumulator: NightAccumulator?
    private var width = 0
    private var height = 0

    /// Decodes `data` and adds it to the accumulator, sizing the accumulator from the first
    /// frame. Returns false on decode failure, a dimension mismatch against the first frame,
    /// or NightAccumulator rejecting the frame (byte-count mismatch).
    func decodeAndAdd(_ data: Data) -> Bool {
        guard let decoded = NightStacker.decodeRGBA8(data) else { return false }
        if accumulator == nil {
            width = decoded.width
            height = decoded.height
            accumulator = NightAccumulator(byteCount: decoded.bytes.count)
        } else if decoded.width != width || decoded.height != height {
            return false
        }
        return accumulator?.add(frame: decoded.bytes) ?? false
    }

    /// Encodes the running average as HEIF. Only meaningful once all frames were added.
    func encodedHEIF() -> Data? {
        guard let accumulator, let average = accumulator.average() else { return nil }
        return NightStacker.encodeHEIF(rgba: average, width: width, height: height)
    }
}
