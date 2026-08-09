# SnapFlex — UI 3.0 "Strumento" Design

**Date:** 2026-08-09
**Status:** Approved direction (mockup A picked by the user), pending implementation plan

## Overview

The viewfinder chrome becomes a precision instrument panel: one segmented
rail instead of scattered chips, a micro statusline, a tick-ruler dial with a
fixed center needle, and an EV index arc around the shutter. Dense, labeled,
hairline-bordered — Teenage Engineering vibe. The identity (deep black,
accent #4ADE80, monospace) and the whole existing motion system (auto-hide
chrome, springs, detents, haptics, per-item rotation, Reduce Motion) are
unchanged.

## Components

### 1. Segmented rail (replaces the two-row chip bar)

- One horizontal rail, hairline border (`white 0.14`, radius 8), cells
  separated by 1pt gaps on a `white 0.05` fill.
- Cells in order: `FMT`, `PROC`, `FLASH`, `TIMER`, `BKT`, `LONG`, and
  `BLEND` (only while LONG ≠ off). Equal widths, `.frame(maxWidth: .infinity)`.
- Cell anatomy: micro-label 7pt mono, tracking .18em, `white 0.38`, above the
  value 9.5–10pt mono. Value shows current state (`RAW`, `STD`, `OFF`/`ON`
  becomes `—`/`3s`/`10s` for timer, `—`/`BKT 3`/`BKT 5`, LONG label short
  form `—`/`15s`/`BULB`).
- Active cell (feature engaged): value in accent, fill `accent 0.10`, and a
  2pt accent underline inset 18% from cell edges.
- Tap cycles exactly as today (same actions, same `Haptics.light()`),
  `.contentTransition(.numericText())` on values.
- Per-cell content counter-rotates with the device (existing modifier).

### 2. Statusline (above the rail)

- One 8.5pt mono line, tracking .14em, `white 0.42`; accent for engaged bits.
- Left slot: capture pipeline summary, e.g. `RAW+HEIF · STD` (format,
  companion, PROC — accent on the format when RAW is on).
- Right slot: battery percentage `BAT 82` (UIDevice battery monitoring;
  hide the slot if level is unavailable/simulator returns -1) and the assist
  menu trigger (existing slider icon, 14pt) at the far right.
- The save-state warnings (Photos denied banner) remain the existing
  separate banner — the statusline never carries errors.

### 3. Top deck container

- Statusline + rail in one VStack, padding 14/10, background
  `linear-gradient(black 0.92 → black 0.78)` with a 1pt bottom hairline in
  `accent 0.18`. Replaces the current two-row gradient bar.

### 4. Tick-ruler dial (ParameterDial restyle)

- Same gesture engine (drag, momentum, detent snapping, haptics, NaN
  guards, decay cancellation) — only the visual layer changes.
- Horizontal tick strip: minor ticks every detent-fraction, drawn as 1pt
  `white 0.28` lines, height 26; the strip translates with the normalized
  value so ticks scroll under a FIXED center needle (2pt accent, soft glow
  `accent 0.8` shadow radius 8, extends 3pt above the strip).
- Edge fade via linear mask (transparent → opaque 18% → opaque 82% →
  transparent).
- Current formatted value 9pt accent mono centered above the needle
  (existing formatting per parameter), `.contentTransition(.numericText())`.
- Tiles row below the ruler keeps today's behavior; tile restyle: selected
  tile gets `accent 0.12` fill + 1pt `accent 0.4` outline (keep
  matchedGeometryEffect capsule sliding).

### 5. Shutter EV arc

- A 2pt arc ring 9pt outside the shutter circle: trims from 12 o'clock,
  sweep proportional to `evBias / evRange`, positive clockwise, negative
  counter-clockwise, accent color.
- Label `EV +0.3` 7.5pt accent mono, tracking .12em, centered 22pt above
  the shutter, visible only when `evBias != 0`.
- Arc participates in chrome auto-hide with the rest of the bottom row
  decorations (shutter itself stays visible in minimal state, arc hides).

## Out of scope

- No layout change to bottom row (thumbnail, shutter, lens chips, zoom badge)
  beyond the EV arc.
- No Core changes except any pure formatting helper if needed (with tests).
- Histogram, overlays, LONG HUD unchanged.

## Testing

- Core: unchanged suite must stay green; add tests only for any new pure
  formatting helpers (e.g. rail short-labels) placed in Core.
- App: suite stays green; battery slot logic guarded for -1.
- On-device QA additions: rail legibility over bright scenes, ruler needle
  tracking during momentum, EV arc direction (+ clockwise), statusline
  battery accuracy, auto-hide still smooth with the new top deck.
