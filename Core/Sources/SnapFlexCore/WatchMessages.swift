import Foundation

public enum WatchMessageKey {
    public static let capture = "capture"        // watch -> phone, message key presence triggers
    public static let status = "status"          // phone -> watch, value: encoded WatchStatus
    public static let thumbnail = "thumbnail"    // phone -> watch, value: JPEG Data
}

public struct WatchStatus: Codable, Equatable, Sendable {
    public var line: String        // e.g. "READY", "NIGHT 3/8", "LONG 12s"
    public var canCapture: Bool

    public init(line: String, canCapture: Bool) {
        self.line = line
        self.canCapture = canCapture
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            return Data()
        }
    }

    public static func decode(_ data: Data) -> WatchStatus? {
        let decoder = JSONDecoder()
        return try? decoder.decode(WatchStatus.self, from: data)
    }
}
