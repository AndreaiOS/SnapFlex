import Testing
@testable import SnapFlexCore

@Suite struct ChromeVisibilityTests {
    @Test func hidesAfterIdleDelay() {
        let idle = ChromeVisibility.idleSeconds
        var chrome = ChromeVisibility()
        chrome.interaction(at: 10)
        chrome.tick(now: 10 + idle - 0.1)
        #expect(chrome.state == .full)
        chrome.tick(now: 10 + idle)
        #expect(chrome.state == .minimal)
    }

    @Test func interactionRevealsAndRearms() {
        let idle = ChromeVisibility.idleSeconds
        var chrome = ChromeVisibility()
        chrome.interaction(at: 0)
        chrome.tick(now: idle + 1)
        #expect(chrome.state == .minimal)
        chrome.interaction(at: idle + 2)
        #expect(chrome.state == .full)
        chrome.tick(now: idle + 2 + idle - 0.5)
        #expect(chrome.state == .full)
        chrome.tick(now: idle + 2 + idle)
        #expect(chrome.state == .minimal)
    }

    @Test func blockedPinsFull() {
        let idle = ChromeVisibility.idleSeconds
        var chrome = ChromeVisibility()
        chrome.interaction(at: 0)
        chrome.blocked = true
        chrome.tick(now: idle + 6)
        #expect(chrome.state == .full)
        chrome.blocked = false
        chrome.tick(now: idle + 6.1)   // idle window already elapsed
        #expect(chrome.state == .minimal)
    }

    @Test func unblockingWhileRecentStaysFull() {
        var chrome = ChromeVisibility(blocked: true)
        chrome.interaction(at: 0)
        chrome.blocked = false
        chrome.tick(now: 1.0)
        #expect(chrome.state == .full)
    }

    @Test func needsInteractionFalseWhenFullAndRecent() {
        var chrome = ChromeVisibility()
        chrome.interaction(at: 10)
        #expect(chrome.needsInteraction(at: 10.1) == false)
    }

    @Test func needsInteractionTrueWhenMinimal() {
        let idle = ChromeVisibility.idleSeconds
        var chrome = ChromeVisibility()
        chrome.interaction(at: 0)
        chrome.tick(now: idle + 1)
        #expect(chrome.state == .minimal)
        #expect(chrome.needsInteraction(at: idle + 1.1) == true)
    }

    @Test func needsInteractionTrueWhenInteractionStale() {
        var chrome = ChromeVisibility()
        chrome.interaction(at: 10)
        #expect(chrome.needsInteraction(at: 10.3) == true)
    }
}

@Suite struct ChromeReadoutTests {
    let auto = ManualValues(iso: nil, shutterSeconds: nil, focusPosition: nil, wbKelvin: nil, evBias: 0)

    @Test func fullyAutoReadsAUTO() {
        #expect(chromeReadout(values: auto, longMode: .off, longBlend: .nd, processing: .standard) == "AUTO")
    }

    @Test func manualAndModesJoinWithDots() {
        let values = ManualValues(iso: 200, shutterSeconds: 1.0/120, focusPosition: nil, wbKelvin: nil, evBias: 0)
        let readout = chromeReadout(values: values, longMode: .preset(seconds: 15), longBlend: .nd, processing: .max)
        #expect(readout == "ISO 200 · 1/120 · ND 15s · MAX")
    }

    @Test func bulbAndExtrasIncluded() {
        let values = ManualValues(iso: nil, shutterSeconds: nil, focusPosition: 0.4, wbKelvin: 5500, evBias: -0.7)
        let readout = chromeReadout(values: values, longMode: .bulb, longBlend: .trails, processing: .zero)
        #expect(readout == "EV -0.7 · 5500K · MF · TRAILS BULB · 0AI")
    }
}
