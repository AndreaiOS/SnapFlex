import CoreGraphics
import Foundation
import ImageIO

/// Pure ImageIO/CoreGraphics decode+encode helpers for the NIGHT stack pipeline.
/// No UIKit dependency so these are directly unit-testable off the main actor.
enum NightStacker {
    /// Decodes `data` (any ImageIO-readable format, including HEIF) into RGBA8
    /// (premultipliedLast, sRGB). Returns nil on decode failure.
    static func decodeRGBA8(_ data: Data) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        guard let buffer = malloc(byteCount) else { return nil }
        defer { free(buffer) }
        memset(buffer, 0, byteCount)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo)
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let typedBuffer = buffer.assumingMemoryBound(to: UInt8.self)
        let bytes = [UInt8](UnsafeBufferPointer(start: typedBuffer, count: byteCount))
        return (bytes, width, height)
    }

    /// Encodes RGBA8 (premultipliedLast, sRGB) pixel data as HEIF (`public.heic`,
    /// the UTI backing `AVFileType.heic`) at lossy quality 0.9. Returns nil on encode failure.
    static func encodeHEIF(rgba: [UInt8], width: Int, height: Int) -> Data? {
        let bytesPerRow = width * 4
        guard width > 0, height > 0, rgba.count == bytesPerRow * height else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: bitmapInfo,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData, "public.heic" as CFString, 1, nil)
        else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return outputData as Data
    }
}
