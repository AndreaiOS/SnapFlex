# NIGHT Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NIGHT ×8 mode — 8 locked-exposure 0AI stills averaged into one clean HEIF, no AI.

**Architecture:** Pure `NightAccumulator` in Core (UInt16 sums); `CameraEngine.captureNightStack` orchestrates sequential captures + ImageIO decode/encode in Engine; NIGHT rail cell + progress pill + mutual exclusions in the app layer.

**Tech Stack:** existing + ImageIO/CoreGraphics (Engine). **Spec:** `docs/superpowers/specs/2026-08-09-night-stack-design.md`

## Global Constraints

- Stack recipe forced: `raw: .none, includeProcessed: true, processing: .zero`, flash off, bracketing nil.
- Mutual exclusion: NIGHT on ⇒ LONG off + BKT nil; LONG or BKT engaged ⇒ NIGHT off.
- Peak memory ≈ accumulator (w·h·4·2 bytes) + one decoded frame (w·h·4). Frames decoded one at a time, released before next capture completes processing.
- Abort semantics: any failed/mismatched frame aborts the whole stack; nothing partial is saved.
- Test commands from `/Users/andreamurru/SnapFlexBuild`: `cd Core && swift test` (49 + new); `xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'` (47 + new; FOREGROUND, BLOCKED if hung >10min). Ignore SourceKit noise.

---

### Task 1: Core — NightAccumulator

**Files:**
- Create: `Core/Sources/SnapFlexCore/NightStack.swift`
- Test: `Core/Tests/SnapFlexCoreTests/NightStackTests.swift`

**Interfaces (produces, consumed verbatim by Task 2):**

```swift
public enum NightStack {
    public static let frameCount = 8
}

public struct NightAccumulator {
    public private(set) var framesAdded: Int
    public let pixelCount: Int   // bytes = pixelCount (RGBA8 length)
    public init(byteCount: Int)  // allocates UInt16 sums of that length, framesAdded = 0
    /// Adds an RGBA8 frame. Returns false (and adds nothing) if frame.count != byteCount.
    public mutating func add(frame: [UInt8]) -> Bool
    /// Integer-mean of added frames; nil if framesAdded == 0.
    public func average() -> [UInt8]?
}
```

Implementation note: `add` loops with `withUnsafeBufferPointer` accumulating into the `[UInt16]` sums (simple indexed loop — the optimizer vectorizes it; no Accelerate dependency in Core). `average()` divides by `framesAdded` with integer rounding (`(sum + n/2) / n`).

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import SnapFlexCore

@Suite struct NightStackTests {
    @Test func averagesTwoFrames() {
        var acc = NightAccumulator(byteCount: 4)
        #expect(acc.add(frame: [0, 100, 200, 255]))
        #expect(acc.add(frame: [10, 120, 250, 255]))
        #expect(acc.framesAdded == 2)
        #expect(acc.average() == [5, 110, 225, 255])
    }

    @Test func rejectsMismatchedLength() {
        var acc = NightAccumulator(byteCount: 4)
        #expect(acc.add(frame: [1, 2]) == false)
        #expect(acc.framesAdded == 0)
    }

    @Test func emptyAverageIsNil() {
        #expect(NightAccumulator(byteCount: 4).average() == nil)
    }

    @Test func roundsAverage() {
        var acc = NightAccumulator(byteCount: 1)
        _ = acc.add(frame: [1])
        _ = acc.add(frame: [2])
        #expect(acc.average() == [2])   // (3 + 1) / 2 rounds to 2
    }
}
```

- [ ] **Step 2:** RED. **Step 3:** implement. **Step 4:** GREEN (49 + 4). **Step 5: Commit** `feat(core): night stack accumulator`

---

### Task 2: Engine — captureNightStack

**Files:**
- Modify: `Engine/CameraEngine.swift`
- Create: `Engine/NightStacker.swift` (ImageIO decode/encode helpers)
- Test: `Tests/CameraEngineTests.swift` (append), `Tests/NightStackerTests.swift`

**Interfaces (produces, consumed by Task 3):**
- `CameraEngine`: `var nightEnabled = false` (published);
  `func captureNightStack(onProgress: @escaping (Int, Int) -> Void, completion: @escaping (Data?) -> Void)` — MainActor entry. Behavior:
  1. Guard `!longExposureRunning`. Lock AE via the existing LONG pattern (`prepareLongExposure`-style: lock when fully auto, remember to re-apply at end — factor the existing lock/unlock into shared private helpers if needed rather than duplicating).
  2. Sequentially call the capture path `NightStack.frameCount` times with a forced recipe (`CaptureRecipe(raw: .none, includeProcessed: true, bracketing: nil, processing: .zero)`) and flash off — add a device-capture entry point that takes an explicit recipe (small overload of the existing `capture`) so the forcing bypasses UI state without mutating it.
  3. After each frame: `onProgress(index+1, frameCount)`; decode HEIF → RGBA8 via `NightStacker.decodeRGBA8(_ data: Data) -> (bytes: [UInt8], width: Int, height: Int)?`; first frame sizes a `NightAccumulator`; mismatch or decode failure → abort (completion(nil), restore AE).
  4. End: `NightStacker.encodeHEIF(rgba: [UInt8], width: Int, height: Int) -> Data?` (CGImageDestination, `kCGImageDestinationLossyCompressionQuality: 0.9`); restore AE; `completion(data)`.
- `NightStacker` is an enum with the two static functions above (pure, ImageIO/CoreGraphics only — no UIKit) so they are unit-testable.

- [ ] **Step 1: Failing tests** — `Tests/NightStackerTests.swift`: build a tiny 4×4 CGImage in-test, encode via `NightStacker.encodeHEIF`, decode via `decodeRGBA8`, assert dimensions and that a solid-color image round-trips within HEIF lossy tolerance (±3 per channel). Note: if HEIC encoding is unavailable in the simulator (`CGImageDestinationCreateWithData` returns nil for `public.heic`), have `encodeHEIF` fall back to... it IS available on iOS simulators — write the test against HEIC directly; if it proves unavailable at runtime the implementer reports BLOCKED with evidence rather than papering over. In `Tests/CameraEngineTests.swift`: extend FakeCameraDevice to return a pre-encoded tiny HEIF (fixture generated in-test via encodeHEIF) for each capture; `captureNightStack` → completion Data decodes to the right size; a fake failure (empty resources) mid-stack → completion(nil).
- [ ] **Step 2:** RED. **Step 3:** implement. **Step 4:** GREEN (full app suite). **Step 5: Commit** `feat(engine): night stack capture and averaging`

---

### Task 3: UI — NIGHT cell, routing, progress

**Files:**
- Modify: `App/TopBar.swift`, `App/ViewfinderScreen.swift`, `README.md`

**Authoritative behavior:**
- Rail: `NIGHT` cell after LONG: value `engine.nightEnabled ? "×8" : "—"`, active when enabled; action toggles and enforces exclusions (`nightEnabled = !nightEnabled; if nightEnabled { engine.longMode = .off; engine.bracketCount = nil }`). LONG cell action gains `if engine.longMode != .off { engine.nightEnabled = false }` after cycling; BKT likewise when setting non-nil.
- ViewfinderScreen `takePhoto()`: after the LONG routing block, add NIGHT routing: if `engine.nightEnabled`, run the countdown flow as usual, then `performNightStack()` instead of `performCapture()` (thread through the countdown-fired path too).
- `performNightStack()`: guards `!captureInFlight`; sets it; `@State nightProgress: (Int, Int)?` drives a top-center progress pill (`Text("NIGHT \(n)/\(total)")`, readout-pill styling, accent text, `contentTransition(.numericText())`); begins a background task + `isIdleTimerDisabled = true` (LONG's guard pattern — reuse `LongExposureBackgroundGuard`); calls `engine.captureNightStack`; on completion: clear progress/in-flight/idle-timer/guard; nil → `showCaptureFailed()`; data → thumbnail pop + `Task { await store.store([CaptureResource(kind: .processedHEIF, data: data)]); refreshSaveState() }` + `Haptics.success()`.
- Chrome: `chromeBlocked` gains `|| nightProgress != nil` (pill must stay visible).
- README QA: `- [ ] NIGHT ×8 on a tripod: single clean HEIF saved, visibly less noisy than one 0AI frame; abort mid-stack leaves no partial asset`.

- [ ] **Step 1:** implement. **Step 2:** full sweep both suites green. **Step 3: Commit** `feat(ui): NIGHT stack mode with progress pill`

---

## Self-Review Notes

- Spec coverage: accumulator (T1), sequential locked capture + decode/average/encode + abort (T2), cell/exclusions/routing/progress/save/QA (T3).
- Type consistency: `NightStack.frameCount`/`NightAccumulator` API exact between T1 and T2; `captureNightStack(onProgress:completion:)` exact between T2 and T3.
- Risk flags for implementers: AE lock reuse must not double-apply LONG logic (factor shared helper); memory — decode one frame at a time; the forced-recipe capture overload must not leak into normal captures.
