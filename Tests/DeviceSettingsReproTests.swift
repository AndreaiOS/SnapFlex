// On-device diagnostic: builds capture settings for every format combination
// exactly like the capture path does. AVFoundation validates several setters
// only on real hardware (e.g. photoQualityPrioritization throws on RAW), so run
// this on a physical device after any capture-path change:
//   xcodebuild test -destination 'platform=iOS,id=<udid>' \
//     -only-testing:SnapFlexTests/DeviceSettingsReproTests
// In the simulator it skips (no camera). The last "COMBO" line printed before a
// crash identifies the throwing combination.
import Testing
import AVFoundation
@testable import SnapFlex
import SnapFlexCore

@Suite struct DeviceSettingsReproTests {
    @Test func allSettingsCombos() throws {
        let session = AVCaptureSession()
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("COMBO: no camera (simulator?) — skipping")
            return
        }
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.maxPhotoQualityPrioritization = .quality
        if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = true }
        session.commitConfiguration()

        print("COMBO: available RAW formats: \(output.availableRawPhotoPixelFormatTypes)")
        let bayer = output.availableRawPhotoPixelFormatTypes
            .first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let proRAW = output.availableRawPhotoPixelFormatTypes
            .first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        print("COMBO: bayer=\(String(describing: bayer)) proRAW=\(String(describing: proRAW))")

        let rawKinds: [(String, RAWKind, OSType?)] = [
            ("bayer", .bayer, bayer), ("proRAW", .proRAW, proRAW), ("none", RAWKind.none, nil)]
        for (name, kind, rawType) in rawKinds {
            for includeProcessed in [true, false] {
                for flashOn in [false, true] {
                    for processing in ProcessingLevel.allCases {
                        print("COMBO: raw=\(name) processed=\(includeProcessed) flash=\(flashOn) proc=\(processing.rawValue)")
                        let recipe = CaptureRecipe(raw: kind, includeProcessed: includeProcessed,
                                                   bracketing: nil, processing: processing)
                        let settings = PhotoCaptureCoordinator.makeSettings(
                            recipe: recipe, rawType: rawType, flashOn: flashOn)
                        _ = settings
                    }
                }
            }
        }
        print("COMBO: ALL PASSED")
    }
}
