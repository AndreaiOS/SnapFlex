# SnapFlex — Shooting Recipes Design

**Date:** 2026-08-09
**Status:** Approved (feature batch 3/5), pending implementation plan

## Overview

Named, recallable capture setups ("recipes"): one tap restores a full
combination of exposure and pipeline settings. The film-recipe workflow the
community loves, on top of SnapFlex's existing persistence.

## What a recipe captures

`iso` (Float?), `shutterSeconds` (Double?), `evBias` (Float),
`wbKelvin` (Int?), `raw` (RAWMode), `heifCompanion` (Bool),
`processing` (ProcessingLevel), `aspectIndex` (Int) — plus `name` (String)
and `id` (UUID). Deliberately excluded: focus (scene-dependent), LONG mode
(a shooting mode, not a look), zoom/lens (framing).

## Core model

- `Recipe`: Codable, Equatable, Sendable struct with the fields above.
- `RecipeBook`: value type holding `recipes: [Recipe]` with
  `add(_:)` (appends; if a recipe with the same name exists, replaces it),
  `remove(id:)`, `encode() -> Data` / `init(data: Data)` (JSON round-trip;
  corrupt data → empty book). Pure logic, unit-tested; persistence I/O stays
  app-side (UserDefaults data blob under `recipes.book`).

## UI

- A `RCP` mono text button (same styling family as the statusline, accent
  when at least one recipe exists) in the top deck statusline, left of the
  assist menu.
- Its Menu: one button per saved recipe (name; tapping applies it), then
  "Save current…" (opens a SwiftUI alert with a TextField for the name;
  default suggestion `Recipe N`), then a "Delete" submenu listing recipes as
  destructive buttons.
- Applying a recipe: sets engine ISO/shutter (via the existing setters so
  clamping applies), EV bias, WB kelvin, formatSelection (raw + companion),
  processing level, and the aspect binding; fires `Haptics.success()` and
  reveals chrome. Values outside the current device's ranges are clamped by
  the existing engine/device clamping — a recipe never crashes.
- Saving: snapshots the same fields from current state; `Haptics.light()`.

## Testing

- Core: round-trip encode/decode, add-replaces-same-name, remove, corrupt
  data → empty.
- App: suite stays green (apply/save logic lives in small testable funcs if
  feasible, else covered by Core + QA).
- On-device QA: save a recipe, relaunch, apply → all values restored and
  visible in rail/tiles; apply with a lens with narrower ISO range → clamped,
  no crash.
