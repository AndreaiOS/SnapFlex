# UI 3.0 "Strumento" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument-panel chrome per the approved mockup A: segmented rail + statusline top deck, tick-ruler dial, shutter EV arc.

**Architecture:** Pure view-layer restyle over the existing engine. TopBar.swift is rewritten around a segmented rail; ParameterDial.swift keeps its full gesture/momentum/detent engine and swaps only its visual layer; ViewfinderScreen.swift gains the EV arc. Core gains one pure helper for rail short-labels.

**Tech Stack:** existing (SwiftUI, SnapFlexCore). **Spec:** `docs/superpowers/specs/2026-08-09-ui3-strumento-design.md`

## Global Constraints

- Identity tokens: accent #4ADE80 (`Theme.accent`), mono via `Theme.valueFont`, deep black grounds. No new colors except spec-stated opacities.
- Every animation through `Theme.motion(...)` (Reduce Motion); haptics via the existing `Haptics` helper; per-item rotation via `rotatesWithDevice(rotation)` on cell/tile CONTENT.
- Do not touch the dial's gesture/momentum/detent/NaN-guard logic — visual layer only.
- Auto-hide behavior unchanged: the new top deck replaces the old bar inside the SAME chrome group (opacity/scale/hit-testing modifiers stay as they are in ViewfinderScreen).
- Existing actions must be preserved exactly: cycle functions, assist menu contents, settings persistence hooks.
- Test commands: `cd Core && swift test`; `xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet`. Run from the repo at `/Users/andreamurru/SnapFlexBuild`. SourceKit "No such module" diagnostics are spurious — ignore.

---

### Task 1: Core — rail short-label helpers

**Files:**
- Create: `Core/Sources/SnapFlexCore/RailLabels.swift`
- Test: `Core/Tests/SnapFlexCoreTests/RailLabelsTests.swift`

**Interfaces (produces, used verbatim by Task 2):**

```swift
public enum RailLabels {
    /// "—" when off, "3s"/"10s" when set
    public static func timer(_ seconds: Int) -> String
    /// "—" when nil, "BKT 3"/"BKT 5"
    public static func bracket(_ count: Int?) -> String
    /// Short LONG label: "—" for .off, "15s" for presets, "BULB" for bulb
    public static func long(_ mode: LongMode) -> String
    /// Pipeline summary for the statusline, e.g. "RAW+HEIF · STD", "HEIF · MAX"
    public static func pipeline(raw: RAWMode, heifCompanion: Bool, processing: ProcessingLevel) -> String
}
```

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import SnapFlexCore

@Suite struct RailLabelsTests {
    @Test func timerLabels() {
        #expect(RailLabels.timer(0) == "—")
        #expect(RailLabels.timer(3) == "3s")
        #expect(RailLabels.timer(10) == "10s")
    }
    @Test func bracketLabels() {
        #expect(RailLabels.bracket(nil) == "—")
        #expect(RailLabels.bracket(3) == "BKT 3")
    }
    @Test func longLabels() {
        #expect(RailLabels.long(.off) == "—")
        #expect(RailLabels.long(.preset(seconds: 15)) == "15s")
        #expect(RailLabels.long(.bulb) == "BULB")
    }
    @Test func pipelineSummary() {
        #expect(RailLabels.pipeline(raw: .bayer, heifCompanion: true, processing: .standard) == "RAW+HEIF · STD")
        #expect(RailLabels.pipeline(raw: .off, heifCompanion: true, processing: .max) == "HEIF · MAX")
        #expect(RailLabels.pipeline(raw: .proRAW, heifCompanion: false, processing: .zero) == "ProRAW · 0AI")
    }
}
```

Rule for pipeline: `raw.rawValue`, plus `+HEIF` only when raw ≠ .off AND heifCompanion; then ` · ` + processing.rawValue.

- [ ] **Step 2:** `cd Core && swift test` → RED. **Step 3:** implement. **Step 4:** GREEN (all suites). **Step 5: Commit** `feat(core): rail short-label helpers`

---

### Task 2: Top deck — segmented rail + statusline (TopBar rewrite)

**Files:**
- Modify: `App/TopBar.swift`

**Interfaces:** consumes `RailLabels` (Task 1). TopBar's public init signature and bindings stay EXACTLY as today (engine, aspect, timerDuration, showGrid, showLevel, rotation, longAvailable) — ViewfinderScreen must not change for this task.

**Authoritative behavior:**
- Body = VStack(spacing: 8): statusline row, then the rail. Container padding `.horizontal 14 / .top 14 / .bottom 10`, background `LinearGradient(black.opacity(0.92) → black.opacity(0.78), top→bottom)`, `overlay(alignment: .bottom)` 1pt `Theme.accent.opacity(0.18)` line.
- Statusline: HStack, 8.5pt `Theme.valueFont`, tracking via `.tracking(1.2)`. Left: `Text(RailLabels.pipeline(...))`, `foregroundStyle` accent when `engine.formatSelection.raw != .off` else `white.opacity(0.42)`. Spacer. Right: battery `Text("BAT \(Int(level*100))")` in `white.opacity(0.42))` shown only when level ≥ 0 (enable `UIDevice.current.isBatteryMonitoringEnabled = true` in `onAppear`; read `UIDevice.current.batteryLevel`; refresh on `UIDevice.batteryLevelDidChangeNotification` via `.onReceive`), then the existing `assistMenu` (unchanged contents) sized down: icon `.font(.system(size: 14))`.
- Rail: HStack(spacing: 1) inside `RoundedRectangle(cornerRadius: 8)` clip with `overlay` 1pt stroke `white.opacity(0.14)`. Cells: `railCell(label:value:active:action:)` — a Button; VStack(spacing: 2): micro-label 7pt `Theme.valueFont`, `.tracking(1.4)`, `white.opacity(0.38)`; value 10pt `Theme.valueFont`, accent when active else `white.opacity(0.8)`; `.frame(maxWidth: .infinity)`, `.padding(.vertical, 7)`, background `Theme.accent.opacity(0.10)` when active else `white.opacity(0.05)`; when active add `overlay(alignment: .bottom)` of a 2pt accent bar `.padding(.horizontal, <18% of width via GeometryReader-free approximation: .padding(.horizontal, 12)>)`. Cell CONTENT gets `rotatesWithDevice(rotation)`; `.contentTransition(.numericText())` + `.animation(Theme.motion(Theme.springStandard), value: value)` on the value Text. Action wraps `Haptics.light()` exactly like today's `chip`.
- Cells in order with today's exact cycle actions: FMT (`engine.formatSelection.raw.rawValue`, active raw ≠ .off, action cycleFormat), PROC (value `engine.processingLevel.rawValue`, active `processingLevel != .standard`, action next), FLASH (value `engine.flashOn ? "ON" : "—"`, active flashOn), TIMER (`RailLabels.timer(timerDuration)`, active > 0), BKT (`RailLabels.bracket(engine.bracketCount)`, active non-nil), LONG when `longAvailable` (`RailLabels.long(engine.longMode)`, active ≠ .off), BLEND when `engine.longMode != .off` (`engine.longBlend.rawValue`, active true).
- ASPECT cell: aspect moves into the rail? NO — aspect stays out of the rail (7 cells max with blend). Aspect moves into the assist menu as a `Picker("Aspect", selection: $aspect)` with the three cases (menu already has toggles; add the picker at the top). Delete the old aspect chip.

- [ ] **Step 1:** implement. **Step 2:** app suite green. **Step 3: Commit** `feat(ui): instrument top deck with segmented rail and statusline`

---

### Task 3: Tick-ruler dial (ParameterDial visual layer)

**Files:**
- Modify: `App/ParameterDial.swift`

**Authoritative behavior (visual only — gesture/momentum/detent code untouched):**
- Replace the current dial track visuals with: ZStack(alignment: .top) of (a) tick strip, (b) fixed center needle, (c) value label.
- Tick strip: `Canvas` (or an HStack of ticks inside a `GeometryReader`) height 26, drawing 1pt vertical lines `white.opacity(0.28)` every 8pt across 3× the visible width, with `.offset(x:)` proportional to the CURRENT normalized value: `offset = -(normalized - 0.5) * stripWidth` where stripWidth = 2× visible width (ticks scroll left as value increases). Mask: `LinearGradient` alpha mask transparent→opaque at 18%→opaque at 82%→transparent.
- Needle: `Rectangle` 2×32pt `Theme.accent`, `.shadow(color: Theme.accent.opacity(0.8), radius: 8)`, centered, extending 3pt above the strip.
- Value label: the existing formatted current-value string, 9pt `Theme.valueFont`, accent, `.contentTransition(.numericText())` + `.animation(Theme.motion(Theme.springStandard), value: <string>)`, positioned 16pt above the needle.
- Keep any existing close/cancel affordances and paddings so ViewfinderScreen layout is unaffected. Reduce Motion: needle glow shadow radius drops to 0 (`Theme.motion` handles animations; for the static shadow use `UIAccessibility.isReduceMotionEnabled ? 0 : 8` is NOT needed — keep the shadow, it is static).
- The ruler must read the same normalized position the gesture engine already maintains — reuse the existing state variable; do NOT introduce a second source of truth.

- [ ] **Step 1:** implement. **Step 2:** app suite green (dial logic tests unchanged). **Step 3: Commit** `feat(ui): tick-ruler dial with fixed needle`

---

### Task 4: Shutter EV arc + sweep + README QA

**Files:**
- Modify: `App/ViewfinderScreen.swift`, `README.md`

**Authoritative behavior:**
- In the shutter ZStack (around the existing circles), add: `Circle().trim(from: 0, to: CGFloat(abs(evFraction) / 2)).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90)).scaleEffect(x: evFraction < 0 ? -1 : 1)` framed 18pt larger than the shutter (80×80), where `evFraction = Double(engine.values.evBias) / max(engine.ranges.evBias.upperBound, 1)` clamped to -1...1. Positive sweeps clockwise from 12 o'clock, negative mirrors counter-clockwise. `.animation(Theme.motion(Theme.springStandard), value: engine.values.evBias)`.
- Label: when `engine.values.evBias != 0`, `Text(String(format: "EV %+.1f", engine.values.evBias))` 7.5pt `Theme.valueFont` accent `.tracking(0.9)`, offset y -52 from shutter center, `.transition(.opacity)`.
- Arc and label hide with chrome (`opacity(chromeHidden ? 0 : 1)` with the existing direction-aware animation) — the shutter itself keeps current behavior.
- README QA additions:

```markdown
- [ ] Segmented rail legible over bright scenes; active cells green with underline
- [ ] Statusline shows pipeline summary and battery; assist menu opens from top-right
- [ ] Ruler ticks scroll under the fixed needle and settle on detents
- [ ] EV arc sweeps clockwise for +, mirrored for −; label appears only when EV ≠ 0
```

- [ ] **Step 1:** implement. **Step 2:** full sweep both suites green. **Step 3: Commit** `feat(ui): shutter EV arc and UI 3.0 QA notes`

---

## Self-Review Notes

- Spec coverage: rail+cells+active state (T2), statusline+battery+menu (T2), top deck container (T2), tick ruler+needle+value (T3), EV arc+label (T4), Core helpers (T1), QA (T4). Aspect relocation to assist menu decided in T2 (rail stays ≤7 cells).
- Type consistency: RailLabels API defined once (T1) and consumed with exact signatures (T2). No cross-task type invention.
- Risk: T3 must not touch gesture code — reviewer should diff-check that momentum/detent functions are byte-identical.
