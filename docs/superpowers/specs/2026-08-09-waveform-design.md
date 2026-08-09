# SnapFlex — Luma Waveform Design

**Date:** 2026-08-09
**Status:** Approved (feature batch 1/5), pending implementation plan

## Overview

A cinema-monitor luma waveform docked bottom-left of the viewfinder: for each
image column, the distribution of luminance values plotted vertically (dark at
the bottom, bright at the top), rendered in accent green with intensity
proportional to pixel counts. Sibling of the existing Metal histogram: same
BGRA frame source, same overlay pipeline, its own compute kernel and tiny
Metal view.

## Architecture

- **Kernel** (`Overlay` shaders): `waveformAccumulate` — input BGRA texture,
  output `texture2d<uint, access::read_write>` 128 (columns) × 64 (luma bins),
  atomic-free per-column binning via one threadgroup per output column
  (each thread walks a stripe of source rows for its column; luma =
  0.299R+0.587G+0.114B). Zeroed each frame before accumulation.
- **Render**: `waveformFragment` maps counts → accent-green alpha with a soft
  knee (`alpha = min(1, count / knee)`, knee ≈ rows/32), over near-black.
- **Pipeline**: `OverlayPipeline` gains `waveformEnabled` in `OverlaySettings`
  (Core) and produces the waveform texture on the SAME MTLCommandQueue used by
  overlay renders (existing same-queue contract; gpuLock pattern not needed —
  single queue serializes).
- **View**: `WaveformMetalView` (UIViewRepresentable MTKView, 118×52pt,
  1pt hairline border white 0.14, corner radius 4, "LUMA" 6pt mono label
  overlay top-left) docked bottom-left above the parameter area, participates
  in chrome auto-hide, `allowsHitTesting(false)`.
- **Toggle**: "Waveform" in the assist menu next to Histogram; mutually
  independent (both can be on).

## Constraints

- Update ≤ 15 fps (existing frame-tap cadence); no work when disabled.
- Reuse existing CVMetalTextureCache / frame fan-out — the overlay driver
  already receives frames; waveform hooks the same path as histogram.
- Nearest sampling only on any float texture reads (A12/A13 rule).

## Testing

- Core: `OverlaySettings.waveformEnabled` round-trip (if Core owns the type).
- App (Metal unit tests like ShaderTests): uniform mid-gray input → all
  columns bin at the same luma row; black/white split image → two distinct
  rows populated; disabled → no texture writes.
- On-device QA: waveform tracks scene changes live; no frame-pacing hit with
  histogram+peaking+zebra all enabled.
