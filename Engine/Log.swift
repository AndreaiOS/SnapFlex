import os

/// One logging surface for the whole app: `log stream --predicate
/// 'subsystem == "co.SnapFlex"'` shows everything; filter by category to
/// narrow. Existing loggers (capture-store, long-exposure) share the subsystem.
enum Log {
    static let capture = Logger(subsystem: "co.SnapFlex", category: "capture")
    static let night = Logger(subsystem: "co.SnapFlex", category: "night-stack")
    static let watch = Logger(subsystem: "co.SnapFlex", category: "watch-remote")
    static let session = Logger(subsystem: "co.SnapFlex", category: "session")
}
