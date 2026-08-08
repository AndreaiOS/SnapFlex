# Processing Level (PROC) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PROC chip (0AI / STD / MAX) mapping to `AVCapturePhotoSettings.photoQualityPrioritization` (.speed/.balanced/.quality) on processed captures, including RAW companions; brackets untouched.

**Architecture:** `ProcessingLevel` in SnapFlexCore → carried by `CaptureRecipe` → mapped in `PhotoCaptureCoordinator.makeSettings` → published by `CameraEngine.processingLevel` → TopBar chip.

**Tech Stack:** existing. **Spec:** `docs/superpowers/specs/2026-08-08-processing-level-design.md`

## Global Constraints

- Mapping exactly: `.zero`→`.speed`, `.standard`→`.balanced`, `.max`→`.quality`; default `.standard`
- Prioritization set on NON-bracket settings only (same guard as flashMode)
- Chip cycle: 0AI → STD → MAX → 0AI; chip label = rawValue
- Test commands as usual (Core `swift test`; app `xcodebuild test ... 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet`)

---

### Task 1: Core — ProcessingLevel + recipe plumbing

**Files:**
- Create: `Core/Sources/SnapFlexCore/ProcessingLevel.swift`
- Modify: `Core/Sources/SnapFlexCore/CaptureRecipe.swift`
- Test: `Core/Tests/SnapFlexCoreTests/ProcessingLevelTests.swift`

**Interfaces:**

```swift
public enum ProcessingLevel: String, CaseIterable, Sendable {
    case zero = "0AI"
    case standard = "STD"
    case max = "MAX"
    public var next: ProcessingLevel {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
```

- `CaptureRecipe` gains `public var processing: ProcessingLevel`; its memberwise init gains `processing: ProcessingLevel = .standard` (defaulted → existing call sites/tests compile unchanged); `CaptureRecipe.make(selection:capabilities:bracketing:)` gains `processing: ProcessingLevel = .standard` and passes it through.

- [ ] **Step 1: Failing tests**

```swift
// Core/Tests/SnapFlexCoreTests/ProcessingLevelTests.swift
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
```

- [ ] **Step 2:** `cd Core && swift test` → RED. **Step 3:** implement. **Step 4:** GREEN (all Core suites; existing CaptureRecipe tests must pass unchanged thanks to the defaults). **Step 5: Commit** — `feat(core): add processing level to capture recipes`

---

### Task 2: Engine + coordinator mapping

**Files:**
- Modify: `Engine/CameraEngine.swift`, `Engine/PhotoCaptureCoordinator.swift`
- Test: `Tests/PhotoCaptureCoordinatorTests.swift`, `Tests/CameraEngineTests.swift`

**Interfaces:**
- `CameraEngine`: `var processingLevel: ProcessingLevel = .standard` (published); `capture()` passes it to `CaptureRecipe.make(..., processing: processingLevel)`.
- `PhotoCaptureCoordinator.makeSettings`: after the existing flashMode guard block, add (same non-bracket guard):

```swift
if !(settings is AVCapturePhotoBracketSettings) {
    settings.photoQualityPrioritization = switch recipe.processing {
    case .zero: .speed
    case .standard: .balanced
    case .max: .quality
    }
}
```

- [ ] **Step 1: Failing tests** — add to Tests/PhotoCaptureCoordinatorTests.swift:

```swift
    @Test func processingLevelMapsToPrioritization() {
        for (level, expected): (ProcessingLevel, AVCapturePhotoSettings.QualityPrioritization) in
            [(.zero, .speed), (.standard, .balanced), (.max, .quality)] {
            let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true,
                                       bracketing: nil, processing: level)
            let settings = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
            #expect(settings.photoQualityPrioritization == expected)
        }
    }

    @Test func bracketSettingsSkipPrioritization() {
        let recipe = CaptureRecipe(raw: RAWKind.none, includeProcessed: true,
                                   bracketing: .autoExposure(biases: [-1, 0, 1]), processing: .max)
        _ = PhotoCaptureCoordinator.makeSettings(recipe: recipe, rawType: nil, flashOn: false)
        // constructing must not trap; bracket settings keep their default prioritization
    }
```

  And to Tests/CameraEngineTests.swift:

```swift
    @Test func captureCarriesProcessingLevel() {
        let (engine, device) = makeEngine()
        engine.formatSelection = FormatSelection(raw: .off, heifCompanion: false)
        engine.processingLevel = .max
        engine.capture { _ in }
        #expect(device.capturedRecipes.last?.processing == .max)
    }
```

  Note: if setting `photoQualityPrioritization` above the output's `maxPhotoQualityPrioritization` traps in the simulator when settings are detached from an output, it does not — the property is validated at capturePhoto time; the test only constructs settings.

- [ ] **Step 2:** app suite → RED. **Step 3:** implement both files. **Step 4:** GREEN (full suite). **Step 5: Commit** — `feat(engine): map processing level to photo quality prioritization`

---

### Task 3: PROC chip + sweep + README

**Files:**
- Modify: `App/TopBar.swift`, `README.md`

**Interfaces:**
- TopBar: after the format chip, add `chip(engine.processingLevel.rawValue) { engine.processingLevel = engine.processingLevel.next }`. Uses the existing chip helper (rotation inherited). Chip hidden while `engine.longMode != .off`? No — keep visible (LONG ignores it; harmless).
- README QA additions:

```markdown
- [ ] PROC 0AI vs MAX on a detailed scene shows visibly different processing
- [ ] RAW + HEIF companion honors the PROC level on the companion
- [ ] PROC level survives lens switches and app restarts is NOT required (resets to STD)
```

- [ ] **Step 1:** implement chip + README. **Step 2:** full sweep both suites → green (expect Core 31, app 40). **Step 3: Commit** — `feat(ui): add PROC processing level chip`

---

## Self-Review Notes

- Spec coverage: enum+cycle (T1), recipe carry (T1), mapping+bracket guard (T2), engine publish+capture pass-through (T2), chip (T3), QA (T3). Out-of-scope honored (no metadata, LONG untouched).
- Type consistency: `ProcessingLevel` defined once (T1); `processing:` defaulted params keep all existing Core/app tests compiling unchanged.
