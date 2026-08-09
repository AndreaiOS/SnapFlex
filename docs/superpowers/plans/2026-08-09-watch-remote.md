# Apple Watch Remote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Watch companion app: remote shutter, live status line, last-capture thumbnail.

**Architecture:** Core carries the shared message schema (`WatchStatus` + keys). New `SnapFlexWatch` XcodeGen target (watchOS SwiftUI) embedded in the iOS app. iPhone-side `WatchRemote` wraps WCSession behind a protocol; ViewfinderScreen wires capture/status/thumbnail.

**Tech Stack:** existing + WatchConnectivity. **Spec:** `docs/superpowers/specs/2026-08-09-watch-remote-design.md`

## Global Constraints

- Watch bundle id `co.SnapFlex.watchkitapp`; DEVELOPMENT_TEAM RA4VQQK3U6; watchOS deployment 10.0. Identity: black ground, `#4ADE80` accent, monospaced fonts.
- All WatchConnectivity sends best-effort (no error surfacing beyond OFFLINE state); all iPhone-side callbacks delivered on main.
- iOS suite must stay green; watch target must BUILD (`xcodebuild build -scheme SnapFlexWatch -destination 'generic/platform=watchOS Simulator'`).
- Test commands from `/Users/andreamurru/SnapFlexBuild`: `cd Core && swift test` (53 + new); `xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'` (56 + new; FOREGROUND, BLOCKED if hung >10min). Ignore SourceKit noise.

---

### Task 1: Core schema + watch target scaffold

**Files:**
- Create: `Core/Sources/SnapFlexCore/WatchMessages.swift`, `Core/Tests/SnapFlexCoreTests/WatchMessagesTests.swift`
- Create: `Watch/SnapFlexWatchApp.swift`, `Watch/WatchContentView.swift`
- Modify: `project.yml` (new target + embed) — then `xcodegen generate`, commit regenerated project.

**Interfaces (produces):**

```swift
// Core/Sources/SnapFlexCore/WatchMessages.swift
public enum WatchMessageKey {
    public static let capture = "capture"        // watch -> phone, message key presence triggers
    public static let status = "status"          // phone -> watch, value: encoded WatchStatus
    public static let thumbnail = "thumbnail"    // phone -> watch, value: JPEG Data
}

public struct WatchStatus: Codable, Equatable, Sendable {
    public var line: String        // e.g. "READY", "NIGHT 3/8", "LONG 12s"
    public var canCapture: Bool
    public init(line: String, canCapture: Bool)
    public func encoded() -> Data          // JSON
    public static func decode(_ data: Data) -> WatchStatus?   // nil on corrupt
}
```

**project.yml (authoritative snippet — adapt keys to the file's existing style):**

```yaml
  SnapFlexWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources: [Watch]
    dependencies:
      - package: SnapFlexCore   # same local package reference the app uses; verify the existing package stanza name
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: co.SnapFlex.watchkitapp
        DEVELOPMENT_TEAM: RA4VQQK3U6
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: co.SnapFlex
        GENERATE_INFOPLIST_FILE: YES
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: 1.0
```

and on the iOS `SnapFlex` target: `dependencies: - target: SnapFlexWatch` with `embed: true` (XcodeGen embeds watch apps into `$(CONTENTS_FOLDER_PATH)/Watch` automatically for watchOS app dependencies; if the generated project mis-embeds, set `copy: { destination: watch app }`-equivalent per XcodeGen docs — resolve empirically and document).

**Watch UI v1 (static skeleton, wired in Task 2):** `SnapFlexWatchApp` (App entry) + `WatchContentView`: VStack — `Text("READY")` (system mono 12, accent #4ADE80 via Color(red:green:blue:)), 64pt `Circle()` white button (no action yet), `RoundedRectangle` 40pt gray thumbnail placeholder. Black background.

- [ ] **Step 1: Core failing tests** — WatchStatus round-trip + corrupt-decode-nil (2 tests, same style as RecipesTests). RED → implement → GREEN (53 + 2).
- [ ] **Step 2: scaffold target** — project.yml + Watch/ sources + `xcodegen generate`; verify `xcodebuild build -project SnapFlex.xcodeproj -scheme SnapFlexWatch -destination 'generic/platform=watchOS Simulator'` succeeds AND the iOS suite still passes (56).
- [ ] **Step 3: Commit** `feat(watch): core message schema and watch app scaffold`

---

### Task 2: WatchRemote + wiring + watch UI

**Files:**
- Create: `App/WatchRemote.swift`, `Tests/WatchRemoteTests.swift`
- Modify: `Watch/WatchContentView.swift` (+ create `Watch/WatchSessionModel.swift`), `App/ViewfinderScreen.swift`, `README.md`
- `xcodegen generate` after new files; commit regenerated project.

**Authoritative behavior:**
- `App/WatchRemote.swift`:

```swift
protocol WatchSessionProtocol: AnyObject {
    var isReachable: Bool { get }
    func send(_ message: [String: Any])
}

final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    var onCaptureRequested: (() -> Void)?    // called on main
    // init(session:) takes WatchSessionProtocol for tests; static func live() activates WCSession.default when supported
    func publishStatus(_ status: WatchStatus) // sends [status: status.encoded()] when reachable
    func pushThumbnail(_ jpeg: Data)          // sends [thumbnail: jpeg] when reachable
    // WCSessionDelegate: didReceiveMessage containing WatchMessageKey.capture -> DispatchQueue.main.async { onCaptureRequested?() }
}
```

  WCSession.default conformance to the protocol via a tiny adapter (WCSession's `sendMessage(_:replyHandler:errorHandler:)` wrapped fire-and-forget). Guard `WCSession.isSupported()`.
- ViewfinderScreen wiring: create `@State watchRemote = WatchRemote.live()`; `onAppear`: `watchRemote?.onCaptureRequested = { takePhoto() }`; publish status when relevant state changes (one small `watchStatusLine` computed: OFFLINE handled watch-side; here send `NIGHT n/8` when nightProgress, `LONG` + remaining when isLongExposing, else `READY` with `canCapture: !captureInFlight`) via `.onChange` of those states; push thumbnail (JPEG ~200px via UIImage resize + jpegData 0.7) where `lastThumbnail` is set (both capture sites — factor a tiny helper).
- Watch side: `WatchSessionModel` (ObservableObject, WCSessionDelegate): activates session; receives status/thumbnail messages → published vars; `sendCapture()` sends `[capture: true]` when reachable else `WKInterfaceDevice.current().play(.failure)`. `WatchContentView` binds: status line text (accent), shutter Button → sendCapture + `.play(.click)`, thumbnail Image(uiImage:) when present. OFFLINE shown when `!session.isReachable`.
- `Tests/WatchRemoteTests.swift`: fake WatchSessionProtocol capturing sends; capture message → onCaptureRequested fires on main (expectation); publishStatus encodes decodable WatchStatus; unreachable → no send recorded. (WatchRemote's delegate methods called directly with dictionaries — no real WCSession in tests.)
- README QA: `- [ ] Watch remote: shutter fires from the wrist (normal + NIGHT), status updates live, thumbnail lands; OFFLINE when phone unreachable`.

- [ ] **Step 1:** failing WatchRemote tests → RED. **Step 2:** implement all. **Step 3:** iOS suite GREEN (56 + new), Core 55, watch target still builds. **Step 4: Commit** `feat(watch): remote shutter with live status and thumbnail`

---

## Self-Review Notes

- Spec coverage: schema (T1), scaffold/embed (T1), WatchRemote + wiring + watch UI + tests + QA (T2).
- Type consistency: WatchStatus/WatchMessageKey defined once in Core, consumed by both targets; WatchSessionProtocol only in App.
- Risks flagged: XcodeGen watch embedding quirks (T1 instructed to resolve empirically and document); WCSession activation is a no-op on simulator without a paired watch — tests avoid real WCSession entirely.
