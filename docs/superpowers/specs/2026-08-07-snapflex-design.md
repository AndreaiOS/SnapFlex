# SnapFlex — Design Document

**Date:** 2026-08-07
**Status:** Approved design, pending implementation plan

## Overview

SnapFlex is an iOS camera app for photographers who want full manual control — the maximum that Apple's public APIs allow. Photo only (no video in v1), rear cameras only, English-only UI, distributed on the App Store, targeting iOS 18+.

## Scope

### In scope (v1)

**Manual controls** (each toggles between auto and manual):
- ISO and shutter speed (set together via `setExposureModeCustom`)
- Manual focus (`setFocusModeLocked`, lens position 0–1)
- White balance in Kelvin (`setWhiteBalanceModeLocked` with Kelvin→gains conversion)
- Exposure compensation (EV bias) when in auto exposure
- Lens selection: ultra-wide / wide / telephoto (as available on device) plus pinch zoom

**Capture formats** (user-selectable):
- Apple ProRAW (DNG) — on supported devices (iPhone Pro models)
- Bayer RAW (DNG) — plain sensor RAW via `AVCapturePhotoOutput`, works on non-Pro devices
- HEIF/JPEG — alone or saved alongside RAW as a processed companion

**Assist tools** (each individually toggleable):
- Live RGB histogram
- Focus peaking (edge highlight for manual focus)
- Zebra stripes on clipped highlights
- Rule-of-thirds grid and horizon level (CoreMotion)

**Capture extras:**
- Self-timer (3s / 10s countdown)
- Exposure bracketing: 3 or 5 shots via `AVCapturePhotoBracketSettings` with configurable EV step
- Volume buttons as shutter release

**Output:**
- Photos are saved directly to the system Photos library (add-only permission). RAW + HEIF pairs are saved as a single asset with multiple resources.
- In-app thumbnail of the last capture; tapping it opens the Photos app.

### Out of scope (v1)

- Video recording
- Front camera
- In-app gallery or photo editing
- Localization beyond English
- Presets/custom shooting modes, Apple Watch remote, widgets

## UI Design

**Layout — "parameter bar + dial" (chosen from mockup option A, Halide-style):**
- Full-screen viewfinder.
- Bottom bar: one row of parameter tiles (ISO · SHUTTER · EV · FOCUS · WB), then shutter button flanked by last-capture thumbnail (left) and lens selector chips (right).
- Tapping a parameter tile shows a horizontal scrubbing dial above the bar; the active tile is highlighted. Tapping again (or a long-press on the tile) returns that parameter to auto.
- Top bar: format selector (ProRAW/RAW/HEIF), flash toggle, aspect ratio, assist-tools toggle menu.
- Histogram floats in a corner of the viewfinder; grid/level/peaking/zebra draw over the preview.

**Visual style — "tech monospace" (chosen from mockup option C):**
- Deep black chrome, translucent over the viewfinder.
- Accent color: green (≈ `#4ADE80`) for active/selected values.
- Monospaced font for all numeric values; instrument-like, precise look.
- Portrait and landscape supported; controls stay anchored to the shutter side.

## Architecture

Four modules with strict boundaries; data flow is unidirectional (UI sends commands → CameraEngine publishes state → UI renders). Only CameraEngine touches AVFoundation session APIs.

### CameraEngine (no UI)

- Owns the `AVCaptureSession` on a dedicated serial queue.
- Exposes `@Observable` state: current parameter values, valid ranges for the active device (ISO, shutter duration, lens position, WB gains, zoom), active lens, format capabilities (ProRAW support), session state (running / interrupted / failed).
- Receives commands: `setISO`, `setShutter`, `setExposureBias`, `lockFocus(position:)`, `setWhiteBalance(kelvin:)`, `selectLens`, `setZoom`, `capture(settings:)`.
- Handles device discovery (`AVCaptureDevice.DiscoverySession`), lens switching, format configuration, bracketed capture, and zero-shutter-lag / responsive capture settings.
- The capture device is abstracted behind a protocol so the engine's logic is unit-testable with a fake device.

### OverlayPipeline (Metal)

- Consumes reduced-resolution frames from `AVCaptureVideoDataOutput`.
- Compute shaders produce: RGB histogram bins, focus-peaking mask (Sobel edge filter + threshold), zebra mask (luminance threshold, default 100% clip warning).
- Renders masks and histogram onto a transparent `MTKView` layered over the system preview (`AVCaptureVideoPreviewLayer`). Chosen hybrid approach: Apple manages the preview (color-accurate, power-efficient); overlays may lag the preview by ~1 frame, which is acceptable.
- When all assist overlays are off, the video data output is detached and the pipeline consumes nothing.

### CaptureStore (PhotoKit)

- Receives `AVCapturePhoto` results (DNG and/or HEIF) and writes them to the Photos library using `PHPhotoLibrary` add-only authorization.
- RAW+HEIF pairs become one asset with multiple resources.
- If Photos permission is denied, files are written to a temporary app directory and flushed to Photos once permission is granted (no capture is ever lost).

### UI (SwiftUI)

- Viewfinder via `UIViewRepresentable` wrapping the preview layer + MTKView overlay.
- Parameter bar, dial, top bar, timer countdown, level indicator, capture feedback.
- Volume-button shutter via `AVCaptureEventInteraction`.
- Reads CameraEngine state; issues commands only.

## Data Flow

**Capture:** shutter tap / volume press / timer expiry → CameraEngine builds `AVCapturePhotoSettings` for the selected format (ProRAW if supported and enabled, else Bayer RAW; HEIF companion if enabled; plain HEIF otherwise) → bracketing uses `AVCapturePhotoBracketSettings` (3 or 5 exposures) → on DNG delivery, CaptureStore saves in the background while the UI shows immediate shutter feedback and updates the thumbnail. Queued captures never block the viewfinder.

**Manual parameters:** dial gestures send values to CameraEngine. Valid ranges differ per lens; on lens switch the engine re-reads device ranges, republishes them (dials rescale), and clamps manual values to the nearest valid value — never silently resetting to auto.

## Error Handling

- **Camera permission denied:** dedicated full-screen state with a button to Settings. No degraded mode.
- **Photos permission denied:** capture still works; DNGs are stored in the app's temp directory and a banner prompts the user to grant access, after which files are migrated to Photos.
- **Session interruptions** (phone call, multitasking, thermal pressure): "camera paused" overlay driven by `AVCaptureSession` interruption notifications; automatic resume when the interruption ends.
- **Capture failure** (e.g. storage full): non-blocking error toast; the viewfinder keeps running.

## Testing

- **Unit tests (pure logic):** Kelvin↔gains conversion, EV→ISO/shutter pairs for bracketing, range clamping on lens switch, timer state machine, `AVCapturePhotoSettings` construction for every format combination.
- **CameraEngine tests:** run against a fake capture device behind the protocol (command → expected device calls and published state).
- **Shader tests:** feed synthetic images with known properties — a gray ramp must produce zebra above the threshold; a checkerboard must light up peaking on edges; histogram bins must match analytically computed values.
- **Manual on-device verification:** actual ProRAW/RAW capture, lens switching, bracketing output — the camera has no simulator support.

## Technical Notes

- Swift 6, SwiftUI, no third-party dependencies (AVFoundation, Metal, MetalKit, PhotoKit, CoreMotion).
- iPhone only. iOS 18 minimum enables modern capture APIs (responsive capture, zero shutter lag) without fallbacks.
- ProRAW availability is a runtime capability check; on unsupported devices the format selector simply omits it.
