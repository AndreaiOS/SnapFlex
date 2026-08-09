import Foundation
import SnapFlexCore
import UIKit
import WatchConnectivity
import WatchKit

/// Watch-side half of the remote: activates its own `WCSession`, publishes the
/// phone's status/thumbnail as observable state, and sends capture requests.
final class WatchSessionModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var statusLine = "READY"
    @Published var canCapture = true
    @Published var isReachable = false
    @Published var thumbnail: UIImage?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendCapture() {
        guard let session, session.isReachable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        session.sendMessage([WatchMessageKey.capture: true], replyHandler: nil, errorHandler: nil)
        WKInterfaceDevice.current().play(.click)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateReachability(session.isReachable)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateReachability(session.isReachable)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyOnMain(message)
    }

    private func updateReachability(_ reachable: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isReachable = reachable }
    }

    private func applyOnMain(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.apply(message) }
    }

    private func apply(_ message: [String: Any]) {
        if let data = message[WatchMessageKey.status] as? Data, let status = WatchStatus.decode(data) {
            statusLine = status.line
            canCapture = status.canCapture
        }
        if let jpeg = message[WatchMessageKey.thumbnail] as? Data, let image = UIImage(data: jpeg) {
            thumbnail = image
        }
    }
}
