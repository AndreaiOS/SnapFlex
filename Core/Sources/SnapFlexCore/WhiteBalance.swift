public struct WBGains: Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// AVFoundation requires each gain in 1.0...device.maxWhiteBalanceGain.
    public func clamped(maxGain: Float) -> WBGains {
        WBGains(red: min(max(red, 1), maxGain),
                green: min(max(green, 1), maxGain),
                blue: min(max(blue, 1), maxGain))
    }
}
