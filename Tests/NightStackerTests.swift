import CoreGraphics
import Foundation
import Testing
@testable import SnapFlex

@Suite struct NightStackerTests {
    /// Builds a solid-color RGBA8 (premultipliedLast) buffer.
    static func solidRGBA(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r
            bytes[i + 1] = g
            bytes[i + 2] = b
            bytes[i + 3] = a
        }
        return bytes
    }

    @Test func roundTripPreservesDimensions() throws {
        let rgba = Self.solidRGBA(width: 4, height: 4, r: 200, g: 100, b: 50)
        let encoded = try #require(NightStacker.encodeHEIF(rgba: rgba, width: 4, height: 4))
        let decoded = try #require(NightStacker.decodeRGBA8(encoded))
        #expect(decoded.width == 4)
        #expect(decoded.height == 4)
        #expect(decoded.bytes.count == 4 * 4 * 4)
    }

    @Test func roundTripPreservesColorWithinLossyTolerance() throws {
        let rgba = Self.solidRGBA(width: 4, height: 4, r: 200, g: 100, b: 50)
        let encoded = try #require(NightStacker.encodeHEIF(rgba: rgba, width: 4, height: 4))
        let decoded = try #require(NightStacker.decodeRGBA8(encoded))
        for i in stride(from: 0, to: decoded.bytes.count, by: 4) {
            #expect(abs(Int(decoded.bytes[i]) - 200) <= 3)
            #expect(abs(Int(decoded.bytes[i + 1]) - 100) <= 3)
            #expect(abs(Int(decoded.bytes[i + 2]) - 50) <= 3)
        }
    }

    @Test func decodeRGBA8FailsOnGarbageData() {
        #expect(NightStacker.decodeRGBA8(Data([0, 1, 2, 3])) == nil)
    }

    @Test func encodeHEIFFailsOnMismatchedByteCount() {
        #expect(NightStacker.encodeHEIF(rgba: [0, 0, 0, 255], width: 4, height: 4) == nil)
    }
}
