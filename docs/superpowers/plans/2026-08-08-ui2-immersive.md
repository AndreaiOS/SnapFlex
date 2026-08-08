# UI 2.0 "Immersive" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-hiding chrome (2s idle → minimal HUD, bouncy reveal) plus a unified animation language (springs, numeric morphs, dial detents with haptics, shutter/thumbnail pops, sliding selection capsule) across the whole viewfinder, with Reduce Motion fallbacks.

**Architecture:** `ChromeVisibility` state machine + readout-summary builder in SnapFlexCore (pure, tested); `Haptics` helper + animation constants in Theme; ViewfinderScreen drives visibility from a timer and interaction hooks; per-view animation adoption.

**Spec:** `docs/superpowers/specs/2026-08-08-ui2-immersive-design.md`

## Global Constraints

- Idle delay exactly **2.0s**; chrome NEVER hides while: dial open, LONG exposing, countdown active, permission/interruption overlay up.
- Minimal state keeps: shutter (54pt), top-center readout pill (non-auto values + active modes, `·` separated; fully-auto → `AUTO`), grid/level if enabled (shooting aids, not chrome).
- Reveal triggers: any tap/drag, dial open, Camera Control event, capture, status change.
- Springs: standard `.spring(response: 0.35, dampingFraction: 0.75)`; bouncy `.spring(response: 0.4, dampingFraction: 0.6)` — centralized in Theme.
- Haptics via one `Haptics` enum: light (dial detent, chip cycle), selection (tile select), medium (capture), success (LONG complete).
- Reduce Motion: crossfades replace springs; auto-hide timing unchanged.
- Test commands as usual (Core swift test; app xcodebuild ... OS=18.6 -quiet). xcodegen after new files.

---

### Task 1: Core — ChromeVisibility state machine + readout builder

**Files:**
- Create: `Core/Sources/SnapFlexCore/ChromeVisibility.swift`
- Test: `Core/Tests/SnapFlexCoreTests/ChromeVisibilityTests.swift`

**Interfaces:**

```swift
public struct ChromeVisibility: Equatable, Sendable {
    public enum State: Equatable, Sendable { case full, minimal }
    public static let idleSeconds: Double = 2.0

    public private(set) var state: State = .full
    /// Conditions that pin the chrome to .full (dial open, exposing, countdown, overlay).
    public var blocked: Bool { didSet /* if blocked { reveal-at(lastInteraction) semantics: state = .full } */ }
    public init(blocked: Bool = false)

    /// User interacted now: state = .full, idle clock restarts.
    public mutating func interaction(at time: Double)
    /// Clock tick: hides when now - lastInteraction >= idleSeconds, unless blocked.
    public mutating func tick(now: Double)
}

/// "ISO 200 · 1/120 · ND 15s" summary for the minimal readout pill.
public func chromeReadout(values: ManualValues, longMode: LongMode, longBlend: LongBlend,
                          processing: ProcessingLevel) -> String
```

- Readout rules: include `ISO <v>` if manual, shutter (Format-style string: the function takes preformatted shutter? NO — keep pure: format inside with the 1/N vs X.Xs rule copied) if manual, `EV +x.x` if non-zero, `<kelvin>K` if manual WB, `MF` if manual focus, `<blend> <mode-suffix>` when longMode ≠ .off (e.g. "ND 15s", "TRAILS BULB"), `0AI`/`MAX` when processing ≠ .standard. Join with `" · "`. Empty → `"AUTO"`.

- [ ] **Step 1: Failing tests**

```swift
// Core/Tests/SnapFlexCoreTests/ChromeVisibilityTests.swift
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
```

- [ ] **Step 2:** RED. **Step 3:** implement (ChromeVisibility keeps `lastInteraction: Double`; `blocked = true` forces `.full` immediately; readout order fixed: ISO, shutter, EV, WB, MF, LONG, PROC; shutter formatting rule: `seconds >= 0.35 ? "%.1fs" : "1/<round>"`; LONG suffix: preset → "\(blend.rawValue) \(seconds)s", bulb → "\(blend.rawValue) BULB"). **Step 4:** GREEN. **Step 5: Commit** — `feat(core): add chrome visibility state machine and readout builder`

---

### Task 2: Theme animation constants + Haptics helper

**Files:**
- Create: `App/Haptics.swift`
- Modify: `App/Theme.swift`

**Interfaces:**

```swift
// Theme additions
extension Theme {
    static let springStandard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy: Animation = .spring(response: 0.4, dampingFraction: 0.6)
    /// Respect Reduce Motion: crossfade instead of spring.
    static func motion(_ spring: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.2) : spring
    }
}

// App/Haptics.swift
enum Haptics {
    static func light()      // UIImpactFeedbackGenerator(style: .light)
    static func selection()  // UISelectionFeedbackGenerator
    static func medium()     // UIImpactFeedbackGenerator(style: .medium)
    static func success()    // UINotificationFeedbackGenerator .success
}
```

- Build-verified. Commit — `feat(ui): add animation constants and haptics helper`

---

### Task 3: Auto-hide chrome integration

**Files:**
- Modify: `App/ViewfinderScreen.swift`

**Authoritative behavior:**
- `@State private var chrome = ChromeVisibility()`; a 0.5s `Task` loop calls `chrome.tick(now:)` using `Date().timeIntervalSinceReferenceDate` (started onAppear, cancelled onDisappear).
- `blocked` recomputed via `.onChange` of: `selected != nil` (dial open), `isLongExposing`, `countdown != nil`, `engine.status == .interrupted` → `chrome.blocked = <OR of all>`.
- `interaction()` called (with current time) from: a `simultaneousGesture(TapGesture...)` + `DragGesture(minimumDistance: 0)` on the root ZStack (careful: must not swallow buttons — use `.simultaneousGesture`), tile selection, chip taps happen inside TopBar (they bubble via the root simultaneous gesture — sufficient), Camera Control events (`.onChange(of: engine.values)` as proxy — any value change reveals), capture (takePhoto start).
- Rendering: when `chrome.state == .minimal` (and not blocked): TopBar+histogram row and the dial+ParameterBar Group and thumbnail+lens chips get `.opacity(0)` + `.allowsHitTesting(false)` via a transition using `Theme.motion(Theme.springStandard)`; the shutter shrinks to 54pt (`scaleEffect` or frame swap with `Theme.motion(Theme.springBouncy)` on reveal); a top-center readout pill appears: `Text(chromeReadout(values: engine.values, longMode: engine.longMode, longBlend: engine.longBlend, processing: engine.processingLevel))` in `Theme.valueFont(11)`, chrome-styled capsule, `.transition(.opacity)`. Grid/level overlay unaffected.
- Withdraw `withAnimation(Theme.motion(...))` around state flips so hide is soft-spring and reveal is bouncy.

- Build-verified (state machine already unit-tested in Core). Full suite green. Commit — `feat(ui): auto-hide chrome with minimal readout HUD`

---

### Task 4: Animation language adoption

**Files:**
- Modify: `App/ParameterBar.swift`, `App/ParameterDial.swift`, `App/ViewfinderScreen.swift`, `App/TopBar.swift`, `App/LongExposureHUD.swift`

**Authoritative behavior (each item independent, apply all):**
1. **Numeric morphs:** parameter tile value Texts and TopBar chip labels get `.contentTransition(.numericText())` + `.animation(Theme.motion(Theme.springStandard), value: <the string>)`.
2. **Selection capsule:** ParameterBar highlights the selected tile with a single capsule that slides between tiles — `@Namespace private var selectionNS` + `matchedGeometryEffect(id: "tile-selection", in: selectionNS)` on the background capsule (rendered only for the selected tile), animated with `Theme.motion(Theme.springStandard)`. Tile selection fires `Haptics.selection()`.
3. **Dial detents + momentum:** in ParameterDial — on drag end, compute a decay: launch a `Task` applying exponential deceleration to the last drag velocity (`value.velocity` of DragGesture on iOS 17+ or track manually from translation deltas), stepping the normalized position until speed < threshold, then SNAP to the nearest detent: ISO full stops [25,50,100,200,400,800,1600,3200] ∩ range, shutter stops (the RealCameraDevice.shutterStops list ∩ range), EV 0.1 steps, WB 100K steps, focus continuous (no snap). Each detent crossing during drag/decay fires `Haptics.light()` (compare detent index between updates). Cancel the decay task on new drag.
4. **Shutter feedback:** shutter button gets press-scale (`.scaleEffect(pressed ? 0.9 : 1)` via a ButtonStyle with `Theme.motion(Theme.springBouncy)`); capture fires `Haptics.medium()`; LONG completion (onFinished with data) fires `Haptics.success()`.
5. **Thumbnail pop:** when `lastThumbnail` changes, animate in from `scaleEffect(0.6)` with `Theme.springBouncy` (`.transition(.scale(scale: 0.6).combined(with: .opacity))` keyed by an incrementing capture counter id).
6. **Chip cycling haptic:** TopBar `chip(_:action:)` wraps the action to also call `Haptics.light()`.
7. **LONG morph:** when an exposure starts, the shutter's white fill crossfades to a ring-only look (`Theme.motion` animated) — implement as opacity swap between the filled Circle and a stroked Circle inside the existing shutter ZStack, driven by `isLongExposing`.

- Build-verified; full suite green. Commit — `feat(ui): adopt springs, haptics, detents and morphs across the viewfinder`

---

### Task 5: Sweep + README QA

- Both suites green (expect Core 38, app 40). Append to README QA:

```markdown
- [ ] Chrome fades out after 2s idle; tap reveals with a bounce
- [ ] Chrome never hides while dial open, LONG running, or countdown active
- [ ] Minimal HUD readout matches active settings (e.g. "ISO 200 · 1/120 · ND 15s")
- [ ] Dial has momentum and snaps to stops with tick haptics
- [ ] Values morph digits; selection capsule slides between tiles
- [ ] Shutter press bounces; capture and LONG-complete haptics fire
- [ ] Reduce Motion ON: crossfades instead of springs, auto-hide still works
```

- Commit — `docs: add UI 2.0 QA checklist`

---

## Self-Review Notes

- Spec coverage: chrome states+delay+triggers+blockers (T1/T3), minimal HUD contents (T1 readout + T3 pill), animation language items (T4 maps 1:1 to the spec's list), haptics set (T2/T4), Reduce Motion (T2 `motion()` used everywhere), grid/level exemption (T3). 
- Type consistency: ChromeVisibility/chromeReadout defined once in Core (T1), consumed in T3; Theme.motion/springs defined T2, used T3/T4; Haptics defined T2, used T4.
- Known risk: dial momentum (T4.3) is the most intricate item — if DragGesture velocity is unavailable, manual delta tracking is the fallback; reviewer should scrutinize the decay loop for main-actor safety and cancellation.
