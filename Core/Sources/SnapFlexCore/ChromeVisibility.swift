public struct ChromeVisibility: Equatable, Sendable {
    public enum State: Equatable, Sendable { case full, minimal }
    public static let idleSeconds: Double = 2.0

    public private(set) var state: State = .full
    private var lastInteraction: Double = 0

    /// Conditions that pin the chrome to .full (dial open, exposing, countdown, overlay).
    public var blocked: Bool = false {
        didSet {
            if blocked {
                state = .full
            }
        }
    }

    public init(blocked: Bool = false) {
        self.blocked = blocked
    }

    /// User interacted now: state = .full, idle clock restarts.
    public mutating func interaction(at time: Double) {
        state = .full
        lastInteraction = time
    }

    /// Clock tick: hides when now - lastInteraction >= idleSeconds, unless blocked.
    public mutating func tick(now: Double) {
        guard !blocked else { return }
        if now - lastInteraction >= Self.idleSeconds {
            state = .minimal
        }
    }
}

/// "ISO 200 · 1/120 · ND 15s" summary for the minimal readout pill.
public func chromeReadout(values: ManualValues, longMode: LongMode, longBlend: LongBlend,
                          processing: ProcessingLevel) -> String {
    var parts: [String] = []

    // ISO
    if let iso = values.iso {
        parts.append("ISO \(Int(iso))")
    }

    // Shutter
    if let shutter = values.shutterSeconds {
        let shutterStr: String
        if shutter >= 0.35 {
            shutterStr = String(format: "%.1fs", shutter)
        } else {
            shutterStr = "1/\(Int((1.0 / shutter).rounded()))"
        }
        parts.append(shutterStr)
    }

    // EV (non-zero only)
    if values.evBias != 0 {
        parts.append(String(format: "EV %+.1f", values.evBias))
    }

    // WB (manual only)
    if let wbKelvin = values.wbKelvin {
        parts.append("\(wbKelvin)K")
    }

    // MF (manual focus)
    if values.focusPosition != nil {
        parts.append("MF")
    }

    // LONG mode
    if longMode != .off {
        let longStr: String
        switch longMode {
        case .off:
            break
        case .preset(let seconds):
            longStr = "\(longBlend.rawValue) \(seconds)s"
            parts.append(longStr)
        case .bulb:
            longStr = "\(longBlend.rawValue) BULB"
            parts.append(longStr)
        }
    }

    // Processing (only when != .standard)
    if processing != .standard {
        parts.append(processing.rawValue)
    }

    return parts.isEmpty ? "AUTO" : parts.joined(separator: " · ")
}
