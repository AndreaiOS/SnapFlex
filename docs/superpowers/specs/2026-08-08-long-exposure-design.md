# SnapFlex — LONG Exposure Mode Design

**Date:** 2026-08-08
**Status:** Approved design, pending implementation plan

## Overview

Computational long exposure: SnapFlex breaks the ~1s hardware shutter limit by
accumulating video frames on the GPU into a single exposure — silk water, light
trails, star trails. Durations 2/5/15/30s plus Bulb, two blend modes, live
accumulation preview in the viewfinder.

## Scope

### In scope

- **Blend modes** (user-selectable while LONG is active):
  - **ND** — progressive per-pixel average of frames (digital ND filter: silk
    water, vanishing crowds, motion-blurred clouds)
  - **TRAILS** — per-pixel maximum (light trails, star trails, light painting)
- **Durations:** presets 2s / 5s / 15s / 30s, plus **Bulb** (start/stop with the
  shutter; hard safety cap at 5 minutes)
- **Live accumulation preview:** during the exposure the viewfinder shows the
  accumulating image in real time (not the live camera feed), with a progress
  ring and elapsed time; Bulb shows elapsed time and a stop affordance
- **Exposure lock:** on start, exposure is frozen — the user's manual ISO/shutter
  values if set, otherwise AE lock — so accumulated frames are consistent
- **Handheld warning:** a shake icon appears when gyro motion exceeds a
  threshold (feature is tripod-first; warning only, never blocks)
- **Output:** maximum-quality HEIF written through the existing CaptureStore
  pipeline (spool fallback included) straight to Photos
- **Cancel:** tapping the shutter during a preset exposure cancels and discards;
  in Bulb it stops and saves

### Out of scope (this iteration)

- Frame alignment / handheld stabilization (v2)
- DNG output of the fused result — Apple provides no API to author synthetic
  DNGs; output is HEIF only
- Full 48MP resolution — accumulation runs at the video stream resolution
  (~4K), the same trade-off as every app in this category
- Intervalometer / timelapse

## Architecture

New `LongExposure/` module alongside the existing Overlay pipeline; the same
`AVCaptureVideoDataOutput` BGRA frames that feed histogram/peaking also feed the
accumulator (fan-out at the frame-handler level).

### LongExposureAccumulator (Metal)

- Float32 RGBA accumulation texture at frame resolution
- Kernels: `accumulateAverageKernel` (running mean: acc += (frame − acc)/n) and
  `accumulateMaxKernel` (acc = max(acc, frame))
- `preview` texture readable by the viewfinder's MTKView layer each frame
- `readout()` → 8-bit sRGB image data (HEIF-encodable) at end of exposure
- Reset on start; thread-safety per the OverlayPipeline NSLock pattern

### LongExposureSession (pure logic, SnapFlexCore)

State machine, unit-tested: `idle → exposing(elapsed, target) → finishing` with
`cancel` (presets: discard; bulb: stop-and-save) and the 5-minute bulb cap.
Progress fraction and remaining time are derived values.

### Engine integration

- `CameraEngine` gains LONG state: `longMode: LongMode` (`off`, `preset(seconds)`,
  `bulb`), `longBlend: LongBlend` (`nd`, `trails`), `longProgress`
- `capture()` routes to `startLongExposure()` when LONG is active; frames flow
  via the existing `setVideoFrameHandler` fan-out; AE lock via
  `AVCaptureDevice.exposureMode = .locked` when no manual values are set
- Completion: accumulator readout → `CaptureResource(.processedHEIF)` →
  `CaptureStore.store` (existing permission/spool behavior applies)

### UI

- `LONG` chip in TopBar (OFF → 2s → 5s → 15s → 30s → BULB); `ND / TRAILS`
  toggle visible only when LONG ≠ OFF
- During exposure: accumulation preview replaces the live feed, progress ring
  around the shutter button, elapsed/remaining monospace readout, shake warning
  icon when gyro exceeds threshold
- Shutter semantics: preset → tap cancels; bulb → tap stops and saves

## Error handling

- App backgrounded / session interrupted mid-exposure: exposure is finalized
  and saved with whatever accumulated (never silently lost); if under 1s of
  accumulation, discarded
- Thermal pressure: same as interruption — finalize and save
- Storage/Photos failures: existing CaptureStore spool guarantees apply

## Testing

- Kernel tests with synthetic textures: average of known frames must equal the
  analytic mean (± quantization), max must equal per-pixel maximum
- `LongExposureSession` state machine: transitions, bulb cap, cancel semantics,
  progress math — pure unit tests
- Readout → HEIF encoding round-trip produces a decodable image of the right size
- On-device: silk-water ND on a faucet, TRAILS on car lights, bulb star trail,
  handheld warning firing, cancel/stop flows
