# Focus Loupe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 140pt magnifying loupe (native-pixel center crop) shown while the focus dial is open with manual focus engaged.

**Architecture:** Blit-based center crop in OverlayPipeline (new `loupeEnabled` + `loupeTexture`, exposed via OverlayFrameDriver), a `LoupeView` MTKView drawing it magnified, visibility driven by ViewfinderScreen's focus-dial state.

**Tech Stack:** existing (Metal, SwiftUI). **Spec:** `docs/superpowers/specs/2026-08-09-focus-loupe-design.md`

## Global Constraints

- Same MTLCommandQueue as all overlay work; no work when `loupeEnabled == false`.
- Loupe texture: `bgra8Unorm` 320×320 `.shaderRead` (blit destination needs no shaderWrite), blit 1:1 copy of the centered square, origin clamped ≥ 0, crop side `min(320, min(width, height))`.
- Fragment reads with clamped nearest coordinates (match `waveformFragment` convention: `min(uint(uv.x * side), side-1)`).
- Every animation through `Theme.motion(...)`; loupe never intercepts touches.
- Test commands from `/Users/andreamurru/SnapFlexBuild`: `cd Core && swift test` (45); `xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'` (45 + new; FOREGROUND, report BLOCKED if hung >10min). Ignore SourceKit "No such module" noise.

---

### Task 1: Pipeline crop + tests

**Files:**
- Modify: `Overlay/OverlayPipeline.swift`, `Overlay/OverlayFrameDriver.swift`
- Test: `Tests/ShaderTests.swift` (append)

**Interfaces (produces, consumed by Task 2):**
- `OverlaySettings` gains `var loupeEnabled: Bool = false` (update `allOff` and `anyEnabled`).
- `OverlayPipeline` gains `var loupeTexture: MTLTexture?` (stateLock getter like waveform) filled in `process(...)` when enabled: lazily create the destination texture, then on the SAME command buffer as the other passes add a blit encoder copying `sourceSlice` → loupe texture where `side = min(320, min(w, h))`, `origin = ((w-side)/2, (h-side)/2)`; recreate the destination if `side` changed since last frame.
- `OverlayFrameDriver` gains `var loupeTexture: MTLTexture? { pipeline.loupeTexture }`.

- [ ] **Step 1: Failing tests** (append to ShaderTests, reusing its texture helpers):

```swift
    @Test func loupeCopiesCenterCrop() {
        // 400x400 input where pixel value encodes position (existing gradient helper
        // or a custom fill): enable only loupe, process, read back loupe texture;
        // assert side == 320 and texel (0,0) equals source texel (40,40),
        // texel (319,319) equals source texel (359,359).
    }

    @Test func loupeDisabledProducesNoTexture() {
        // histogramEnabled true so the pass runs; loupeEnabled false → loupeTexture nil
    }
```

Write them as REAL executable tests per ShaderTests' existing readback pattern.

- [ ] **Step 2:** RED. **Step 3:** implement. **Step 4:** GREEN (app suite full; Core untouched). **Step 5: Commit** `feat(overlay): loupe center-crop pipeline`

---

### Task 2: LoupeView + viewfinder integration

**Files:**
- Create: `App/LoupeView.swift`
- Modify: `Overlay/Shaders.metal` (loupeFragment), `App/ViewfinderScreen.swift`, `README.md`
- Run `xcodegen generate` after the new file; commit regenerated project.

**Authoritative behavior:**
- `loupeFragment` in Shaders.metal (uses the shared overlay vertex):

```metal
fragment float4 loupeFragment(OverlayVertexOut in [[stage_in]],
                              texture2d<float, access::read> loupe [[texture(0)]]) {
    uint side = loupe.get_width();
    uint2 coord = uint2(min(uint(in.uv.x * float(side)), side - 1),
                        min(uint(in.uv.y * float(side)), side - 1));
    float4 c = loupe.read(coord);
    return float4(c.rgb, 1.0);
}
```

- `LoupeView.swift`: mirror `WaveformView`'s structure exactly (UIViewRepresentable MTKView, 15fps, driver's device/queue, guard `driver.loupeTexture` first, render pipeline built once in the coordinator with `overlayVertex` + `loupeFragment`).
- ViewfinderScreen overlay chrome: in the main ZStack (after the readout pill / capture-failed toast blocks):

```swift
            if showLoupe, let driver {
                LoupeView(driver: driver)
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .overlay(loupeCrosshair)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 120)
            }
```

  with `private var showLoupe: Bool { selected == .focus && engine.values.focusPosition != nil }`, `private var loupeCrosshair: some View` = ZStack of two `Rectangle().fill(Theme.accent)` 8×2 and 2×8 centered, and `.animation(Theme.motion(Theme.springBouncy), value: showLoupe)` on the container. Drive the pipeline: `.onChange(of: showLoupe) { _, on in engine.overlaySettings.loupeEnabled = on }` (and set it false in `onDisappear` for hygiene).
- README QA: `- [ ] Loupe appears while focusing manually (dial open + MF); magnified center crop is sharp and live`.

- [ ] **Step 1:** implement + xcodegen. **Step 2:** full sweep both suites green. **Step 3: Commit** `feat(ui): focus loupe while adjusting manual focus`

---

## Self-Review Notes

- Spec coverage: settings flag + blit crop + exposure (T1), fragment + view + visibility rule + crosshair + QA (T2). Mutual exclusivity with readout pill argued in spec (dial pins chrome full → pill hidden).
- Type consistency: `loupeTexture` name identical across pipeline/driver/view; `loupeEnabled` reachable via existing overlaySettings plumbing (engine.overlaySettings → driver.settings sync already exists for other flags — Task 2 must verify that sync path carries the new flag with zero extra work, since OverlaySettings is one struct).
- Perf: blit is bandwidth-only (~400KB/frame at 320²); no work when hidden.
