public struct DeviceCapabilities: Equatable, Sendable {
    public var supportsProRAW: Bool
    public var supportsBayerRAW: Bool

    public init(supportsProRAW: Bool, supportsBayerRAW: Bool) {
        self.supportsProRAW = supportsProRAW
        self.supportsBayerRAW = supportsBayerRAW
    }
}

public enum RAWMode: String, CaseIterable, Sendable, Codable {
    case off = "HEIF"
    case proRAW = "ProRAW"
    case bayer = "RAW"
}

public struct FormatSelection: Equatable, Sendable {
    public var raw: RAWMode
    public var heifCompanion: Bool

    public init(raw: RAWMode, heifCompanion: Bool) {
        self.raw = raw
        self.heifCompanion = heifCompanion
    }
}

public enum RAWKind: Equatable, Sendable {
    case proRAW, bayer, none
}

public struct CaptureRecipe: Equatable, Sendable {
    public var raw: RAWKind
    public var includeProcessed: Bool
    public var bracketing: BracketingPlan?
    public var processing: ProcessingLevel

    public init(raw: RAWKind, includeProcessed: Bool, bracketing: BracketingPlan?, processing: ProcessingLevel = .standard) {
        self.raw = raw
        self.includeProcessed = includeProcessed
        self.bracketing = bracketing
        self.processing = processing
    }

    public static func make(selection: FormatSelection, capabilities: DeviceCapabilities,
                            bracketing: BracketingPlan?, processing: ProcessingLevel = .standard) -> CaptureRecipe {
        var raw: RAWKind = switch selection.raw {
        case .off: .none
        case .proRAW: capabilities.supportsProRAW ? .proRAW
                      : capabilities.supportsBayerRAW ? .bayer : .none
        case .bayer: capabilities.supportsBayerRAW ? .bayer : .none
        }
        // AVCapturePhotoBracketSettings does not support ProRAW.
        if bracketing != nil, raw == .proRAW {
            raw = capabilities.supportsBayerRAW ? .bayer : .none
        }
        let includeProcessed = selection.heifCompanion || raw == .none
        return CaptureRecipe(raw: raw, includeProcessed: includeProcessed, bracketing: bracketing, processing: processing)
    }
}
