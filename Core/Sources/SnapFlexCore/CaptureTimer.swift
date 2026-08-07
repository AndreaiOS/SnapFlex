public struct CaptureTimer: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case counting(remaining: Int)
        case fired
    }

    public var duration: Int
    public private(set) var state: State = .idle

    public init(duration: Int) {
        self.duration = duration
    }

    public mutating func start() {
        state = duration > 0 ? .counting(remaining: duration) : .fired
    }

    public mutating func tick() {
        guard case .counting(let remaining) = state else { return }
        state = remaining > 1 ? .counting(remaining: remaining - 1) : .fired
    }

    public mutating func cancel() {
        state = .idle
    }
}
