import Foundation

public struct ManualBracketExposure: Equatable, Sendable {
    public var iso: Float
    public var shutterSeconds: Double

    public init(iso: Float, shutterSeconds: Double) {
        self.iso = iso
        self.shutterSeconds = shutterSeconds
    }
}

public enum ExposureBase: Equatable, Sendable {
    case auto
    case manual(iso: Float, shutterSeconds: Double)
}

public enum BracketingPlan: Equatable, Sendable {
    case autoExposure(biases: [Float])
    case manual(exposures: [ManualBracketExposure])

    /// Centered EV offsets, darkest→brightest: e.g. count 5, step 1 → [-2,-1,0,1,2].
    static func offsets(count: Int, stepEV: Float) -> [Float] {
        let half = count / 2
        return (-half...half).map { Float($0) * stepEV }
    }

    public static func make(count: Int, stepEV: Float, base: ExposureBase,
                            ranges: ParameterRanges) -> BracketingPlan {
        let offsets = offsets(count: count, stepEV: stepEV)
        switch base {
        case .auto:
            let biases = offsets.map {
                min(max($0, ranges.evBias.lowerBound), ranges.evBias.upperBound)
            }
            return .autoExposure(biases: biases)
        case .manual(let iso, let shutterSeconds):
            let exposures = offsets.map { ev in
                let seconds = shutterSeconds * pow(2.0, Double(ev))
                let clampedSeconds = min(max(seconds, ranges.shutterSeconds.lowerBound),
                                         ranges.shutterSeconds.upperBound)
                return ManualBracketExposure(iso: iso, shutterSeconds: clampedSeconds)
            }
            return .manual(exposures: exposures)
        }
    }
}
