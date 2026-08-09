public enum ProcessingLevel: String, CaseIterable, Sendable, Codable {
    case zero = "0AI"
    case standard = "STD"
    case max = "MAX"

    public var next: ProcessingLevel {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
