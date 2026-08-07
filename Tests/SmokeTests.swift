import Testing
import SnapFlexCore

@Suite struct SmokeTests {
    @Test func coreIsLinked() {
        #expect(LensKind.wide.displayName == "1×")
    }
}
