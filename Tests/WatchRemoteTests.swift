import Testing
import Foundation
@testable import SnapFlex
import SnapFlexCore
import WatchConnectivity

final class FakeWatchSession: WatchSessionProtocol {
    var isReachable = true
    var sent: [[String: Any]] = []

    func send(_ message: [String: Any]) {
        sent.append(message)
    }
}

@Suite struct WatchRemoteTests {
    @Test func captureMessageFiresOnCaptureRequestedOnMain() async {
        let fake = FakeWatchSession()
        let remote = WatchRemote(session: fake)
        await confirmation { confirmed in
            remote.onCaptureRequested = {
                #expect(Thread.isMainThread)
                confirmed()
            }
            remote.session(WCSession.default, didReceiveMessage: [WatchMessageKey.capture: true])
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func nonCaptureMessageDoesNotFireCallback() async {
        let fake = FakeWatchSession()
        let remote = WatchRemote(session: fake)
        var fired = false
        remote.onCaptureRequested = { fired = true }
        remote.session(WCSession.default, didReceiveMessage: ["other": true])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired == false)
    }

    @Test func publishStatusSendsEncodedStatusWhenReachable() {
        let fake = FakeWatchSession()
        fake.isReachable = true
        let remote = WatchRemote(session: fake)
        let status = WatchStatus(line: "NIGHT 3/8", canCapture: false)
        remote.publishStatus(status)
        #expect(fake.sent.count == 1)
        let data = fake.sent.first?[WatchMessageKey.status] as? Data
        #expect(data.flatMap(WatchStatus.decode) == status)
    }

    @Test func publishStatusDoesNothingWhenUnreachable() {
        let fake = FakeWatchSession()
        fake.isReachable = false
        let remote = WatchRemote(session: fake)
        remote.publishStatus(WatchStatus(line: "READY", canCapture: true))
        #expect(fake.sent.isEmpty)
    }

    @Test func pushThumbnailSendsJPEGDataWhenReachable() {
        let fake = FakeWatchSession()
        fake.isReachable = true
        let remote = WatchRemote(session: fake)
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        remote.pushThumbnail(jpeg)
        #expect(fake.sent.first?[WatchMessageKey.thumbnail] as? Data == jpeg)
    }

    @Test func pushThumbnailDoesNothingWhenUnreachable() {
        let fake = FakeWatchSession()
        fake.isReachable = false
        let remote = WatchRemote(session: fake)
        remote.pushThumbnail(Data([0xFF]))
        #expect(fake.sent.isEmpty)
    }

    @Test func liveReturnsSameInstanceOnRepeatedCalls() {
        let first = WatchRemote.live()
        let second = WatchRemote.live()
        #expect(first === second)
    }

    @Test func reachabilityRegainedResendsLastPublishedStatus() async {
        let fake = FakeWatchSession()
        fake.isReachable = false
        let remote = WatchRemote(session: fake)
        let status = WatchStatus(line: "NIGHT 3/8", canCapture: false)
        remote.publishStatus(status)
        #expect(fake.sent.isEmpty)

        fake.isReachable = true
        remote.sessionReachabilityDidChange(WCSession.default)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.sent.count == 1)
        let data = fake.sent.first?[WatchMessageKey.status] as? Data
        #expect(data.flatMap(WatchStatus.decode) == status)
    }
}
