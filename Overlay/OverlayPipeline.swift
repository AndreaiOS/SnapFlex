// Overlay/OverlayPipeline.swift
import Metal

struct OverlaySettings: Equatable {
    var peakingEnabled: Bool
    var zebraEnabled: Bool
    var histogramEnabled: Bool
    var peakingThreshold: Float
    var zebraThreshold: Float

    static let allOff = OverlaySettings(peakingEnabled: false, zebraEnabled: false,
                                        histogramEnabled: false,
                                        peakingThreshold: 0.25, zebraThreshold: 0.98)
    var anyEnabled: Bool { peakingEnabled || zebraEnabled || histogramEnabled }
}

final class OverlayPipeline {
    private struct MaskParams {
        var peakingThreshold: Float
        var zebraThreshold: Float
        var peakingEnabled: UInt32
        var zebraEnabled: UInt32
    }

    private let device: MTLDevice
    private let histogramPipeline: MTLComputePipelineState
    private let maskPipeline: MTLComputePipelineState
    private let binsBuffer: MTLBuffer
    private let stateLock = NSLock()

    private var _settings: OverlaySettings = .allOff
    private var _maskTexture: MTLTexture?

    var settings: OverlaySettings {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _settings }
        set { stateLock.lock(); defer { stateLock.unlock() }; _settings = newValue }
    }

    var maskTexture: MTLTexture? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _maskTexture }
    }

    init?(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let histogramFn = library.makeFunction(name: "histogramKernel"),
              let maskFn = library.makeFunction(name: "maskKernel"),
              let histogramPipeline = try? device.makeComputePipelineState(function: histogramFn),
              let maskPipeline = try? device.makeComputePipelineState(function: maskFn),
              let binsBuffer = device.makeBuffer(length: 192 * MemoryLayout<UInt32>.stride,
                                                 options: .storageModeShared)
        else { return nil }
        self.device = device
        self.histogramPipeline = histogramPipeline
        self.maskPipeline = maskPipeline
        self.binsBuffer = binsBuffer
    }

    func process(texture: MTLTexture, commandQueue: MTLCommandQueue) -> [UInt32]? {
        let settings = self.settings
        guard settings.anyEnabled,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

        if settings.histogramEnabled {
            memset(binsBuffer.contents(), 0, binsBuffer.length)
        }

        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: texture.width, height: texture.height, depth: 1)

        if settings.histogramEnabled,
           let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(histogramPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(binsBuffer, offset: 0, index: 0)
            encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        if settings.peakingEnabled || settings.zebraEnabled {
            ensureMaskTexture(width: texture.width, height: texture.height)
            let maskTexture = self.maskTexture
            if let maskTexture,
               let encoder = commandBuffer.makeComputeCommandEncoder() {
                var params = MaskParams(peakingThreshold: settings.peakingThreshold,
                                        zebraThreshold: settings.zebraThreshold,
                                        peakingEnabled: settings.peakingEnabled ? 1 : 0,
                                        zebraEnabled: settings.zebraEnabled ? 1 : 0)
                encoder.setComputePipelineState(maskPipeline)
                encoder.setTexture(texture, index: 0)
                encoder.setTexture(maskTexture, index: 1)
                encoder.setBytes(&params, length: MemoryLayout<MaskParams>.stride, index: 0)
                encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
            }
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard settings.histogramEnabled else { return nil }
        let pointer = binsBuffer.contents().bindMemory(to: UInt32.self, capacity: 192)
        return Array(UnsafeBufferPointer(start: pointer, count: 192))
    }

    private func ensureMaskTexture(width: Int, height: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let texture = _maskTexture, texture.width == width, texture.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        _maskTexture = device.makeTexture(descriptor: descriptor)
    }
}
