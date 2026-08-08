import CoreImage
import Metal
import SnapFlexCore

final class LongExposureAccumulator {
    private let device: MTLDevice
    private let averagePipeline: MTLComputePipelineState
    private let maxPipeline: MTLComputePipelineState
    private let ciContext: CIContext
    private let lock = NSLock()

    private var blend: LongBlend = .nd
    private var _frameCount = 0
    private var _accumulationTexture: MTLTexture?

    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _frameCount
    }

    var accumulationTexture: MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return _accumulationTexture
    }

    init?(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let averageFn = library.makeFunction(name: "accumulateAverageKernel"),
              let maxFn = library.makeFunction(name: "accumulateMaxKernel"),
              let averagePipeline = try? device.makeComputePipelineState(function: averageFn),
              let maxPipeline = try? device.makeComputePipelineState(function: maxFn)
        else { return nil }
        self.device = device
        self.averagePipeline = averagePipeline
        self.maxPipeline = maxPipeline
        self.ciContext = CIContext(mtlDevice: device)
    }

    func begin(blend: LongBlend) {
        lock.lock(); defer { lock.unlock() }
        self.blend = blend
        _frameCount = 0
        _accumulationTexture = nil
    }

    func accumulate(texture: MTLTexture, commandQueue: MTLCommandQueue) {
        lock.lock()
        if _accumulationTexture == nil ||
            _accumulationTexture!.width != texture.width ||
            _accumulationTexture!.height != texture.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: texture.width, height: texture.height,
                mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            _accumulationTexture = device.makeTexture(descriptor: descriptor)
            _frameCount = 0
        }
        _frameCount += 1
        var frameNumber = UInt32(_frameCount)
        let accumulation = _accumulationTexture!
        let pipeline = blend == .nd ? averagePipeline : maxPipeline
        lock.unlock()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(accumulation, index: 1)
        encoder.setBytes(&frameNumber, length: MemoryLayout<UInt32>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func readoutImageData() -> Data? {
        guard let texture = accumulationTexture,
              let ciImage = CIImage(mtlTexture: texture, options: [
                  .colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
              ])
        else { return nil }
        let oriented = ciImage.oriented(.downMirrored)   // Metal textures are top-left origin
        return ciContext.heifRepresentation(
            of: oriented, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0])
    }
}
