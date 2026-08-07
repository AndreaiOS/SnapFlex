public enum LensKind: String, CaseIterable, Sendable, Codable {
    case ultraWide, wide, telephoto

    public var displayName: String {
        switch self {
        case .ultraWide: ".5"
        case .wide: "1×"
        case .telephoto: "T"
        }
    }
}

public struct ParameterRanges: Equatable, Sendable {
    public var iso: ClosedRange<Float>
    public var shutterSeconds: ClosedRange<Double>
    public var evBias: ClosedRange<Float>
    public var zoom: ClosedRange<Double>

    public init(iso: ClosedRange<Float>, shutterSeconds: ClosedRange<Double>,
                evBias: ClosedRange<Float>, zoom: ClosedRange<Double>) {
        self.iso = iso
        self.shutterSeconds = shutterSeconds
        self.evBias = evBias
        self.zoom = zoom
    }
}

/// Manual parameter values. `nil` means "auto" for that parameter.
public struct ManualValues: Equatable, Sendable {
    public static let wbKelvinRange = 2500...8000
    public static let focusRange: ClosedRange<Float> = 0...1

    public var iso: Float?
    public var shutterSeconds: Double?
    public var focusPosition: Float?
    public var wbKelvin: Int?
    public var evBias: Float

    public init(iso: Float?, shutterSeconds: Double?, focusPosition: Float?,
                wbKelvin: Int?, evBias: Float) {
        self.iso = iso
        self.shutterSeconds = shutterSeconds
        self.focusPosition = focusPosition
        self.wbKelvin = wbKelvin
        self.evBias = evBias
    }
}

/// Clamp manual values into device ranges. Never resets a manual value to auto.
public func clamped(_ values: ManualValues, to ranges: ParameterRanges) -> ManualValues {
    var result = values
    result.iso = values.iso.map { min(max($0, ranges.iso.lowerBound), ranges.iso.upperBound) }
    result.shutterSeconds = values.shutterSeconds.map {
        min(max($0, ranges.shutterSeconds.lowerBound), ranges.shutterSeconds.upperBound)
    }
    result.focusPosition = values.focusPosition.map {
        min(max($0, ManualValues.focusRange.lowerBound), ManualValues.focusRange.upperBound)
    }
    result.wbKelvin = values.wbKelvin.map {
        min(max($0, ManualValues.wbKelvinRange.lowerBound), ManualValues.wbKelvinRange.upperBound)
    }
    result.evBias = min(max(values.evBias, ranges.evBias.lowerBound), ranges.evBias.upperBound)
    return result
}
