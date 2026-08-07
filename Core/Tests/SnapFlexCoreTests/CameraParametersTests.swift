import Testing
@testable import SnapFlexCore

@Suite struct CameraParametersTests {
    let wideRanges = ParameterRanges(
        iso: 32...3264, shutterSeconds: 1.0/8000...1.0,
        evBias: -8...8, zoom: 1...9)
    let uwRanges = ParameterRanges(
        iso: 21...2016, shutterSeconds: 1.0/4000...1.0/2,
        evBias: -8...8, zoom: 1...1)

    @Test func manualValuesClampIntoNewRanges() {
        let values = ManualValues(iso: 3000, shutterSeconds: 1.0, focusPosition: 0.5, wbKelvin: 5500, evBias: 0)
        let clampedValues = clamped(values, to: uwRanges)
        #expect(clampedValues.iso == 2016)
        #expect(clampedValues.shutterSeconds == 0.5)
        #expect(clampedValues.focusPosition == 0.5)   // 0...1, unaffected by lens
        #expect(clampedValues.wbKelvin == 5500)
    }

    @Test func nilValuesStayNil() {
        let values = ManualValues(iso: nil, shutterSeconds: nil, focusPosition: nil, wbKelvin: nil, evBias: 9)
        let clampedValues = clamped(values, to: wideRanges)
        #expect(clampedValues.iso == nil)
        #expect(clampedValues.shutterSeconds == nil)
        #expect(clampedValues.evBias == 8)            // bias clamps too
    }

    @Test func kelvinClampsToAppRange() {
        let values = ManualValues(iso: nil, shutterSeconds: nil, focusPosition: nil, wbKelvin: 20000, evBias: 0)
        #expect(clamped(values, to: wideRanges).wbKelvin == 8000)
    }
}
