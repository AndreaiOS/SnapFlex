public enum NightStack {
    public static let frameCount = 8
}

public struct NightAccumulator {
    public private(set) var framesAdded: Int
    public let pixelCount: Int

    private var sums: [UInt16]

    public init(byteCount: Int) {
        self.framesAdded = 0
        self.pixelCount = byteCount
        self.sums = [UInt16](repeating: 0, count: byteCount)
    }

    /// Adds an RGBA8 frame. Returns false (and adds nothing) if frame.count != byteCount.
    public mutating func add(frame: [UInt8]) -> Bool {
        guard frame.count == pixelCount else {
            return false
        }

        frame.withUnsafeBufferPointer { buffer in
            for i in 0..<pixelCount {
                sums[i] &+= UInt16(buffer[i])
            }
        }

        framesAdded += 1
        return true
    }

    /// Integer-mean of added frames; nil if framesAdded == 0.
    public func average() -> [UInt8]? {
        guard framesAdded > 0 else {
            return nil
        }

        let n = UInt16(framesAdded)
        let halfN = n / 2

        var result = [UInt8]()
        result.reserveCapacity(pixelCount)

        for sum in sums {
            let rounded = (sum &+ halfN) / n
            result.append(UInt8(rounded))
        }

        return result
    }
}
