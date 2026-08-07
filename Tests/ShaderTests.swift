// Tests/ShaderTests.swift
import Testing
import Metal
@testable import SnapFlex

@Suite struct ShaderTests {
    /// 8×8 BGRA texture from per-pixel gray values (0-255).
    func makeTexture(device: MTLDevice, grays: [UInt8]) -> MTLTexture {
        let side = 8
        precondition(grays.count == side * side)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8]()
        for gray in grays { pixels.append(contentsOf: [gray, gray, gray, 255]) }  // BGRA
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: side * 4)
        return texture
    }

    func maskPixels(_ texture: MTLTexture) -> [(r: UInt8, g: UInt8)] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
                         from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                         mipmapLevel: 0)
        return stride(from: 0, to: bytes.count, by: 4).map { (bytes[$0], bytes[$0 + 1]) }
    }

    func setupPipeline() throws -> (OverlayPipeline, MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = OverlayPipeline(device: device),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "metal-unavailable", code: 1)
        }
        return (pipeline, device, queue)
    }

    @Test func histogramCountsUniformImage() throws {
        let (pipeline, device, queue) = try setupPipeline()
        pipeline.settings = OverlaySettings(peakingEnabled: false, zebraEnabled: false,
                                            histogramEnabled: true,
                                            peakingThreshold: 0.25, zebraThreshold: 0.98)
        // All pixels gray 128 → bin 32 of 64 gets all 64 counts, every channel.
        let texture = makeTexture(device: device, grays: .init(repeating: 128, count: 64))
        let bins = pipeline.process(texture: texture, commandQueue: queue)
        #expect(bins?.count == 192)
        #expect(bins?[32] == 64)          // R channel bin 32
        #expect(bins?[64 + 32] == 64)     // G
        #expect(bins?[128 + 32] == 64)    // B
    }

    @Test func zebraFlagsOnlyBrightPixels() throws {
        let (pipeline, device, queue) = try setupPipeline()
        pipeline.settings = OverlaySettings(peakingEnabled: false, zebraEnabled: true,
                                            histogramEnabled: false,
                                            peakingThreshold: 0.25, zebraThreshold: 0.98)
        // Top half 255 (clipped), bottom half 100.
        let grays = [UInt8](repeating: 255, count: 32) + [UInt8](repeating: 100, count: 32)
        let texture = makeTexture(device: device, grays: grays)
        _ = pipeline.process(texture: texture, commandQueue: queue)
        let mask = maskPixels(pipeline.maskTexture!)
        #expect(mask[0].g == 255)         // clipped pixel flagged
        #expect(mask[63].g == 0)          // mid-gray not flagged
    }

    @Test func peakingFiresOnEdges() throws {
        let (pipeline, device, queue) = try setupPipeline()
        pipeline.settings = OverlaySettings(peakingEnabled: true, zebraEnabled: false,
                                            histogramEnabled: false,
                                            peakingThreshold: 0.25, zebraThreshold: 0.98)
        // Left half black, right half white → strong vertical edge at column 3/4.
        var grays = [UInt8]()
        for _ in 0..<8 { grays += [UInt8](repeating: 0, count: 4) + [UInt8](repeating: 255, count: 4) }
        let texture = makeTexture(device: device, grays: grays)
        _ = pipeline.process(texture: texture, commandQueue: queue)
        let mask = maskPixels(pipeline.maskTexture!)
        let row = Array(mask[8..<16])     // row 1 (avoid border row 0)
        #expect(row[3].r == 255 || row[4].r == 255)   // edge flagged
        #expect(row[1].r == 0)            // flat area not flagged
    }
}
