import Testing
@testable import SnapFlexCore

@Suite struct ProcessingLevelTests {
    @Test func cyclesInOrder() {
        #expect(ProcessingLevel.zero.next == .standard)
        #expect(ProcessingLevel.standard.next == .max)
        #expect(ProcessingLevel.max.next == .zero)
    }

    @Test func recipeCarriesProcessingLevel() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .off, heifCompanion: false),
            capabilities: DeviceCapabilities(supportsProRAW: true, supportsBayerRAW: true),
            bracketing: nil, processing: .max)
        #expect(recipe.processing == .max)
    }

    @Test func recipeDefaultsToStandard() {
        let recipe = CaptureRecipe.make(
            selection: FormatSelection(raw: .off, heifCompanion: false),
            capabilities: DeviceCapabilities(supportsProRAW: true, supportsBayerRAW: true),
            bracketing: nil)
        #expect(recipe.processing == .standard)
    }
}
