// Overlay/OverlayFrameDriver.swift
import CoreVideo
import Metal

final class OverlayFrameDriver {
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipeline: OverlayPipeline
    private var textureCache: CVMetalTextureCache?

    var onHistogram: (([UInt32]) -> Void)?
    var maskTexture: MTLTexture? { pipeline.maskTexture }
    var waveformTexture: MTLTexture? { pipeline.waveformTexture }
    var loupeTexture: MTLTexture? { pipeline.loupeTexture }

    var settings: OverlaySettings {
        get { pipeline.settings }
        set { pipeline.settings = newValue }
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

    func ingest(_ pixelBuffer: CVPixelBuffer) {
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
