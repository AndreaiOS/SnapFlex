// Engine/RealCameraDevice.swift
import AVFoundation
import SnapFlexCore

final class RealCameraDevice: NSObject, CameraDeviceProtocol {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "co.socialsprint.snapflex.session")
    private let videoQueue = DispatchQueue(label: "co.socialsprint.snapflex.video")
    private let frameHandlerLock = NSLock()

    private var devicesByLens: [LensKind: AVCaptureDevice] = [:]
    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var frameHandler: ((CVPixelBuffer) -> Void)?
    private var activeCoordinators: [UUID: PhotoCaptureCoordinator] = [:]

    var onStatusChange: ((SessionStatus) -> Void)?
    var onControlEvent: ((CameraControlEvent) -> Void)?
    private(set) var activeLens: LensKind = .wide
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    override init() {
        super.init()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back)
        for device in discovery.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera: devicesByLens[.ultraWide] = device
            case .builtInWideAngleCamera: devicesByLens[.wide] = device
            case .builtInTelephotoCamera: devicesByLens[.telephoto] = device
            default: break
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionInterrupted),
            name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionResumed),
            name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    @objc private func sessionInterrupted() { notifyStatus(.interrupted) }
    @objc private func sessionResumed() { notifyStatus(.running) }

    private func notifyStatus(_ status: SessionStatus) {
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?(status) }
    }

    // MARK: - CameraDeviceProtocol

    var availableLenses: [LensKind] {
        LensKind.allCases.filter { devicesByLens[$0] != nil }
    }

    var ranges: ParameterRanges {
        guard let device = currentDevice else {
            return ParameterRanges(iso: 1...1, shutterSeconds: 1...1, evBias: 0...0, zoom: 1...1)
        }
        let format = device.activeFormat
        return ParameterRanges(
            iso: format.minISO...format.maxISO,
            shutterSeconds: format.minExposureDuration.seconds...format.maxExposureDuration.seconds,
            evBias: device.minExposureTargetBias...device.maxExposureTargetBias,
            zoom: 1.0...min(device.activeFormat.videoMaxZoomFactor, 10.0))
    }

    var capabilities: DeviceCapabilities {
        DeviceCapabilities(
            supportsProRAW: photoOutput.isAppleProRAWSupported,
            supportsBayerRAW: photoOutput.availableRawPhotoPixelFormatTypes.contains {
                AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
            })
    }

    func start() {
        sessionQueue.async { [self] in
            guard !session.isRunning else { return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            attach(lens: .wide)
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if photoOutput.isAppleProRAWSupported { photoOutput.isAppleProRAWEnabled = true }
            photoOutput.maxPhotoQualityPrioritization = .quality
            videoOutput.videoSettings =
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.supportsControls {
                session.setControlsDelegate(self, queue: sessionQueue)
            }
            if let device = currentDevice { configureControls(for: device) }
            session.commitConfiguration()
            session.startRunning()
            notifyStatus(.running)
        }
        sessionQueue.sync {}   // callers read ranges right after start
    }

    func stop() {
        sessionQueue.async { [self] in
            session.stopRunning()
            notifyStatus(.notRunning)
        }
    }

    private func attach(lens: LensKind) {
        guard let device = devicesByLens[lens],
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if let current = currentInput { session.removeInput(current) }
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            currentDevice = device
            activeLens = lens
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }
    }

    func switchTo(_ lens: LensKind) {
        sessionQueue.sync { [self] in
            session.beginConfiguration()
            attach(lens: lens)
            if let device = currentDevice { configureControls(for: device) }
            session.commitConfiguration()
        }
    }

    // MARK: - Camera Control (hardware button on supported devices)

    /// Rebuilds the light-press controls for the active device: system zoom
    /// slider plus EV/ISO sliders and a shutter picker routed through
    /// `onControlEvent` so the engine stays the single source of truth.
    private func configureControls(for device: AVCaptureDevice) {
        guard session.supportsControls else { return }
        for control in session.controls { session.removeControl(control) }

        let format = device.activeFormat
        let zoom = AVCaptureSystemZoomSlider(device: device)

        let ev = AVCaptureSlider("Exposure", symbolName: "plusminus.circle",
                                 in: device.minExposureTargetBias...device.maxExposureTargetBias)
        ev.setActionQueue(sessionQueue) { [weak self] value in
            self?.onControlEvent?(.evBias(value))
        }

        let iso = AVCaptureSlider("ISO", symbolName: "camera.aperture",
                                  in: format.minISO...format.maxISO)
        iso.setActionQueue(sessionQueue) { [weak self] value in
            self?.onControlEvent?(.iso(value))
        }

        let shutterValues = Self.shutterStops(
            in: format.minExposureDuration.seconds...format.maxExposureDuration.seconds)
        let shutter = AVCaptureIndexPicker("Shutter", symbolName: "timer",
                                           localizedIndexTitles: shutterValues.map(Self.shutterLabel))
        shutter.setActionQueue(sessionQueue) { [weak self] index in
            guard shutterValues.indices.contains(index) else { return }
            self?.onControlEvent?(.shutterSeconds(shutterValues[index]))
        }

        for control in [zoom, ev, iso, shutter] as [AVCaptureControl]
        where session.canAddControl(control) {
            session.addControl(control)
        }
    }

    static func shutterStops(in range: ClosedRange<Double>) -> [Double] {
        let stops: [Double] = [1.0/8000, 1.0/4000, 1.0/2000, 1.0/1000, 1.0/500, 1.0/250,
                               1.0/125, 1.0/60, 1.0/30, 1.0/15, 1.0/8, 1.0/4, 1.0/2, 1.0]
        return stops.filter { range.contains($0) }
    }

    static func shutterLabel(_ seconds: Double) -> String {
        seconds >= 0.35 ? String(format: "%.1fs", seconds) : "1/\(Int((1.0 / seconds).rounded()))"
    }

    private func withLockedDevice(_ body: @escaping (AVCaptureDevice) -> Void) {
        sessionQueue.async { [self] in
            guard let device = currentDevice, (try? device.lockForConfiguration()) != nil else { return }
            body(device)
            device.unlockForConfiguration()
        }
    }

    func setExposure(iso: Float?, shutterSeconds: Double?, bias: Float) {
        withLockedDevice { device in
            if let iso, let shutterSeconds {
                let duration = CMTime(seconds: shutterSeconds, preferredTimescale: 1_000_000)
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(bias, completionHandler: nil)
        }
    }

    func lockFocus(position: Float) {
        withLockedDevice { device in
            guard device.isLockingFocusWithCustomLensPositionSupported else { return }
            device.setFocusModeLocked(lensPosition: position, completionHandler: nil)
        }
    }

    func setAutoFocus() {
        withLockedDevice { device in
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }
    }

    func setWhiteBalance(kelvin: Int?) {
        withLockedDevice { device in
            guard let kelvin else {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                return
            }
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: Float(kelvin), tint: 0)
            let raw = device.deviceWhiteBalanceGains(for: values)
            let safe = WBGains(red: raw.redGain, green: raw.greenGain, blue: raw.blueGain)
                .clamped(maxGain: device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(
                with: AVCaptureDevice.WhiteBalanceGains(
                    redGain: safe.red, greenGain: safe.green, blueGain: safe.blue),
                completionHandler: nil)
        }
    }

    func setZoom(_ factor: Double) {
        withLockedDevice { device in
            device.videoZoomFactor = factor
        }
    }

    // MARK: - Video frames (overlay pipeline, Task 12)

    func setVideoFrameHandler(_ handler: ((CVPixelBuffer) -> Void)?) {
        sessionQueue.async { [self] in
            frameHandlerLock.lock()
            frameHandler = handler
            frameHandlerLock.unlock()
            session.beginConfiguration()
            if handler != nil {
                if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                    if let connection = videoOutput.connection(with: .video),
                       connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                }
            } else if session.outputs.contains(videoOutput) {
                session.removeOutput(videoOutput)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Capture (implemented in Task 9)

    func capture(recipe: CaptureRecipe, flashOn: Bool,
                 completion: @escaping ([CaptureResource]) -> Void) {
        sessionQueue.async { [self] in
            var recipe = recipe
            if let bracketing = recipe.bracketing {
                let maxCount = photoOutput.maxBracketedCapturePhotoCount
                if maxCount <= 0 {
                    recipe.bracketing = nil
                } else {
                    switch bracketing {
                    case .autoExposure(let biases):
                        recipe.bracketing = .autoExposure(biases: Array(biases.prefix(maxCount)))
                    case .manual(let exposures):
                        recipe.bracketing = .manual(exposures: Array(exposures.prefix(maxCount)))
                    }
                }
            }
            let rawType: OSType? = switch recipe.raw {
            case .proRAW:
                photoOutput.availableRawPhotoPixelFormatTypes
                    .first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
            case .bayer:
                photoOutput.availableRawPhotoPixelFormatTypes
                    .first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            case .none:
                nil
            }
            let settings = PhotoCaptureCoordinator.makeSettings(
                recipe: recipe, rawType: rawType, flashOn: flashOn)
            let id = UUID()
            let coordinator = PhotoCaptureCoordinator { [weak self] resources in
                completion(resources)
                self?.sessionQueue.async { self?.activeCoordinators[id] = nil }
            }
            activeCoordinators[id] = coordinator
            if let coordinator = rotationCoordinator {
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            photoOutput.capturePhoto(with: settings, delegate: coordinator)
        }
    }
}

extension RealCameraDevice: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

extension RealCameraDevice: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameHandlerLock.lock()
        let handler = frameHandler
        frameHandlerLock.unlock()
        handler?(pixelBuffer)
    }
}
