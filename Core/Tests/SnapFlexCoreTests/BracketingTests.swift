// Core/Tests/SnapFlexCoreTests/BracketingTests.swift
import Testing
@testable import SnapFlexCore

@Suite struct BracketingTests {
    let ranges = ParameterRanges(iso: 32...3264, shutterSeconds: 1.0/8000...1.0,
                                 evBias: -8...8, zoom: 1...9)

    @Test func autoThreeShotPlan() {
        let plan = BracketingPlan.make(count: 3, stepEV: 1.0, base: .auto, ranges: ranges)
        #expect(plan == .autoExposure(biases: [-1.0, 0.0, 1.0]))
    }

    @Test func autoFiveShotClampsBiases() {
        let plan = BracketingPlan.make(count: 5, stepEV: 5.0, base: .auto, ranges: ranges)
        #expect(plan == .autoExposure(biases: [-8.0, -5.0, 0.0, 5.0, 8.0]))
    }

    @Test func manualPlanVariesShutter() {
        let plan = BracketingPlan.make(count: 3, stepEV: 1.0,
                                       base: .manual(iso: 100, shutterSeconds: 1.0/120),
                                       ranges: ranges)
        guard case .manual(let exposures) = plan else { Issue.record("expected manual"); return }
        #expect(exposures.count == 3)
        #expect(exposures[0].iso == 100)
        #expect(exposures[0].shutterSeconds == 1.0/240)
        #expect(exposures[1].iso == 100)
        #expect(exposures[1].shutterSeconds == 1.0/120)
        #expect(exposures[2].iso == 100)
        #expect(exposures[2].shutterSeconds == 1.0/60)
    }

    @Test func manualPlanClampsShutterToRange() {
        let plan = BracketingPlan.make(count: 3, stepEV: 2.0,
                                       base: .manual(iso: 100, shutterSeconds: 1.0/2),
                                       ranges: ranges)
        guard case .manual(let exposures) = plan else { Issue.record("expected manual"); return }
        #expect(exposures.last?.shutterSeconds == 1.0)   // 2.0s clamped to 1.0s max
    }
}
