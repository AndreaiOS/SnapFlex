public enum LongBlend: String, CaseIterable, Sendable {
    case nd = "ND"
    case trails = "TRAILS"
}

public enum LongMode: Equatable, Sendable {
    case off
    case preset(seconds: Int)
    case bulb

    public static let presetSeconds = [2, 5, 15, 30]
    public static let bulbCapSeconds: Double = 300

    public var next: LongMode {
        switch self {
        case .off: return .preset(seconds: Self.presetSeconds[0])
        case .preset(let seconds):
            if let index = Self.presetSeconds.firstIndex(of: seconds),
               index + 1 < Self.presetSeconds.count {
                return .preset(seconds: Self.presetSeconds[index + 1])
            }
            return .bulb
        case .bulb: return .off
        }
    }

    public var label: String {
        switch self {
        case .off: return "LONG OFF"
        case .preset(let seconds): return "LONG \(seconds)s"
        case .bulb: return "LONG BULB"
        }
    }
}

public struct LongExposureSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case exposing(elapsed: Double)
        case finished(save: Bool)
    }

    public let mode: LongMode
    public private(set) var phase: Phase = .exposing(elapsed: 0)
    private static let minimumSaveSeconds = 1.0

    public init(mode: LongMode) {
        self.mode = mode
    }

    public var elapsed: Double {
        if case .exposing(let elapsed) = phase { return elapsed }
        return 0
    }

    public var targetSeconds: Double {
        if case .preset(let seconds) = mode { return Double(seconds) }
        return LongMode.bulbCapSeconds
    }

    public var progress: Double? {
        guard case .preset = mode, case .exposing(let elapsed) = phase else { return nil }
        return min(elapsed / targetSeconds, 1)
    }

    public mutating func tick(_ delta: Double) {
        guard case .exposing(let elapsed) = phase else { return }
        let advanced = elapsed + delta
        if advanced >= targetSeconds {
            phase = .finished(save: true)
        } else {
            phase = .exposing(elapsed: advanced)
        }
    }

    public mutating func shutterTapped() {
        guard case .exposing(let elapsed) = phase else { return }
        switch mode {
        case .bulb: phase = .finished(save: elapsed >= Self.minimumSaveSeconds)
        default: phase = .finished(save: false)
        }
    }

    public mutating func interrupted() {
        guard case .exposing(let elapsed) = phase else { return }
        phase = .finished(save: elapsed >= Self.minimumSaveSeconds)
    }
}
