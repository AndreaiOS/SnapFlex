import Testing
import AVFoundation
import SnapFlexCore
@testable import SnapFlex

@Suite struct PhotoCaptureCoordinatorTests {
    @Test func processedOnlyRecipeMakesHEVCSettings() {
        let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: nil)
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        #expect(settings.format?[AVVideoCodecKey] as? String == AVVideoCodecType.hevc.rawValue)
        #expect(settings.flashMode == .off)
    }

    @Test func flashOnPropagates() {
        let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: nil)
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: true)
        #expect(settings.flashMode == .on)
    }

    @Test func autoBracketedRecipeMakesBracketSettings() {
        let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true,
                                   bracketing: .autoExposure(biases: [-1, 0, 1]))
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        guard let bracket = settings as? AVCapturePhotoBracketSettings else {
            Issue.record("expected AVCapturePhotoBracketSettings"); return
        }
        #expect(bracket.bracketedSettings.count == 3)
    }

    @Test func manualBracketedRecipeMakesManualSettings() {
        let recipe = CaptureRecipe(
            raw: RAWKind.none, includeProcessed: true,
            bracketing: .manual(exposures: [
                ManualBracketExposure(iso: 100, shutterSeconds: 1.0/240),
                ManualBracketExposure(iso: 100, shutterSeconds: 1.0/120),
                ManualBracketExposure(iso: 100, shutterSeconds: 1.0/60),
            ]))
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        guard let bracket = settings as? AVCapturePhotoBracketSettings else {
            Issue.record("expected AVCapturePhotoBracketSettings"); return
        }
        #expect(bracket.bracketedSettings.allSatisfy {
            $0 is AVCaptureManualExposureBracketedStillImageSettings
        })
    }

    @Test func processingLevelMapsToPrioritization() {
        for (level, expected): (ProcessingLevel, AVCapturePhotoOutput.QualityPrioritization) in
            [(.zero, .speed), (.standard, .balanced), (.max, .quality)] {
            let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true,
                                       bracketing: nil, processing: level)
            let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
            #expect(settings.photoQualityPrioritization == expected)
        }
    }

    @Test func prioritizationAppliesWheneverSettingsHaveNoRAW() {
        // The gate is on rawType, not on the recipe: with no RAW in the settings,
        // prioritization applies even if the recipe originally wanted RAW (e.g. the
        // device offers no RAW format). RAW settings throwing on-device is covered
        // by DeviceSettingsReproTests, which needs a physical camera.
        let recipe = CaptureRecipe(raw: RAWKind.bayer, includeProcessed: false,
                                   bracketing: nil, processing: .max)
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        #expect(settings.photoQualityPrioritization == .quality)
    }

    @Test func bracketSettingsSkipPrioritization() {
        let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true,
                                   bracketing: .autoExposure(biases: [-1, 0, 1]), processing: .max)
        let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        #expect(settings.photoQualityPrioritization == .speed)
    }
}
