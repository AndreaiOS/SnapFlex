# SnapFlex — One-Tap ETTR Design

**Date:** 2026-08-10
**Status:** Approved (feature batch B2 1/5), pending implementation plan

## Overview

Expose To The Right in one tap: the exposure is pushed as bright as possible
without clipping highlights, maximizing signal-to-noise — the technically
optimal exposure for RAW shooters. Driven entirely by the histogram we
already compute; no AI, no metering guesswork.

## UX

- Primary trigger: **tap the histogram** (it becomes a button when visible).
  Secondary: an `ETTR` action row in the assist menu (discoverability).
- On tap: a short convergence loop (up to 6 iterations, one per new
  histogram update, ~1s total) nudges exposure until the highlight bin mass
  sits just under the clip threshold. Accent flash on the histogram border
  while converging; `Haptics.success()` when settled, `Haptics.light()` if
  already optimal.
- Exposure channel: in AUTO exposure → adjusts `evBias` (clamped to range).
  In full MANUAL (iso+shutter set) → adjusts `shutterSeconds` by the stop
  delta (clamped; ISO untouched — noise-optimal). Mixed states behave as
  AUTO (bias).
- Requires the histogram overlay enabled; the assist-menu action enables it
  automatically first.
- Never runs during LONG/NIGHT/capture-in-flight.

## Core logic (pure, tested)

`ETTR.adjustment(bins: [UInt32], clipFraction: Double = 0.005, targetTopBins: Int = 12) -> Double`

- `bins`: the 192-bin luma histogram (existing format).
- Returns the suggested exposure delta in EV stops (positive = brighten),
  `0` when converged.
- Rules: let `total = Σbins` (0 → return 0). Clipped mass = fraction in the
  top 2 bins. If clipped > `clipFraction` → return −0.3 (step down).
  Else if the brightest nonzero bin index < 192 − `targetTopBins` → return
  +0.3 (headroom unused). Else 0 (converged).
- A convergence loop app-side applies successive deltas as new histogram
  frames arrive; hard cap 6 iterations.

## Testing

- Core: clipped histogram → negative; dark histogram with headroom →
  positive; converged shape → 0; empty → 0.
- App: suite green; loop capped; manual-mode shutter adjustment clamped.
- On-device QA: tap histogram on a contrasty scene → exposure settles with
  highlights just below zebra; RAW noticeably cleaner in shadows vs default
  metering after pulling down in post.
