public enum RailLabels {
    /// "—" when off, "3s"/"10s" when set
    public static func timer(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        return "\(seconds)s"
    }

    /// "—" when nil, "BKT 3"/"BKT 5"
    public static func bracket(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "BKT \(count)"
    }

    /// Short LONG label: "—" for .off, "15s" for presets, "BULB" for bulb
    public static func long(_ mode: LongMode) -> String {
        switch mode {
        case .off:
            return "—"
        case .preset(let seconds):
            return "\(seconds)s"
        case .bulb:
            return "BULB"
        }
    }

    /// Pipeline summary for the statusline, e.g. "RAW+HEIF · STD", "HEIF · MAX"
    public static func pipeline(raw: RAWMode, heifCompanion: Bool, processing: ProcessingLevel) -> String {
        var parts: [String] = []

        // Add raw format
        let rawLabel = raw.rawValue
        if raw != .off && heifCompanion {
            parts.append("\(rawLabel)+HEIF")
        } else {
            parts.append(rawLabel)
        }

        // Add processing level
        parts.append(processing.rawValue)

        return parts.joined(separator: " · ")
    }
}
