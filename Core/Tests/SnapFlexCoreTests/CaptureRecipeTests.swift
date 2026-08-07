import Testing
@testable import SnapFlexCore

@Suite struct CaptureRecipeTests {
    let pro = DeviceCapabilities(supportsProRAW: true, supportsBayerRAW: true)
    let basic = DeviceCapabilities(supportsProRAW: false, supportsBayerRAW: true)
    let bracket = BracketingPlan.autoExposure(biases: [-1, 0, 1])

    @Test func proRAWOnSupportedDevice() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .proRAW, heifCompanion: true),
            capabilities: pro, bracketing: nil)
        #expect(recipe == CaptureRecipe(raw: .proRAW, includeProcessed: true, bracketing: nil))
    }

    @Test func proRAWFallsBackToBayer() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .proRAW, heifCompanion: false),
            capabilities: basic, bracketing: nil)
        #expect(recipe.raw == .bayer)
    }

    @Test func rawOffForcesProcessed() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .off, heifCompanion: false),
            capabilities: pro, bracketing: nil)
        #expect(recipe == CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: nil))
    }

    @Test func bracketingDowngradesProRAWToBayer() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .proRAW, heifCompanion: true),
            capabilities: pro, bracketing: bracket)
        #expect(recipe.raw == .bayer)
        #expect(recipe.bracketing == bracket)
    }

    @Test func bayerUnsupportedFallsBackToProcessed() {
        let none = DeviceCapabilities(supportsProRAW: false, supportsBayerRAW: false)
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .bayer, heifCompanion: false),
            capabilities: none, bracketing: nil)
        #expect(recipe == CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: nil))
    }

    @Test func proRAWUnsupportedBothFormats() {
        let none = DeviceCapabilities(supportsProRAW: false, supportsBayerRAW: false)
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .proRAW, heifCompanion: false),
            capabilities: none, bracketing: nil)
        #expect(recipe == CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: nil))
    }

    @Test func bracketingDowngradesProRAWToNoneWhenBayerUnsupported() {
        let proOnly = DeviceCapabilities(supportsProRAW: true, supportsBayerRAW: false)
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .proRAW, heifCompanion: false),
            capabilities: proOnly, bracketing: bracket)
        #expect(recipe == CaptureRecipe(raw: RAWKind.none, includeProcessed: true, bracketing: bracket))
    }
}
