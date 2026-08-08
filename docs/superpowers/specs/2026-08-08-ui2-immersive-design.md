# SnapFlex — UI 2.0 "Immersive" Design

**Date:** 2026-08-08
**Status:** Approved design (direction B — immersive auto-hide), pending implementation plan

## Overview

A system-wide UI elevation: the interface gets out of the way when idle and
comes alive when touched. Direction chosen from mockups: **immersive
auto-hide** — after a short idle period the chrome dissolves, leaving the
viewfinder nearly full-bleed with only the shutter and a minimal readout.
Every interaction gains the same animation language: springs, bounces,
morphing values, haptics. The tech-monospace identity (deep black chrome,
accent green #4ADE80, monospaced values) is unchanged.

## Chrome states

**Full** (default on any interaction): top bar, histogram, dial (if open),
parameter bar, bottom row — the current layout.

**Minimal** (after 2.0s with no interaction):
- Hidden: top bar, parameter bar, lens chips, thumbnail, histogram, grid/level
  stay VISIBLE (they are shooting aids, not chrome)
- Remaining: shutter button (slightly smaller, 54pt) and one compact top-center
  readout pill summarizing active state, e.g. `ISO 200 · 1/120 · ND 15s` —
  only non-auto values and active modes appear; fully-auto shows `AUTO`
- Transition: chrome fades+scales out with a soft spring; reveal is a
  bouncier spring (the "bounce back" moment)

**Reveal triggers:** any tap or drag on the screen, opening the dial, a Camera
Control hardware interaction (control events reveal the chrome so the on-screen
values are visible while sliding), a capture, a status change (interruption).

**Never hides while:** the dial is open, a LONG exposure is running (the
exposure HUD has its own layout), the permission/interruption overlays are up,
or the countdown timer is active.

## Animation language

- **Standard spring** for state changes: `.spring(response: 0.35, dampingFraction: 0.75)`
- **Bouncy spring** for reveals/pop-ins: `.spring(response: 0.4, dampingFraction: 0.6)`
- **Value morphs:** parameter values and chips animate digit changes with
  `.contentTransition(.numericText())`; chip label changes crossfade
- **Dial:** momentum with deceleration on release, snap to logical detents
  (full ISO values, standard shutter stops), tick haptic per detent
- **Shutter:** press scales to 0.9 with a spring, release pops back; capture
  fires the flash overlay plus a medium-impact haptic; a LONG exposure start
  morphs the shutter into the progress ring
- **Thumbnail:** new capture pops in with a bouncy spring from 0.6 scale
- **Selection:** tiles highlight with an animated capsule that slides between
  parameters rather than appearing per-tile

## Haptics

- Light impact on dial detents and chip cycling
- Selection-changed on parameter tile selection
- Medium impact on capture; success notification when a LONG exposure completes
- All haptics behind one small `Haptics` helper (single point of tuning)

## Accessibility

`UIAccessibility.isReduceMotionEnabled` (or SwiftUI equivalent) replaces
springs/bounces with plain crossfades; auto-hide timing is unchanged.

## Architecture

- `ChromeVisibilityModel` (pure logic, unit-testable): state machine
  `full ⇄ minimal` driven by `interaction()`, `tick(now:)`, and blocking
  conditions (dial open, exposing, overlay up); owns the 2.0s idle constant
- `Haptics` enum wrapping UIKit feedback generators
- Animation constants centralized in `Theme` (springs, durations) so the
  language stays consistent
- Views consume `ChromeVisibilityModel` state; no view owns its own timer

## Testing

- `ChromeVisibilityModel`: idle expiry, reveal triggers, blocking conditions,
  re-arm on interaction — pure unit tests
- Readout pill content (active-values summary string) — pure function, unit-tested
- Springs/haptics/morphs: build-verified + on-device QA checklist additions
  (hide after 2s, bounce reveal on tap, no hide during dial/LONG/countdown,
  Reduce Motion fallback)
