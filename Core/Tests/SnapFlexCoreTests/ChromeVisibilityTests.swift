import Testing
@testable import SnapFlexCore

@Suite struct ChromeVisibilityTests {
    @Test func hidesAfterIdleDelay() {
        var chrome = ChromeVisibility()
        chrome.interaction(at: 10)
        chrome.tick(now: 11.9)
        #expect(chrome.state == .full)
        chrome.tick(now: 12.0)
        #expect(chrome.state == .minimal)
    }

    @Test func interactionRevealsAndRearms() {
        var chrome = ChromeVisibility()
        chrome.interaction(at: 0)
        chrome.tick(now: 5)
        #expect(chrome.state == .minimal)
        chrome.interaction(at: 6)
        #expect(chrome.state == .full)
        chrome.tick(now: 7.5)
        #expect(chrome.state == .full)
        chrome.tick(now: 8.0)
        #expect(chrome.state == .minimal)
    }

    @Test func blockedPinsFull() {
        var chrome = ChromeVisibility()
        chrome.interaction(at: 0)
        chrome.blocked = true
        chrome.tick(now: 10)
        #expect(chrome.state == .full)
        chrome.blocked = false
        chrome.tick(now: 10.1)   // idle window already elapsed
        #expect(chrome.state == .minimal)
    }

    @Test func unblockingWhileRecentStaysFull() {
        var chrome = ChromeVisibility(blocked: true)
        chrome.interaction(at: 0)
        chrome.blocked = false
        chrome.tick(now: 1.0)
        #expect(chrome.state == .full)
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
