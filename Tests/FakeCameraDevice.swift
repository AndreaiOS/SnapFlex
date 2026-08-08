import Foundation
import SnapFlexCore
@testable import SnapFlex

final class FakeCameraDevice: CameraDeviceProtocol {
    var availableLenses: [LensKind] = [.ultraWide, .wide, .telephoto]
    var activeLens: LensKind = .wide
    var rangesByLens: [LensKind: ParameterRanges] = [
        .wide: ParameterRanges(iso: 32...3264, shutterSeconds: 1.0/8000...1.0, evBias: -8...8, zoom: 1...9),
        .ultraWide: ParameterRanges(iso: 21...2016, shutterSeconds: 1.0/4000...1.0/2, evBias: -8...8, zoom: 1...1),
        .telephoto: ParameterRanges(iso: 25...2500, shutterSeconds: 1.0/8000...1.0, evBias: -8...8, zoom: 1...3),
    ]
    var ranges: ParameterRanges { rangesByLens[activeLens]! }
    var capabilities = DeviceCapabilities(supportsProRAW: true, supportsBayerRAW: true)
    var onStatusChange: ((SessionStatus) -> Void)?
    var onControlEvent: ((CameraControlEvent) -> Void)?

    // Recording
    var started = false
    var appliedExposures: [(iso: Float?, shutter: Double?, bias: Float)] = []
    var lockedFocusPositions: [Float] = []
    var autoFocusCalls = 0
    var appliedKelvins: [Int?] = []
    var capturedRecipes: [CaptureRecipe] = []
    var captureResult: [CaptureResource] = [CaptureResource(kind: .processedHEIF, data: Data([1]))]

    func start() { started = true; onStatusChange?(.running) }
    func stop() { started = false; onStatusChange?(.notRunning) }
    func switchTo(_ lens: LensKind) { activeLens = lens }
    func setExposure(iso: Float?, shutterSeconds: Double?, bias: Float) {
        appliedExposures.append((iso, shutterSeconds, bias))
    }
    func lockFocus(position: Float) { lockedFocusPositions.append(position) }
    func setAutoFocus() { autoFocusCalls += 1 }
    func setWhiteBalance(kelvin: Int?) { appliedKelvins.append(kelvin) }
    func setZoom(_ factor: Double) {}
    func capture(recipe: CaptureRecipe, flashOn: Bool,
                 completion: @escaping ([CaptureResource]) -> Void) {
        capturedRecipes.append(recipe)
        completion(captureResult)
    }
}
