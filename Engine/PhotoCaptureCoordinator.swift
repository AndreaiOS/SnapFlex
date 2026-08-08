import AVFoundation
import SnapFlexCore

final class PhotoCaptureCoordinator: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: ([CaptureResource]) -> Void
    private var resources: [CaptureResource] = []

    init(completion: @escaping ([CaptureResource]) -> Void) {
        self.completion = completion
    }

    static func makeSettings(recipe: CaptureRecipe, rawType: OSType?,
                             flashOn: Bool) -> AVCapturePhotoSettings {
        let processedFormat: [String: Any]? =
            recipe.includeProcessed ? [AVVideoCodecKey: AVVideoCodecType.hevc] : nil

        let settings: AVCapturePhotoSettings
        if let bracketing = recipe.bracketing {
            let bracketed: [AVCaptureBracketedStillImageSettings]
            switch bracketing {
            case .autoExposure(let biases):
                bracketed = biases.map {
                    AVCaptureAutoExposureBracketedStillImageSettings
                        .autoExposureSettings(exposureTargetBias: $0)
                }
            case .manual(let exposures):
                bracketed = exposures.map {
                    AVCaptureManualExposureBracketedStillImageSettings
                        .manualExposureSettings(
                            exposureDuration: CMTime(seconds: $0.shutterSeconds,
                                                     preferredTimescale: 1_000_000),
                            iso: $0.iso)
                }
            }
            if let rawType {
                settings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: rawType,
                    processedFormat: processedFormat,
                    bracketedSettings: bracketed)
            } else {
                settings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: processedFormat ?? [AVVideoCodecKey: AVVideoCodecType.hevc],
                    bracketedSettings: bracketed)
            }
        } else if let rawType {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType,
                                              processedFormat: processedFormat)
        } else {
            settings = AVCapturePhotoSettings(
                format: processedFormat ?? [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        if !(settings is AVCapturePhotoBracketSettings) {
            settings.flashMode = flashOn ? .on : .off
            // Device-verified (iPhone 17 Pro, iOS 26): setting a prioritization above
            // .speed on ANY settings that include RAW throws NSInvalidArgumentException
            // ("Unsupported when capturing RAW") — companion or not. Prioritization is
            // only configurable for processed-only captures.
            if rawType == nil {
                settings.photoQualityPrioritization = switch recipe.processing {
                case .zero: .speed
                case .standard: .balanced
                case .max: .quality
                }
            } else if recipe.raw == .bayer {
                // Bayer RAW rules (AVCapturePhotoOutput.h): prioritization MUST be
                // .speed — even the default .balanced is rejected at capturePhoto.
                settings.photoQualityPrioritization = .speed
            }
            // ProRAW: leave the default untouched; elevated values throw at set time.
        }
        return settings
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        resources.append(CaptureResource(kind: photo.isRawPhoto ? .rawDNG : .processedHEIF,
                                         data: data, frameIndex: photo.sequenceCount))
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        completion(resources)
    }
}
