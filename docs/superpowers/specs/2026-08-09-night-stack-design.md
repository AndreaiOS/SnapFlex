# SnapFlex — NIGHT Stack Design

**Date:** 2026-08-09
**Status:** Approved (feature batch 4/5), pending implementation plan

## Overview

Tripod night mode with zero AI: pressing the shutter in NIGHT mode captures
8 full-resolution stills back to back with locked exposure and minimal
processing (0AI/.speed), averages them pixel-for-pixel, and saves ONE clean
HEIF. Averaging N frames cuts sensor noise by ~√N (≈2.8× for 8) with no
machine-learning smoothing — the "honest computational night" that the
community praises in Project Indigo, expressed in SnapFlex's 0AI identity.

## UX

- New `NIGHT` rail cell (after LONG): cycles `—` → `×8` → `—`.
  Active = accent (like other cells).
- Engaging NIGHT auto-disables incompatible modes: LONG → off, BKT → nil
  (and vice versa: engaging LONG or BKT turns NIGHT off). Flash is forced
  off for NIGHT captures. RAW selection is ignored for the stack (frames are
  captured processed-only); the FMT cell is unaffected outside NIGHT.
- Shutter press with NIGHT ×8: normal timer/countdown flow applies first;
  then the stack runs — a top-center progress pill `NIGHT 3/8` (readout-pill
  styling, accent) replaces the shutter flash; the shutter is held disabled
  by the existing in-flight guard; chrome is pinned visible (blocked) during
  the stack like a countdown.
- Shake warning: reuse the LONG session's tripod assumption — v1 shows no
  gyro warning (out of scope), QA note covers tripod requirement.
- On completion: averaged HEIF saved via CaptureStore (single asset),
  thumbnail pops, `Haptics.success()`. On any frame failure: stack aborts,
  frames captured so far are discarded, `CAPTURE FAILED` toast shows.

## Architecture

- **Core (pure, tested)**: `NightStack` — `frameCount = 8`;
  `NightAccumulator`: fixed-size RGBA8 buffer accumulator with `[UInt16]`
  per-channel sums (`add(frame: [UInt8])` requires matching length;
  `average() -> [UInt8]` integer division by frames added; `framesAdded`).
  Max 8 × 255 = 2040 fits UInt16 with headroom.
- **Engine**: `CameraEngine.captureNightStack(onProgress:completion:)`:
  locks AE if fully auto (reusing the LONG AE-lock pattern + re-apply on
  end), then captures 8 sequential stills via the existing capture path with
  a recipe forced to `raw: .none, includeProcessed: true, processing: .zero`,
  flash off. Each HEIF is decoded to RGBA8 (ImageIO/CoreGraphics, no UIKit),
  fed to the accumulator, and released before the next capture (peak memory
  ≈ accumulator 96MB + one 48MB frame). The averaged RGBA8 buffer is encoded
  to HEIF (CGImageDestination, quality 0.9) and returned as `Data`.
  Dimension mismatch between frames (rotation change mid-stack) aborts.
- **Save**: the result goes through `CaptureStore.store` as a single
  `.processedHEIF` resource (spool fallback included).
- Background guard + idle-timer disable during the stack (same pattern as
  LONG finalize).

## Out of scope (v1)

Gyro shake warning; RAW-averaged output (DNG writing); frame alignment
(tripod assumed); configurable frame count.

## Testing

- Core: accumulator averaging math (two known frames → exact means),
  length-mismatch rejection, framesAdded, empty-average guard.
- App/Engine: `captureNightStack` with the fake device returning synthetic
  tiny HEIFs (generated in-test via ImageIO) → completion delivers a decodable
  HEIF whose pixels are the average; abort path on a failed frame.
- On-device QA: NIGHT ×8 on a tripod at night → visibly cleaner than a single
  0AI frame; stack duration reasonable; interruption mid-stack aborts cleanly.
