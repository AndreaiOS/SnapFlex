import Testing
import Metal
import UIKit
import SnapFlexCore
@testable import SnapFlex

@Suite struct LongAccumulatorTests {
    func makeTexture(device: MTLDevice, gray: UInt8, side: Int = 8) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8]()
        for _ in 0..<(side * side) { pixels.append(contentsOf: [gray, gray, gray, 255]) }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: side * 4)
        return texture
    }

    func firstPixel(_ texture: MTLTexture) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: texture.width * 16,
                         from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return pixel
    }

    func setup() throws -> (LongExposureAccumulator, MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let accumulator = LongExposureAccumulator(device: device),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "metal-unavailable", code: 1)
        }
        return (accumulator, device, queue)
    }

    @Test func averageOfTwoFramesIsMean() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 100), commandQueue: queue)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 200), commandQueue: queue)
        #expect(accumulator.frameCount == 2)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        let expected = (100.0 / 255.0 + 200.0 / 255.0) / 2.0
        #expect(abs(Double(pixel[0]) - expected) < 0.01)
    }

    @Test func maxKeepsBrightestPixel() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .trails)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 180), commandQueue: queue)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 60), commandQueue: queue)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        #expect(abs(Double(pixel[0]) - 180.0 / 255.0) < 0.01)
    }

    @Test func beginResetsState() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 255), commandQueue: queue)
        accumulator.begin(blend: .nd)
        #expect(accumulator.frameCount == 0)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 10), commandQueue: queue)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        #expect(abs(Double(pixel[0]) - 10.0 / 255.0) < 0.01)
    }

    @Test func readoutProducesDecodableHEIF() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 128, side: 16), commandQueue: queue)
        let data = try #require(accumulator.readoutImageData())
        let image = try #require(UIImage(data: data))
        #expect(image.size.width == 16 && image.size.height == 16)
    }
}
