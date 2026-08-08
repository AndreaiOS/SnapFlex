# SnapFlex — Processing Level (PROC) Design

**Date:** 2026-08-08
**Status:** Approved design, pending implementation plan

## Overview

A `PROC` control exposing Apple's computational-photography intensity for
processed (HEIF) captures — a control the native Camera hides:

- **0AI** → `.speed`: minimal processing, no Deep Fusion, minimal Smart HDR —
  the most "optical" image the ISP will produce
- **STD** → `.balanced`: Apple's default processing
- **MAX** → `.quality`: everything on (Deep Fusion, full Smart HDR; slower shots)

The level applies to every processed capture, including the HEIF companion
saved alongside RAW — enabling direct RAW vs 0AI vs MAX comparisons of the
same scene. Bayer RAW remains the true zero-pipeline option and is unaffected.

## Scope

- New `ProcessingLevel` value (Core): `.zero` ("0AI"), `.standard` ("STD"),
  `.max` ("MAX"), with chip-cycling helper; default `.standard`
- `CaptureRecipe` carries the level; `PhotoCaptureCoordinator.makeSettings`
  maps it to `AVCapturePhotoSettings.photoQualityPrioritization`
  (`.speed` / `.balanced` / `.quality`)
- Applied to NON-bracketed settings only (brackets skip computational fusion
  by nature, same guard pattern as flashMode)
- Engine publishes `processingLevel`; UI adds a `PROC` chip to the TopBar
  cycling 0AI → STD → MAX (rotates with the device like the other chips)
- Out of scope: per-shot metadata tagging of the level; LONG exposures
  (they bypass AVCapturePhotoOutput entirely)

## Constraint

`photoOutput.maxPhotoQualityPrioritization` is already `.quality` at session
configuration (v1), which permits any per-capture prioritization ≤ quality —
no session change needed.

## Testing

- Core: recipe carries/defaults the level; cycling order
- App: makeSettings maps each level to the right prioritization on plain
  settings and leaves bracketed settings untouched
- On-device QA: same scene at 0AI vs MAX shows visible processing difference
  (fine detail rendering, HDR strength); RAW+companion pair respects the level
