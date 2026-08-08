# LONG Exposure Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Computational long exposure (ND average / TRAILS max blend) with presets 2/5/15/30s + Bulb (5-min cap), live accumulation preview, AE lock, shake warning, HEIF output through the existing CaptureStore.

**Architecture:** Pure state machine in SnapFlexCore (`LongExposureSession`); Metal accumulator with two kernels; engine-managed frame fan-out (overlay driver + accumulator share the existing `AVCaptureVideoDataOutput` frames); `@Observable` controller drives the session timer and readout; UI adds a LONG chip, ND/TRAILS toggle, and an exposure HUD.

**Tech Stack:** existing stack (SwiftUI, AVFoundation, Metal, SnapFlexCore package). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-08-long-exposure-design.md`

## Global Constraints

- Presets exactly 2/5/15/30 seconds; Bulb hard cap **300s**; exposures accumulating **< 1s** are discarded, never saved.
- Shutter semantics: preset running → tap **cancels and discards**; bulb running → tap **stops and saves** (if ≥ 1s).
- Interruption/backgrounding mid-exposure: finalize and save (≥ 1s rule applies).
- ND = running per-pixel mean; TRAILS = per-pixel max. Accumulation texture `rgba32float`.
- Output: max-quality HEIF via existing `CaptureStore.store` (`CaptureResource(kind: .processedHEIF)`).
- Exposure lock on start: if manual ISO+shutter set, keep them; otherwise `lockAutoExposure()`; restore on finish.
- Thread contracts: frames arrive on the device's videoQueue; UI state is `@MainActor`; accumulator state guarded by NSLock (OverlayPipeline pattern).
- Test commands: Core `cd Core && swift test`; app `xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -quiet`. Run `xcodegen generate` after adding files; commit the regenerated .xcodeproj.

## File Structure

```
Core/Sources/SnapFlexCore/LongExposure.swift        # LongMode, LongBlend, LongExposureSession
Core/Tests/SnapFlexCoreTests/LongExposureTests.swift
LongExposure/LongExposureShaders.metal              # accumulateAverage/accumulateMax + accumulationFragment
LongExposure/LongExposureAccumulator.swift          # Metal accumulation + HEIF readout
LongExposure/LongExposureController.swift           # @Observable session driver
App/LongPreviewMetalView.swift                      # live accumulation view
App/LongExposureHUD.swift                           # progress ring, elapsed, shake warning
Tests/LongAccumulatorTests.swift
Tests/LongControllerTests.swift
(modified) Engine/CameraDevice.swift, Engine/CameraEngine.swift, Engine/RealCameraDevice.swift,
(modified) Overlay/OverlayFrameDriver.swift, App/TopBar.swift, App/ViewfinderScreen.swift, App/SnapFlexApp.swift
```

---

### Task 1: Core — LongMode, LongBlend, LongExposureSession

**Files:**
- Create: `Core/Sources/SnapFlexCore/LongExposure.swift`
- Test: `Core/Tests/SnapFlexCoreTests/LongExposureTests.swift`

**Interfaces:**
- Produces (all public, Sendable, Equatable):

```swift
public enum LongBlend: String, CaseIterable, Sendable { case nd = "ND", trails = "TRAILS" }

public enum LongMode: Equatable, Sendable {
    case off
    case preset(seconds: Int)      // one of LongMode.presetSeconds
    case bulb
    public static let presetSeconds = [2, 5, 15, 30]
    public static let bulbCapSeconds: Double = 300
    public var next: LongMode { ... }   // off→2→5→15→30→bulb→off (chip cycling)
    public var label: String { ... }    // "LONG OFF", "LONG 2s", ..., "LONG BULB"
}

public struct LongExposureSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case exposing(elapsed: Double)
        case finished(save: Bool)
    }
    public let mode: LongMode                  // never .off
    public private(set) var phase: Phase       // starts .exposing(elapsed: 0)
    public init(mode: LongMode)
    public mutating func tick(_ delta: Double) // advance; auto-finish(save: true) at preset target or bulb cap
    public mutating func shutterTapped()       // preset → finished(save: false); bulb → finished(save: elapsed >= 1)
    public mutating func interrupted()         // finished(save: elapsed >= 1)
    public var elapsed: Double
    public var targetSeconds: Double           // preset value, or bulbCapSeconds for bulb
    public var progress: Double?               // elapsed/target for presets, nil for bulb
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// Core/Tests/SnapFlexCoreTests/LongExposureTests.swift
import Testing
@testable import SnapFlexCore

@Suite struct LongExposureTests {
    @Test func modeCyclesThroughAllStates() {
        var mode = LongMode.off
        var seen: [LongMode] = []
        for _ in 0..<6 { mode = mode.next; seen.append(mode) }
        #expect(seen == [.preset(seconds: 2), .preset(seconds: 5), .preset(seconds: 15),
                         .preset(seconds: 30), .bulb, .off])
    }

    @Test func presetAutoFinishesAndSaves() {
        var session = LongExposureSession(mode: .preset(seconds: 2))
        session.tick(1.9)
        #expect(session.phase == .exposing(elapsed: 1.9))
        #expect(session.progress == 0.95)
        session.tick(0.2)
        #expect(session.phase == .finished(save: true))
    }

    @Test func presetShutterTapCancelsWithoutSaving() {
        var session = LongExposureSession(mode: .preset(seconds: 15))
        session.tick(5)
        session.shutterTapped()
        #expect(session.phase == .finished(save: false))
    }

    @Test func bulbStopsAndSavesAfterOneSecond() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(3)
        #expect(session.progress == nil)
        session.shutterTapped()
        #expect(session.phase == .finished(save: true))
    }

    @Test func bulbUnderOneSecondDiscards() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(0.5)
        session.shutterTapped()
        #expect(session.phase == .finished(save: false))
    }

    @Test func bulbAutoFinishesAtCap() {
        var session = LongExposureSession(mode: .bulb)
        session.tick(LongMode.bulbCapSeconds + 1)
        #expect(session.phase == .finished(save: true))
    }

    @Test func interruptionSavesWhenLongEnough() {
        var session = LongExposureSession(mode: .preset(seconds: 30))
        session.tick(4)
        session.interrupted()
        #expect(session.phase == .finished(save: true))
        var short = LongExposureSession(mode: .preset(seconds: 30))
        short.tick(0.3)
        short.interrupted()
        #expect(short.phase == .finished(save: false))
    }

    @Test func ticksAfterFinishAreNoOps() {
        var session = LongExposureSession(mode: .preset(seconds: 2))
        session.tick(5)
        let done = session
        session.tick(1)
        session.shutterTapped()
        #expect(session == done)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd Core && swift test` → FAIL (types missing).

- [ ] **Step 3: Implement**

```swift
// Core/Sources/SnapFlexCore/LongExposure.swift
public enum LongBlend: String, CaseIterable, Sendable {
    case nd = "ND"
    case trails = "TRAILS"
}

public enum LongMode: Equatable, Sendable {
    case off
    case preset(seconds: Int)
    case bulb

    public static let presetSeconds = [2, 5, 15, 30]
    public static let bulbCapSeconds: Double = 300

    public var next: LongMode {
        switch self {
        case .off: return .preset(seconds: Self.presetSeconds[0])
        case .preset(let seconds):
            if let index = Self.presetSeconds.firstIndex(of: seconds),
               index + 1 < Self.presetSeconds.count {
                return .preset(seconds: Self.presetSeconds[index + 1])
            }
            return .bulb
        case .bulb: return .off
        }
    }

    public var label: String {
        switch self {
        case .off: return "LONG OFF"
        case .preset(let seconds): return "LONG \(seconds)s"
        case .bulb: return "LONG BULB"
        }
    }
}

public struct LongExposureSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case exposing(elapsed: Double)
        case finished(save: Bool)
    }

    public let mode: LongMode
    public private(set) var phase: Phase = .exposing(elapsed: 0)
    private static let minimumSaveSeconds = 1.0

    public init(mode: LongMode) {
        self.mode = mode
    }

    public var elapsed: Double {
        if case .exposing(let elapsed) = phase { return elapsed }
        return 0
    }

    public var targetSeconds: Double {
        if case .preset(let seconds) = mode { return Double(seconds) }
        return LongMode.bulbCapSeconds
    }

    public var progress: Double? {
        guard case .preset = mode, case .exposing(let elapsed) = phase else { return nil }
        return min(elapsed / targetSeconds, 1)
    }

    public mutating func tick(_ delta: Double) {
        guard case .exposing(let elapsed) = phase else { return }
        let advanced = elapsed + delta
        if advanced >= targetSeconds {
            phase = .finished(save: true)
        } else {
            phase = .exposing(elapsed: advanced)
        }
    }

    public mutating func shutterTapped() {
        guard case .exposing(let elapsed) = phase else { return }
        switch mode {
        case .bulb: phase = .finished(save: elapsed >= Self.minimumSaveSeconds)
        default: phase = .finished(save: false)
        }
    }

    public mutating func interrupted() {
        guard case .exposing(let elapsed) = phase else { return }
        phase = .finished(save: elapsed >= Self.minimumSaveSeconds)
    }
}
```

- [ ] **Step 4: Verify green** — `cd Core && swift test` → all pass.
- [ ] **Step 5: Commit** — `git add Core/ && git commit -m "feat(core): add long exposure session state machine"`

---

### Task 2: Metal accumulator — kernels, accumulation, HEIF readout

**Files:**
- Create: `LongExposure/LongExposureShaders.metal`
- Create: `LongExposure/LongExposureAccumulator.swift`
- Test: `Tests/LongAccumulatorTests.swift`
- Modify: `project.yml` (add `LongExposure` to the SnapFlex target's sources list) then `xcodegen generate`

**Interfaces:**
- Consumes: `LongBlend` (SnapFlexCore), Metal.
- Produces:

```swift
final class LongExposureAccumulator {
    init?(device: MTLDevice)                    // nil if pipelines fail
    func begin(blend: LongBlend)                // resets state; texture allocated lazily at first frame's size
    func accumulate(texture: MTLTexture, commandQueue: MTLCommandQueue)  // one BGRA frame in
    var frameCount: Int { get }                 // frames accumulated since begin (lock-guarded)
    var accumulationTexture: MTLTexture? { get } // rgba32float, lock-guarded (preview reads this)
    func readoutImageData() -> Data?            // HEIF (max quality) of the current accumulation
}
```

- Kernels: `accumulateAverageKernel` — `acc = acc + (frame - acc) / n` with `n` (1-based frame number) in a constant buffer; `accumulateMaxKernel` — `acc = max(acc, frame)`. First frame (n == 1) simply writes the frame in both modes.
- Render fragment for Task 6: `accumulationFragment` + reuse of a fullscreen-triangle vertex (duplicate `overlayVertex` as `longVertex` in this file to keep files self-contained) sampling the float texture, alpha 1 (opaque).
- Readout: `CIImage(mtlTexture:options:)` (with `.colorSpace` sRGB and vertical flip via `.oriented(.downMirrored)` if needed — verify visually in tests by pixel position), then `CIContext.heifRepresentation(of:format:colorSpace:options:)` at quality 1.0.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/LongAccumulatorTests.swift
import Testing
import Metal
import SnapFlexCore
@testable import SnapFlex

@Suite struct LongAccumulatorTests {
    func makeTexture(device: MTLDevice, gray: UInt8, side: Int = 8) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8]()
        for _ in 0..<(side * side) { pixels.append(contentsOf: [gray, gray, gray, 255]) }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: side * 4)
        return texture
    }

    func firstPixel(_ texture: MTLTexture) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: texture.width * 16,
                         from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return pixel
    }

    func setup() throws -> (LongExposureAccumulator, MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let accumulator = LongExposureAccumulator(device: device),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "metal-unavailable", code: 1)
        }
        return (accumulator, device, queue)
    }

    @Test func averageOfTwoFramesIsMean() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 100), commandQueue: queue)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 200), commandQueue: queue)
        #expect(accumulator.frameCount == 2)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        let expected = (100.0 / 255.0 + 200.0 / 255.0) / 2.0
        #expect(abs(Double(pixel[0]) - expected) < 0.01)
    }

    @Test func maxKeepsBrightestPixel() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .trails)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 180), commandQueue: queue)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 60), commandQueue: queue)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        #expect(abs(Double(pixel[0]) - 180.0 / 255.0) < 0.01)
    }

    @Test func beginResetsState() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 255), commandQueue: queue)
        accumulator.begin(blend: .nd)
        #expect(accumulator.frameCount == 0)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 10), commandQueue: queue)
        let pixel = firstPixel(accumulator.accumulationTexture!)
        #expect(abs(Double(pixel[0]) - 10.0 / 255.0) < 0.01)
    }

    @Test func readoutProducesDecodableHEIF() throws {
        let (accumulator, device, queue) = try setup()
        accumulator.begin(blend: .nd)
        accumulator.accumulate(texture: makeTexture(device: device, gray: 128, side: 16), commandQueue: queue)
        let data = try #require(accumulator.readoutImageData())
        let image = try #require(UIImage(data: data))
        #expect(image.size.width == 16 && image.size.height == 16)
    }
}
```

(Add `import UIKit` for UIImage.)

- [ ] **Step 2: Run to verify failure** — app test command → BUILD FAIL.

- [ ] **Step 3: Implement shaders**

```metal
// LongExposure/LongExposureShaders.metal
#include <metal_stdlib>
using namespace metal;

kernel void accumulateAverageKernel(texture2d<float, access::read> frame [[texture(0)]],
                                    texture2d<float, access::read_write> acc [[texture(1)]],
                                    constant uint &frameNumber [[buffer(0)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= frame.get_width() || gid.y >= frame.get_height()) return;
    float4 sample = frame.read(gid);
    if (frameNumber == 1) {
        acc.write(sample, gid);
    } else {
        float4 current = acc.read(gid);
        acc.write(current + (sample - current) / float(frameNumber), gid);
    }
}

kernel void accumulateMaxKernel(texture2d<float, access::read> frame [[texture(0)]],
                                texture2d<float, access::read_write> acc [[texture(1)]],
                                constant uint &frameNumber [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= frame.get_width() || gid.y >= frame.get_height()) return;
    float4 sample = frame.read(gid);
    if (frameNumber == 1) {
        acc.write(sample, gid);
    } else {
        acc.write(max(acc.read(gid), sample), gid);
    }
}

struct LongVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex LongVertexOut longVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    LongVertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

fragment float4 accumulationFragment(LongVertexOut in [[stage_in]],
                                     texture2d<float, access::sample> acc [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    float4 color = acc.sample(s, in.uv);
    return float4(clamp(color.rgb, 0.0, 1.0), 1.0);
}
```

- [ ] **Step 4: Implement LongExposureAccumulator**

```swift
// LongExposure/LongExposureAccumulator.swift
import CoreImage
import Metal
import SnapFlexCore

final class LongExposureAccumulator {
    private let device: MTLDevice
    private let averagePipeline: MTLComputePipelineState
    private let maxPipeline: MTLComputePipelineState
    private let ciContext: CIContext
    private let lock = NSLock()

    private var blend: LongBlend = .nd
    private var _frameCount = 0
    private var _accumulationTexture: MTLTexture?

    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _frameCount
    }

    var accumulationTexture: MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return _accumulationTexture
    }

    init?(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let averageFn = library.makeFunction(name: "accumulateAverageKernel"),
              let maxFn = library.makeFunction(name: "accumulateMaxKernel"),
              let averagePipeline = try? device.makeComputePipelineState(function: averageFn),
              let maxPipeline = try? device.makeComputePipelineState(function: maxFn)
        else { return nil }
        self.device = device
        self.averagePipeline = averagePipeline
        self.maxPipeline = maxPipeline
        self.ciContext = CIContext(mtlDevice: device)
    }

    func begin(blend: LongBlend) {
        lock.lock(); defer { lock.unlock() }
        self.blend = blend
        _frameCount = 0
        _accumulationTexture = nil
    }

    func accumulate(texture: MTLTexture, commandQueue: MTLCommandQueue) {
        lock.lock()
        if _accumulationTexture == nil ||
            _accumulationTexture!.width != texture.width ||
            _accumulationTexture!.height != texture.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: texture.width, height: texture.height,
                mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            _accumulationTexture = device.makeTexture(descriptor: descriptor)
            _frameCount = 0
        }
        _frameCount += 1
        var frameNumber = UInt32(_frameCount)
        let accumulation = _accumulationTexture!
        let pipeline = blend == .nd ? averagePipeline : maxPipeline
        lock.unlock()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(accumulation, index: 1)
        encoder.setBytes(&frameNumber, length: MemoryLayout<UInt32>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func readoutImageData() -> Data? {
        guard let texture = accumulationTexture,
              let ciImage = CIImage(mtlTexture: texture, options: [
                  .colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
              ])
        else { return nil }
        let oriented = ciImage.oriented(.downMirrored)   // Metal textures are top-left origin
        return ciContext.heifRepresentation(
            of: oriented, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0])
    }
}
```

Note for the implementer: if the readout test shows the HEIF is produced but mirrored/flipped, adjust the `.oriented(...)` value — the test only checks decodability and size, orientation is verified on device.

- [ ] **Step 5: project.yml** — change the SnapFlex target's `sources: [App, Engine, Overlay]` to `sources: [App, Engine, Overlay, LongExposure]`, run `xcodegen generate`.
- [ ] **Step 6: Verify green** — app test command → all pass (existing + 4 new).
- [ ] **Step 7: Commit** — `git add LongExposure/ Tests/ project.yml SnapFlex.xcodeproj && git commit -m "feat(long): add Metal accumulator with ND and TRAILS kernels"`

---

### Task 3: Exposure lock protocol + engine LONG state

**Files:**
- Modify: `Engine/CameraDevice.swift` (protocol), `Engine/RealCameraDevice.swift`, `Engine/CameraEngine.swift`
- Modify: `Tests/FakeCameraDevice.swift`
- Test: `Tests/CameraEngineTests.swift` (additions)

**Interfaces:**
- Protocol additions: `func lockAutoExposure()` (real device: `device.exposureMode = .locked` via `withLockedDevice`), `func unlockAutoExposure()` (restore `.continuousAutoExposure` if supported). Fake records `lockCalls: Int` / `unlockCalls: Int`.
- Engine additions: `var longMode: LongMode` (default `.off`), `var longBlend: LongBlend` (default `.nd`) — both plain published vars; `func prepareLongExposure()` — if `values.iso == nil || values.shutterSeconds == nil` calls `device.lockAutoExposure()`; `func endLongExposure()` — calls `device.unlockAutoExposure()` only if it locked (track with a private flag), then re-applies manual values if any (call `applyExposure()` equivalent via existing setters).

- [ ] **Step 1: Write the failing tests** (add to CameraEngineTests)

```swift
    @Test func prepareLongLocksAEOnlyWhenAuto() {
        let (engine, device) = makeEngine()
        engine.prepareLongExposure()
        #expect(device.lockCalls == 1)
        engine.endLongExposure()
        #expect(device.unlockCalls == 1)
    }

    @Test func prepareLongKeepsManualExposure() {
        let (engine, device) = makeEngine()
        engine.setISO(100)
        engine.setShutter(1.0 / 60)
        engine.prepareLongExposure()
        #expect(device.lockCalls == 0)
        engine.endLongExposure()
        #expect(device.unlockCalls == 0)
    }
```

- [ ] **Step 2: RED** — build fails (protocol members missing).
- [ ] **Step 3: Implement** protocol members in CameraDevice.swift, RealCameraDevice (via `withLockedDevice`, guarding `isExposureModeSupported(.locked)`), FakeCameraDevice counters, engine methods with the `didLockAE` flag.
- [ ] **Step 4: GREEN** — full app suite passes.
- [ ] **Step 5: Commit** — `git add Engine/ Tests/ && git commit -m "feat(engine): add AE lock protocol and LONG mode state"`

---

### Task 4: Frame fan-out — engine-managed tap

**Files:**
- Modify: `Overlay/OverlayFrameDriver.swift`, `Engine/CameraEngine.swift`

**Interfaces:**
- `OverlayFrameDriver`: expose `func ingest(_ pixelBuffer: CVPixelBuffer)` (rename of the private `handle`); its `bind(attach:)`/self-attach logic is REMOVED — the driver no longer talks to the device. Its `settings` setter keeps forwarding to the pipeline but no longer attaches/detaches.
- `CameraEngine`: owns the tap. New private `var frameTapActive = false`; `var longFrameTap: ((CVPixelBuffer) -> Void)?` (set by the app wiring in Task 5; called on videoQueue). New private `func updateFrameTap()` — desired = `overlaySettings.anyEnabled || longExposureRunning`; when the desired state changes, call `realDevice.setVideoFrameHandler` with a closure fanning out to `overlayDriver?.ingest(...)` (only when `overlaySettings.anyEnabled`) and `longFrameTap?(...)` (only while `longExposureRunning`), or nil. `overlaySettings.didSet` and the LONG start/stop paths (Task 5) call `updateFrameTap()`. Add `private(set) var longExposureRunning = false` with internal setters used by Task 5.
- CameraEngine init: the old `overlayDriver.bind { ... }` call is replaced by storing the real device reference (`private let realDevice: RealCameraDevice?`) and calling `updateFrameTap()`.
- Existing behavior must hold: toggling overlays on/off still attaches/detaches the video output (existing engine test `overlaySettingsPublishWithoutDriver` must stay green).

- [ ] **Step 1:** Refactor per the interfaces (no new tests — covered by existing suite + Task 5's tests; this is a pure plumbing move).
- [ ] **Step 2:** Full app suite green.
- [ ] **Step 3: Commit** — `git add Overlay/ Engine/ && git commit -m "refactor(engine): centralize video frame fan-out in the engine"`

---### Task 5: LongExposureController

**Files:**
- Create: `LongExposure/LongExposureController.swift`
- Test: `Tests/LongControllerTests.swift`

**Interfaces:**

```swift
@Observable @MainActor
final class LongExposureController {
    private(set) var session: LongExposureSession?
    var isExposing: Bool { session != nil }
    private(set) var elapsed: Double = 0
    private(set) var progress: Double?          // nil for bulb
    var previewTexture: MTLTexture? { accumulator.accumulationTexture }
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue

    init?()                                      // creates its own device/queue/accumulator
    // Test seam: internal init(accumulator:device:queue:) if needed

    /// Starts a session; `onFinished` fires exactly once with HEIF data (nil = discard).
    func start(mode: LongMode, blend: LongBlend, onFinished: @escaping (Data?) -> Void)
    func shutterTapped()
    func interrupted()
    /// nonisolated — called on videoQueue with each camera frame while running.
    nonisolated func ingest(_ pixelBuffer: CVPixelBuffer)
}
```

- Timer: a `Task` loop sleeping 100ms, calling `session.tick(0.1)` and syncing `elapsed`/`progress`; when phase becomes `.finished(save:)`, stop the loop, if save && accumulator.frameCount > 0 → `readoutImageData()` on a background task → `onFinished(data)`; else `onFinished(nil)`. Clear `session` after.
- `ingest`: converts CVPixelBuffer → MTLTexture via its own `CVMetalTextureCache` (copy the OverlayFrameDriver pattern) and calls `accumulator.accumulate` — but ONLY while a session is exposing (guard with a lock-protected `running` flag toggled by start/finish, since ingest is nonisolated).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/LongControllerTests.swift
import Testing
import SnapFlexCore
@testable import SnapFlex

@MainActor @Suite struct LongControllerTests {
    @Test func presetSessionAutoFinishes() async throws {
        let controller = try #require(LongExposureController())
        var result: Data?? = nil
        controller.start(mode: .preset(seconds: 2), blend: .nd) { result = .some($0) }
        #expect(controller.isExposing)
        try await Task.sleep(for: .seconds(2.6))
        #expect(result != nil)          // finished
        #expect(result! == nil)         // no frames accumulated → discard
        #expect(!controller.isExposing)
    }

    @Test func shutterTapCancelsPreset() async throws {
        let controller = try #require(LongExposureController())
        var result: Data?? = nil
        controller.start(mode: .preset(seconds: 30), blend: .nd) { result = .some($0) }
        try await Task.sleep(for: .milliseconds(300))
        controller.shutterTapped()
        try await Task.sleep(for: .milliseconds(300))
        #expect(result != nil && result! == nil)
        #expect(!controller.isExposing)
    }
}
```

- [ ] **Step 2: RED**, **Step 3: implement**, **Step 4: GREEN** (full suite).
- [ ] **Step 5: Commit** — `git add LongExposure/ Tests/ SnapFlex.xcodeproj && git commit -m "feat(long): add exposure controller with timer loop and frame ingestion"`

---

### Task 6: Live accumulation preview view

**Files:**
- Create: `App/LongPreviewMetalView.swift`

**Interfaces:**
- `LongPreviewMetalView: UIViewRepresentable` — same Coordinator/MTKView structure as `OverlayMetalView`, but opaque (`isOpaque = true`, black clear color), render pipeline `longVertex` + `accumulationFragment`, drawing `controller.previewTexture` each frame at 30fps; renders nothing (keeps last clear) while texture is nil.
- Build-verified task (no simulator camera); tests stay green.

- [ ] **Step 1:** Implement per OverlayMetalView pattern. **Step 2:** build + suite green. **Step 3: Commit** — `feat(ui): add live accumulation preview view`

---

### Task 7: UI — LONG chip, ND/TRAILS toggle, exposure HUD, shutter routing

**Files:**
- Create: `App/LongExposureHUD.swift`
- Modify: `App/TopBar.swift`, `App/ViewfinderScreen.swift`, `App/SnapFlexApp.swift`, `Engine/CameraEngine.swift` (start/stop orchestration)

**Interfaces:**
- TopBar: LONG chip showing `engine.longMode.label`, tap → `engine.longMode = engine.longMode.next`; when `engine.longMode != .off`, an adjacent chip shows `engine.longBlend.rawValue`, tap toggles nd/trails. Both chips rotate with the device like the others.
- Engine orchestration (in CameraEngine): `func startLong(controller: LongExposureController, store onFinished: @escaping (Data?) -> Void)` is NOT added — instead the ViewfinderScreen drives it (UI owns the controller):
  - `takePhoto()` routing: if `engine.longMode != .off` and controller not exposing → begin: `engine.prepareLongExposure()`, `engine.longExposureRunning = true` + `updateFrameTap()` (expose an engine method `func beginLongFrames(tap:)` that sets `longFrameTap` + running flag + calls updateFrameTap, and `func endLongFrames()` for teardown), `controller.start(mode:blend:)` with completion: on data → wrap as `CaptureResource(kind: .processedHEIF, data:)` and `store.store([resource])` + thumbnail update; always `engine.endLongFrames()` + `engine.endLongExposure()`.
  - If controller IS exposing → `controller.shutterTapped()`.
  - Timer countdown flow is bypassed while LONG is active (LONG replaces the self-timer; guard at the top of takePhoto).
- `LongExposureHUD(controller: LongExposureController)` view: progress ring around the shutter position (a `Circle().trim(from: 0, to: progress)` stroke in accent, indeterminate ring style for bulb), elapsed monospace text (`%.1fs`), shake warning icon (`exclamationmark.triangle`) driven by a `ShakeModel` (CMMotionManager rotationRate magnitude > 0.35 rad/s sustained — simple @Observable like LevelModel, started while HUD visible).
- ViewfinderScreen: while `controller.isExposing` → `LongPreviewMetalView` replaces the preview area (over PreviewView), HUD overlays, chrome interactions limited to the shutter.
- ViewfinderScreen state: `@State private var longController = LongExposureController()`; if nil (no Metal), LONG chip hidden (pass a flag to TopBar).
- Interruption/background: `.onChange(of: scenePhase)` → if not `.active` and exposing → `controller.interrupted()`; also `engine.status == .interrupted` while exposing → `controller.interrupted()` (`.onChange(of: engine.status)`).
- Build-verified; existing suite green.

- [ ] **Step 1:** Implement all wiring per interfaces. **Step 2:** build + suite green. **Step 3: Commit** — `feat(ui): wire LONG exposure mode into viewfinder and top bar`

---

### Task 8: Full sweep + README QA additions

**Files:**
- Modify: `README.md`

- [ ] **Step 1:** Run both suites; all green.
- [ ] **Step 2:** Append to the README QA checklist:

```markdown
- [ ] LONG ND 5s on running water produces silk effect; live preview builds up
- [ ] LONG TRAILS on moving lights produces trails
- [ ] BULB: starts on tap, stops+saves on second tap; auto-stops at 5 min
- [ ] Preset tap-to-cancel discards (nothing saved to Photos)
- [ ] Backgrounding mid-exposure saves the partial result (if ≥ 1s)
- [ ] Shake warning appears handheld, absent on tripod
- [ ] AE stays locked during the exposure (no brightness pumping in preview)
```

- [ ] **Step 3: Commit** — `docs: add LONG exposure QA checklist`

---

## Self-Review Notes

- Spec coverage: blend modes (T2), durations+bulb+cap (T1), live preview (T2/T6), AE lock (T3), shake warning (T7), HEIF via CaptureStore (T7), cancel/stop semantics (T1/T7), interruption finalize (T1/T7), out-of-scope items honored (no DNG, no alignment).
- Type consistency: `LongMode`/`LongBlend` defined once in Core (T1), consumed by T2/T3/T5/T7; `ingest(_:)` name shared by driver and controller deliberately (same role).
- Known simplification: controller tests exercise timer/cancel paths without camera frames (simulator has no camera); accumulation math is covered by T2's synthetic-texture tests; the full pipeline is device QA.
