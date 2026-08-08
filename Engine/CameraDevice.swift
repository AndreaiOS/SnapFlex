import Foundation
import SnapFlexCore

enum SessionStatus: Equatable {
    case notRunning, running, interrupted, denied
}

struct CaptureResource: Equatable {
    enum Kind: Equatable { case rawDNG, processedHEIF }
    let kind: Kind
    let data: Data
    let frameIndex: Int

    init(kind: Kind, data: Data, frameIndex: Int = 0) {
        self.kind = kind
        self.data = data
        self.frameIndex = frameIndex
    }
}

protocol CameraDeviceProtocol: AnyObject {
    var availableLenses: [LensKind] { get }
    var activeLens: LensKind { get }
    var ranges: ParameterRanges { get }
    var capabilities: DeviceCapabilities { get }
    var onStatusChange: ((SessionStatus) -> Void)? { get set }
    func start()
    func stop()
    func switchTo(_ lens: LensKind)
    func setExposure(iso: Float?, shutterSeconds: Double?, bias: Float)
    func lockFocus(position: Float)
    func setAutoFocus()
    func setWhiteBalance(kelvin: Int?)
    func setZoom(_ factor: Double)
    func capture(recipe: CaptureRecipe, flashOn: Bool,
                 completion: @escaping ([CaptureResource]) -> Void)
}
