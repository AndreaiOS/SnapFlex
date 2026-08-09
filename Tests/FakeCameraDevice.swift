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
    var lockCalls = 0
    var unlockCalls = 0
    var capturedRecipes: [CaptureRecipe] = []
    var captureResult: [CaptureResource] = [CaptureResource(kind: .processedHEIF, data: Data([1]))]
    /// When set, returned as a `.processedHEIF` resource for every capture instead of
    /// `captureResult` — used by night-stack tests to feed real decodable HEIF fixtures.
    var stubbedCaptureData: Data?
    /// When set (and non-empty), takes priority over `stubbedCaptureData`: cycles through
    /// these by capture index (wrapping), so night-stack averaging tests can feed varying
    /// per-frame data and actually distinguish "averaged" from "passed through last frame".
    var stubbedCaptureDataSequence: [Data]?
    var captureCallCount = 0
    /// 0-based capture index at which to simulate a resource-less failure (empty resources),
    /// exercising night-stack's mid-sequence abort path. nil = never fail.
    var failCaptureAtIndex: Int?

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
    func lockAutoExposure() { lockCalls += 1 }
    func unlockAutoExposure() { unlockCalls += 1 }
    func capture(recipe: CaptureRecipe, flashOn: Bool,
                 completion: @escaping ([CaptureResource]) -> Void) {
        capturedRecipes.append(recipe)
        let index = captureCallCount
        captureCallCount += 1
        if index == failCaptureAtIndex {
            completion([])
            return
        }
        if let sequence = stubbedCaptureDataSequence, !sequence.isEmpty {
            let data = sequence[index % sequence.count]
            completion([CaptureResource(kind: .processedHEIF, data: data, frameIndex: index)])
        } else if let stubbedCaptureData {
            completion([CaptureResource(kind: .processedHEIF, data: stubbedCaptureData, frameIndex: index)])
        } else {
            completion(captureResult)
        }
    }
}
