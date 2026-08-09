import Foundation
import SnapFlexCore
import WatchConnectivity

/// Abstraction over `WCSession` so `WatchRemote` is testable without a real
/// Watch Connectivity session, which behaves inertly (and can misbehave) without
/// a paired watch.
protocol WatchSessionProtocol: AnyObject {
    var isReachable: Bool { get }
    func send(_ message: [String: Any])
}

/// Fire-and-forget adapter: `WCSession.sendMessage` takes reply/error handlers
/// we don't need, since status/thumbnail pushes are best-effort.
extension WCSession: WatchSessionProtocol {
    func send(_ message: [String: Any]) {
        sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}

/// Phone-side half of the watch remote: publishes status/thumbnails to the
/// watch and relays capture requests back to the app.
final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    private let session: WatchSessionProtocol
    private var lastStatus: WatchStatus?
    var onCaptureRequested: (() -> Void)?

    init(session: WatchSessionProtocol) {
        self.session = session
        super.init()
    }

    /// Process-wide instance: created once, on first access. Views must not
    /// construct their own — a `WatchRemote` created and dropped on every
    /// re-init (e.g. `ViewfinderScreen` recreating its `@State` across
    /// scenePhase-driven view re-inits) would grab `WCSession.default`'s
    /// (weak) delegate slot and immediately lose it once deallocated.
    static let shared: WatchRemote? = {
        guard WCSession.isSupported() else { return nil }
        let remote = WatchRemote(session: WCSession.default)
        WCSession.default.delegate = remote
        WCSession.default.activate()
        return remote
    }()

    /// `nil` when Watch Connectivity isn't supported on this device.
    static func live() -> WatchRemote? { shared }

    func publishStatus(_ status: WatchStatus) {
        lastStatus = status
        guard session.isReachable else { return }
        session.send([WatchMessageKey.status: status.encoded()])
    }

    func pushThumbnail(_ jpeg: Data) {
        guard session.isReachable else { return }
        session.send([WatchMessageKey.thumbnail: jpeg])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Watch connecting mid-operation must not leave it on a stale default
    /// status (e.g. READY/canCapture while a LONG exposure is running) —
    /// resend whatever was last published as soon as reachability returns.
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session.isReachable, let status = self.lastStatus else { return }
            self.publishStatus(status)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchMessageKey.capture] != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureRequested?()
        }
    }
}
