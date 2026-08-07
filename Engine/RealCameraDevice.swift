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
    private(set) var activeLens: LensKind = .wide

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
            shutterSeconds: format.minExposureDuration.seconds...min(format.maxExposureDuration.seconds, 1.0),
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
        }
    }

    func switchTo(_ lens: LensKind) {
        sessionQueue.sync { [self] in
            session.beginConfiguration()
            attach(lens: lens)
            session.commitConfiguration()
        }
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
            photoOutput.capturePhoto(with: settings, delegate: coordinator)
        }
    }
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
