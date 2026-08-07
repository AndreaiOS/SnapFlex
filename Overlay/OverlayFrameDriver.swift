// Overlay/OverlayFrameDriver.swift
import CoreVideo
import Metal

final class OverlayFrameDriver {
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipeline: OverlayPipeline
    private var textureCache: CVMetalTextureCache?
    private var attachFrames: (((CVPixelBuffer) -> Void)?) -> Void = { _ in }

    var onHistogram: (([UInt32]) -> Void)?
    var maskTexture: MTLTexture? { pipeline.maskTexture }

    var settings: OverlaySettings {
        get { pipeline.settings }
        set {
            let wasEnabled = pipeline.settings.anyEnabled
            pipeline.settings = newValue
            if newValue.anyEnabled != wasEnabled {
                attachFrames(newValue.anyEnabled ? { [weak self] in self?.handle($0) } : nil)
            }
        }
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = OverlayPipeline(device: device) else { return nil }
        self.metalDevice = device
        self.commandQueue = queue
        self.pipeline = pipeline
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    /// Supply the device hook that attaches/detaches the video data output.
    func bind(attach: @escaping (((CVPixelBuffer) -> Void)?) -> Void) {
        attachFrames = attach
        if pipeline.settings.anyEnabled {
            attach { [weak self] in self?.handle($0) }
        }
    }

    private func handle(_ pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        if let bins = pipeline.process(texture: texture, commandQueue: commandQueue) {
            onHistogram?(bins)
        }
    }
}
