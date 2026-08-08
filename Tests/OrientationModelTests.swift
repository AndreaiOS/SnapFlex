import Testing
import UIKit
@testable import SnapFlex

@MainActor @Suite struct OrientationModelTests {
    @Test func mapsDeviceOrientationToUIAngle() {
        let model = OrientationModel()
        model.update(.landscapeLeft)
        #expect(model.uiAngle == 90)
        model.update(.landscapeRight)
        #expect(model.uiAngle == -90)
        model.update(.portraitUpsideDown)
        #expect(model.uiAngle == 180)
        model.update(.portrait)
        #expect(model.uiAngle == 0)
    }

    @Test func ambiguousOrientationsKeepLastAngle() {
        let model = OrientationModel()
        model.update(.landscapeLeft)
        model.update(.faceUp)
        #expect(model.uiAngle == 90)
        model.update(.unknown)
        #expect(model.uiAngle == 90)
    }
}
