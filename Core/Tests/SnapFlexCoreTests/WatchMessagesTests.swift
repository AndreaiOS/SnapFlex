import Testing
import Foundation
@testable import SnapFlexCore

@Suite struct WatchMessagesTests {
    @Test func roundTripsThroughData() {
        let status = WatchStatus(line: "NIGHT 3/8", canCapture: false)
        let restored = WatchStatus.decode(status.encoded())
        #expect(restored == status)
    }

    @Test func corruptDataYieldsNil() {
        #expect(WatchStatus.decode(Data([0x00, 0x01])) == nil)
    }
}
