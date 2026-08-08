// LongExposure/LongExposureController.swift
import CoreVideo
import Foundation
import Metal
import Observation
import SnapFlexCore

@Observable @MainActor
final class LongExposureController {
    private(set) var session: LongExposureSession?
    var isExposing: Bool { session != nil }
    private(set) var elapsed: Double = 0
    private(set) var progress: Double?          // nil for bulb
    var previewTexture: MTLTexture? { accumulator.accumulationTexture }
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue

    // Accessed from the nonisolated `ingest(_:)`, which runs on the camera's videoQueue.
    // `accumulator` guards its own state internally with a lock; `textureCache` is a
    // Core Video opaque handle set once in init and only read thereafter; `runningFlag`
    // is only ever touched while holding `runningLock`.
    nonisolated(unsafe) private let accumulator: LongExposureAccumulator
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    private var timerTask: Task<Void, Never>?

    private let runningLock = NSLock()
    nonisolated(unsafe) private var runningFlag = false

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let accumulator = LongExposureAccumulator(device: device) else { return nil }
        self.metalDevice = device
        self.commandQueue = queue
        self.accumulator = accumulator
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    /// Starts a session; `onFinished` fires exactly once with HEIF data (nil = discard).
    func start(mode: LongMode, blend: LongBlend, onFinished: @escaping (Data?) -> Void) {
        guard session == nil else { return }
        accumulator.begin(blend: blend)
        setRunning(true)
        session = LongExposureSession(mode: mode)
        elapsed = 0
        progress = session?.progress

        timerTask = Task { [weak self] in
            guard let self else { return }
            var shouldSave = false
            var lastTick = ContinuousClock.now
            while true {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let delta = Double((now - lastTick).components.seconds)
                    + Double((now - lastTick).components.attoseconds) / 1e18
                lastTick = now
                self.session?.tick(delta)
                self.elapsed = self.session?.elapsed ?? self.elapsed
                self.progress = self.session?.progress
                if case .finished(let save) = self.session?.phase {
                    shouldSave = save
                    break
                }
            }

            self.setRunning(false)

            let frameCount = self.accumulator.frameCount
            let data: Data?
            if shouldSave && frameCount > 0 {
                data = await Task.detached { [accumulator = self.accumulator] in
                    accumulator.readoutImageData()
                }.value
            } else {
                data = nil
            }

            self.session = nil
            self.elapsed = 0
            self.progress = nil
            onFinished(data)
        }
    }

    func shutterTapped() {
        session?.shutterTapped()
    }

    func interrupted() {
        session?.interrupted()
    }

    /// nonisolated — called on videoQueue with each camera frame while running.
    nonisolated func ingest(_ pixelBuffer: CVPixelBuffer) {
        guard isRunning, let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        accumulator.accumulate(texture: texture, commandQueue: commandQueue)
    }

    /// Synchronous, nonisolated lock-protected accessors. Plain function bodies (rather than
    /// inline `.lock()`/`.unlock()` at async call sites) avoid the async-context NSLock warning.
    private nonisolated func setRunning(_ value: Bool) {
        runningLock.lock()
        runningFlag = value
        runningLock.unlock()
    }

    private nonisolated var isRunning: Bool {
        runningLock.lock()
        defer { runningLock.unlock() }
        return runningFlag
    }
}
