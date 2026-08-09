# SnapFlex — Focus Loupe Design

**Date:** 2026-08-09
**Status:** Approved (feature batch 2/5), pending implementation plan

## Overview

A magnified punch-in of the frame center shown while the user adjusts manual
focus: a 140pt circle, top-center of the viewfinder, displaying a native-pixel
center crop of the live feed (magnification falls out of drawing a small crop
at a larger size). Disappears when the focus dial closes or focus returns to
AF. The single most requested focusing aid in the pro-camera community
(Halide's loupe).

## Architecture

- **Crop source**: the existing overlay frame path. `OverlayPipeline` gains a
  `loupeEnabled` flag in `OverlaySettings` and, when enabled, copies a square
  center crop of the source BGRA texture into a private `loupeTexture`
  (`bgra8Unorm`, 320×320, `.shaderRead` usage) via `MTLBlitCommandEncoder`
  (1:1 copy, no scaling — magnification happens at draw time). Exposed like
  `waveformTexture` (stateLock getter), passthrough on `OverlayFrameDriver`.
- **Crop origin**: `((width-320)/2, (height-320)/2)` clamped to ≥ 0; if the
  source is smaller than 320 on a side, copy the largest centered square that
  fits.
- **View**: `LoupeView` (MTKView UIViewRepresentable, 15 fps, same
  device/queue as the driver — same-queue contract) draws the loupe texture
  with the existing overlay vertex + a `loupeFragment` doing plain
  `texture2d<float>` reads (bgra8Unorm, no sampler needed — compute uv→texel
  with nearest reads and clamped coordinates, matching waveformFragment's
  convention).
- **SwiftUI chrome**: 140×140, `clipShape(Circle())`, 1pt hairline
  `white 0.2` circle stroke plus a 2pt accent crosshair tick at the center
  (two 8pt accent lines), `allowsHitTesting(false)`, positioned top-center
  under the top deck (same slot family as the readout pill, offset lower so
  they can't overlap — the pill only shows when chrome is hidden, the loupe
  only when the dial is open, and the dial pins chrome visible, so they are
  mutually exclusive by construction; still offset for safety).
- **Visibility rule** (ViewfinderScreen): shown iff
  `selected == .focus && engine.values.focusPosition != nil` — i.e. the focus
  dial is open AND manual focus is engaged. `OverlaySettings.loupeEnabled` is
  driven from this same condition via `.onChange` (so the GPU copy only runs
  while visible). Transition: scale 0.9 + opacity with `Theme.springBouncy`
  through `Theme.motion`.

## Out of scope (v1)

- Peaking overlay inside the loupe; tap-to-move loupe point (fixed center);
  zoom levels (fixed native-pixel crop).

## Testing

- App Metal tests (ShaderTests pattern): with loupe enabled, processing a
  gradient input yields a loupe texture whose corner texel equals the source
  texel at the crop origin (blit correctness); disabled → texture stays nil.
- On-device QA: loupe appears only with focus dial + MF; magnification is
  native-pixel; no frame pacing hit.
