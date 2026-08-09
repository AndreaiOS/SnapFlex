# SnapFlex — Apple Watch Remote Design

**Date:** 2026-08-09
**Status:** Approved (feature batch 5/5), pending implementation plan

## Overview

A companion watchOS app that acts as a remote trigger: a big shutter button on
the wrist fires the iPhone camera (respecting the phone's current mode —
normal, timer, NIGHT, LONG), shows a live status line, and displays a small
thumbnail of the last capture. Ideal for tripod work (LONG/NIGHT) where
touching the phone shakes the shot.

## Scope (v1)

- Watch app (watchOS 10+, SwiftUI, tech-mono identity: black ground, accent
  green #4ADE80, monospaced): one screen — status line (e.g. `READY`,
  `NIGHT 3/8`, `LONG 12s`, `OFFLINE`), a 64pt circular shutter button,
  last-capture thumbnail (small, rounded).
- iPhone side: `WatchRemote` (App layer) wrapping `WCSession` behind a
  protocol for testability. Receives `capture` messages → triggers the same
  `takePhoto()` path as the on-screen shutter (MainActor). Publishes status
  updates (mode/progress changes) to the watch via `sendMessage` (fire and
  forget, best effort) and pushes a ~200px JPEG thumbnail after each capture
  via `transferFile`-free `sendMessageData` (small payload, best effort).
- Reachability: watch shows `OFFLINE` when the session is not reachable;
  capture taps while offline are ignored with haptic feedback (watch-side
  `WKInterfaceDevice.current().play(.failure)`).
- Out of scope v1: live viewfinder streaming, parameter editing from the
  watch, complications, independent watch capture.

## Architecture

- New XcodeGen target `SnapFlexWatch` (platform watchOS, SwiftUI app,
  bundle id `co.SnapFlex.watchkitapp`, DEVELOPMENT_TEAM RA4VQQK3U6),
  embedded in the iOS app target. Sources in `Watch/`.
- Shared message contract in Core (`WatchMessages`: pure constants +
  encode/decode of the status payload struct — Codable, unit-tested) so both
  targets speak the same schema. Core package is already platform-agnostic.
- iPhone: `WatchRemote` (NSObject, WCSessionDelegate) with
  `onCaptureRequested: (() -> Void)?` (delivered on main),
  `func publishStatus(_ status: WatchStatus)`, `func pushThumbnail(_ jpeg: Data)`.
  Wired in ViewfinderScreen: capture → takePhoto(); status published on
  mode/progress changes; thumbnail pushed where lastThumbnail updates.
- Watch: `WatchSessionModel` (ObservableObject) mirroring status/thumbnail,
  sends `capture` on tap.

## Testing

- Core: WatchStatus payload round-trip.
- App: WatchRemote routing with a fake session conforming to the protocol
  (capture message → onCaptureRequested on main; status encoding passed to
  session; unreachable → no send).
- Watch target: build-verified (no watch unit tests in v1).
- On-device QA: pair, tap shutter from watch (normal + NIGHT), status
  updates, thumbnail arrives; offline behavior.
