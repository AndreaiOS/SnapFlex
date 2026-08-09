import AVFoundation
import SwiftUI
import SnapFlexCore
import UIKit

/// Self-locking holder for a background task identifier, shared between the
/// expiration handler (main thread) and the post-await completion path
/// (arbitrary executor). `end()` is atomic and idempotent — it clears `id`
/// under the lock before calling `endBackgroundTask`, so a race between the
/// two callers can't double-end the same task.
private final class LongExposureBackgroundGuard {
    private let lock = NSLock()
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin(name: String) {
        lock.lock(); defer { lock.unlock() }
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        lock.lock()
        let current = id
        id = .invalid
        lock.unlock()
        if current != .invalid {
            UIApplication.shared.endBackgroundTask(current)
        }
    }
}

struct ViewfinderScreen: View {
    let engine: CameraEngine
    let session: AVCaptureSession
    let driver: OverlayFrameDriver?
    let store: CaptureStore

    @State private var selected: SelectedParameter?
    @State private var shutterFlash = false
    @State private var aspect: AspectRatio = .fourThree
    @State private var showGrid = false
    @State private var showLevel = false
    @State private var timerDuration = 0
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var lastThumbnail: UIImage?
    @State private var thumbnailID = 0
    @State private var zoomBase: Double = 1
    @State private var orientation = OrientationModel()
    @State private var longController = LongExposureController()
    @State private var chrome = ChromeVisibility()
    @State private var chromeTask: Task<Void, Never>?
    @State private var photosDenied = false
    @State private var pendingSaves = 0
    @State private var captureInFlight = false
    @State private var captureFailed = false
    @State private var nightProgress: (Int, Int)?
    @State private var displayZoom: Double = 1
    @State private var recipeBook = RecipeBook(data: UserDefaults.standard.data(forKey: "recipes.book") ?? Data())
    @State private var showSaveRecipeAlert = false
    @State private var newRecipeName = ""
    @State private var watchRemote = WatchRemote.live()
    @Environment(\.scenePhase) private var scenePhase

    private var isLongExposing: Bool { longController?.isExposing == true }

    /// Mirrors the on-screen readout for the watch's status line.
    private var watchStatusLine: WatchStatus {
        if let nightProgress {
            return WatchStatus(line: "NIGHT \(nightProgress.0)/\(nightProgress.1)", canCapture: false)
        }
        if isLongExposing, let longController {
            let remaining = max(0, (longController.session?.targetSeconds ?? 0) - longController.elapsed)
            return WatchStatus(line: "LONG " + String(format: "%.0fs", remaining), canCapture: false)
        }
        return WatchStatus(line: "READY", canCapture: !captureInFlight)
    }

    /// Small Equatable summary of the state `watchStatusLine` depends on, so a
    /// single `.onChange` can drive republishing instead of one per field.
    private var watchStatusKey: String { "\(nightProgress?.0 ?? -1)|\(isLongExposing)|\(captureInFlight)" }

    private var chromeBlocked: Bool {
        selected != nil || isLongExposing || countdown != nil || engine.status == .interrupted
            || nightProgress != nil
    }

    private var chromeHidden: Bool { chrome.state == .minimal }

    private var showLoupe: Bool { selected == .focus && engine.values.focusPosition != nil && !isLongExposing }

    private var loupeCrosshair: some View {
        ZStack {
            Rectangle().fill(Theme.accent).frame(width: 8, height: 2)
            Rectangle().fill(Theme.accent).frame(width: 2, height: 8)
        }
    }

    private func chromeInteraction() {
        withAnimation(Theme.motion(Theme.springBouncy)) {
            chrome.interaction(at: Date().timeIntervalSinceReferenceDate)
        }
    }

    /// Throttled entry point for high-frequency interaction sources (drag deltas during
    /// dial scrubs/pinches, per-frame value changes): skips the mutating/animated path
    /// entirely when it wouldn't change anything, avoiding a full body re-eval at input rate.
    private func chromeInteractionThrottled() {
        let now = Date().timeIntervalSinceReferenceDate
        guard chrome.needsInteraction(at: now) else { return }
        withAnimation(Theme.motion(Theme.springBouncy)) {
            chrome.interaction(at: now)
        }
    }

    var body: some View {
        ZStack {
            PreviewView(session: session, onCaptureEvent: { takePhoto() })
                .ignoresSafeArea()
            if let longController, longController.isExposing {
                LongPreviewMetalView(controller: longController)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if let driver, engine.overlaySettings.peakingEnabled || engine.overlaySettings.zebraEnabled {
                OverlayMetalView(driver: driver)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            Color.white
                .ignoresSafeArea()
                .opacity(shutterFlash ? 0.7 : 0)
                .allowsHitTesting(false)

            if let countdown {
                Text("\(countdown)")
                    .font(Theme.valueFont(64))
                    .foregroundStyle(Theme.accent)
                    .rotatesWithDevice(orientation.uiAngle)
                    .allowsHitTesting(false)
            }

            if engine.status == .interrupted {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    Text("Camera paused")
                        .font(Theme.valueFont(16))
                        .foregroundStyle(.white)
                }
                .allowsHitTesting(false)
            }

            GridLevelOverlay(showGrid: showGrid, showLevel: showLevel)
                .ignoresSafeArea()

            AspectMask(aspect: aspect)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if photosDenied {
                    photosDeniedBanner
                }
                Group {
                    TopBar(engine: engine, aspect: $aspect, timerDuration: $timerDuration,
                           showGrid: $showGrid, showLevel: $showLevel,
                           rotation: orientation.uiAngle,
                           longAvailable: longController != nil,
                           recipes: recipeBook.recipes,
                           onApplyRecipe: apply,
                           onSaveRecipe: beginSaveRecipe,
                           onDeleteRecipe: deleteRecipe)
                        .disabled(isLongExposing || captureInFlight)
                        .opacity(isLongExposing || captureInFlight ? 0.4 : 1)
                    if engine.overlaySettings.histogramEnabled, let bins = engine.histogramBins {
                        HStack {
                            Spacer()
                            HistogramView(bins: bins).padding(8)
                        }
                    }
                }
                .opacity(chromeHidden ? 0 : 1)
                .scaleEffect(chromeHidden ? 0.96 : 1, anchor: .top)
                .allowsHitTesting(!chromeHidden)
                .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
                Spacer()
                if let longController, longController.isExposing {
                    LongExposureHUD(controller: longController)
                        .padding(.bottom, 4)
                }
                if engine.overlaySettings.waveformEnabled, let driver {
                    WaveformView(driver: driver)
                        .frame(width: 118, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                Text("LUMA")
                                    .font(Theme.valueFont(6))
                                    .tracking(1.2)
                                    .foregroundStyle(Color.white.opacity(0.35))
                                    .padding(4)
                            }
                        )
                        .allowsHitTesting(false)
                        .padding(.leading, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(chromeHidden ? 0 : 1)
                        .scaleEffect(chromeHidden ? 0.96 : 1, anchor: .bottom)
                        .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
                }
                Group {
                    if let parameter = selected {
                        ParameterDial(engine: engine, parameter: parameter)
                    }
                    ParameterBar(engine: engine, selected: $selected,
                                 rotation: orientation.uiAngle)
                        .padding(.vertical, 8)
                        .background(Theme.chrome)
                }
                .disabled(isLongExposing)
                .opacity(isLongExposing ? 0.4 : 1)
                .opacity(chromeHidden ? 0 : 1)
                .scaleEffect(chromeHidden ? 0.96 : 1, anchor: .bottom)
                .allowsHitTesting(!chromeHidden)
                .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
                bottomRow
                    .padding(.vertical, 10)
                    .background(Theme.chrome.opacity(chromeHidden ? 0 : 1))
                    .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
            }

            if chromeHidden {
                Text(chromeReadout(values: engine.values, longMode: engine.longMode,
                                    longBlend: engine.longBlend, processing: engine.processingLevel))
                    .font(Theme.valueFont(11))
                    .tracking(0.5)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .rotatesWithDevice(orientation.uiAngle)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(Theme.motion(Theme.springStandard), value: chromeHidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if let nightProgress {
                let progressText = "NIGHT \(nightProgress.0)/\(nightProgress.1)"
                Text(progressText)
                    .font(Theme.valueFont(11))
                    .tracking(0.5)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(Theme.motion(Theme.springStandard), value: progressText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
                    .rotatesWithDevice(orientation.uiAngle)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 44)
            }

            if captureFailed {
                Text("CAPTURE FAILED")
                    .font(Theme.valueFont(11))
                    .tracking(0.5)
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .overlay(Capsule().strokeBorder(Theme.warning.opacity(0.5), lineWidth: 1))
                    .rotatesWithDevice(orientation.uiAngle)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 44)
            }

            if showLoupe, let driver {
                LoupeView(driver: driver)
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .overlay(loupeCrosshair)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 120)
            }
        }
        .animation(Theme.motion(Theme.springBouncy), value: showLoupe)
        .statusBarHidden()
        .onAppear {
            loadSettings()
            orientation.start()
            refreshSaveState()
            chrome.blocked = chromeBlocked
            chrome.interaction(at: Date().timeIntervalSinceReferenceDate)
            watchRemote?.onCaptureRequested = { takePhoto() }
            publishWatchStatus()
            chromeTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    withAnimation(Theme.motion(Theme.springStandard)) {
                        chrome.tick(now: Date().timeIntervalSinceReferenceDate)
                    }
                    // Rides the existing 500ms tick instead of a dedicated
                    // .onChange, so the watch sees a live-enough LONG
                    // countdown without adding to the type-checker load on
                    // this view's already-large modifier chain.
                    if isLongExposing { publishWatchStatus() }
                }
            }
        }
        .onDisappear {
            orientation.stop()
            chromeTask?.cancel()
            chromeTask = nil
            engine.overlaySettings.loupeEnabled = false
        }
        .onChange(of: chromeBlocked) { _, blocked in
            chrome.blocked = blocked
        }
        .onChange(of: showLoupe) { _, on in
            engine.overlaySettings.loupeEnabled = on
        }
        .onChange(of: watchStatusKey) { _, _ in publishWatchStatus() }
        .onChange(of: engine.values) { _, _ in
            chromeInteractionThrottled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { longController?.interrupted() }
            if phase == .active {
                // Delay so the app-level flushSpool (SnapFlexApp) finishes first;
                // picks up a permission change made in Settings.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    refreshSaveState()
                }
            }
        }
        .onChange(of: engine.status) { _, status in
            if status == .interrupted { longController?.interrupted() }
        }
        .onChange(of: engine.formatSelection) { _, _ in saveSettings() }
        .onChange(of: engine.processingLevel) { _, _ in saveSettings() }
        .onChange(of: aspect) { _, _ in saveSettings() }
        .onChange(of: timerDuration) { _, _ in saveSettings() }
        .onChange(of: showGrid) { _, _ in saveSettings() }
        .onChange(of: showLevel) { _, _ in saveSettings() }
        .alert("Save recipe", isPresented: $showSaveRecipeAlert) {
            TextField("Name", text: $newRecipeName)
            Button("Save") { snapshotRecipe() }
            Button("Cancel", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                longController?.interrupted()
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    guard !isLongExposing else { return }
                    engine.setZoom(zoomBase * value.magnification)
                    displayZoom = min(max(zoomBase * value.magnification,
                                          engine.ranges.zoom.lowerBound),
                                      engine.ranges.zoom.upperBound)
                }
                .onEnded { value in
                    guard !isLongExposing else { return }
                    zoomBase = min(max(zoomBase * value.magnification,
                                       engine.ranges.zoom.lowerBound),
                                   engine.ranges.zoom.upperBound)
                    displayZoom = zoomBase
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in chromeInteractionThrottled() }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !isLongExposing else { return }
                let target: Double = zoomBase > 1.5 ? 1.0 : 2.0
                engine.setZoom(target)
                zoomBase = target
                displayZoom = target
                Haptics.light()
            }
        )
    }

    /// Always visible (exempt from chrome auto-hide): losing photos silently is
    /// the one state the UI must never soft-pedal.
    private var photosDeniedBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Text(pendingSaves > 0
                 ? "PHOTOS ACCESS OFF · \(pendingSaves) SHOT\(pendingSaves == 1 ? "" : "S") WAITING · TAP FOR SETTINGS"
                 : "PHOTOS ACCESS OFF · TAP FOR SETTINGS")
                .font(Theme.valueFont(11))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func refreshSaveState() {
        photosDenied = store.saveBlocked
        pendingSaves = store.spooledCount
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "settings.rawMode"),
           let mode = RAWMode(rawValue: raw) {
            engine.formatSelection.raw = mode
        }
        if defaults.object(forKey: "settings.heifCompanion") != nil {
            engine.formatSelection.heifCompanion = defaults.bool(forKey: "settings.heifCompanion")
        }
        if let proc = defaults.string(forKey: "settings.processing"),
           let level = ProcessingLevel(rawValue: proc) {
            engine.processingLevel = level
        }
        if defaults.object(forKey: "settings.aspect") != nil {
            let index = defaults.integer(forKey: "settings.aspect")
            if AspectRatio.allCases.indices.contains(index) {
                aspect = AspectRatio.allCases[index]
            }
        }
        if defaults.object(forKey: "settings.timer") != nil {
            timerDuration = defaults.integer(forKey: "settings.timer")
        }
        showGrid = defaults.bool(forKey: "settings.grid")
        showLevel = defaults.bool(forKey: "settings.level")
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(engine.formatSelection.raw.rawValue, forKey: "settings.rawMode")
        defaults.set(engine.formatSelection.heifCompanion, forKey: "settings.heifCompanion")
        defaults.set(engine.processingLevel.rawValue, forKey: "settings.processing")
        defaults.set(AspectRatio.allCases.firstIndex(of: aspect) ?? 0, forKey: "settings.aspect")
        defaults.set(timerDuration, forKey: "settings.timer")
        defaults.set(showGrid, forKey: "settings.grid")
        defaults.set(showLevel, forKey: "settings.level")
    }

    // MARK: - Recipes

    private func saveRecipeBook() {
        UserDefaults.standard.set(recipeBook.encode(), forKey: "recipes.book")
    }

    private func apply(_ recipe: Recipe) {
        // Closing the dial cancels any in-flight momentum decay, which would
        // otherwise overwrite the recipe's value on its next tick.
        selected = nil
        engine.setISO(recipe.iso)
        engine.setShutter(recipe.shutterSeconds)
        engine.setEVBias(recipe.evBias)
        engine.setWhiteBalance(kelvin: recipe.wbKelvin)
        engine.formatSelection = FormatSelection(raw: recipe.raw, heifCompanion: recipe.heifCompanion)
        engine.processingLevel = recipe.processing
        if AspectRatio.allCases.indices.contains(recipe.aspectIndex) {
            aspect = AspectRatio.allCases[recipe.aspectIndex]
        }
        Haptics.success()
        chromeInteraction()
    }

    private func beginSaveRecipe() {
        newRecipeName = "Recipe \(recipeBook.recipes.count + 1)"
        showSaveRecipeAlert = true
    }

    private func snapshotRecipe() {
        let trimmed = newRecipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Recipe \(recipeBook.recipes.count + 1)" : trimmed
        let recipe = Recipe(
            name: name,
            iso: engine.values.iso,
            shutterSeconds: engine.values.shutterSeconds,
            evBias: engine.values.evBias,
            wbKelvin: engine.values.wbKelvin,
            raw: engine.formatSelection.raw,
            heifCompanion: engine.formatSelection.heifCompanion,
            processing: engine.processingLevel,
            aspectIndex: AspectRatio.allCases.firstIndex(of: aspect) ?? 0)
        recipeBook.add(recipe)
        saveRecipeBook()
        Haptics.light()
    }

    private func deleteRecipe(_ recipe: Recipe) {
        recipeBook.remove(id: recipe.id)
        saveRecipeBook()
    }

    private var bottomRow: some View {
        HStack {
            Button {
                if let url = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Group {
                    if let lastThumbnail {
                        Image(uiImage: lastThumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .id(thumbnailID)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.2))
                            .frame(width: 40, height: 40)
                    }
                }
                .rotatesWithDevice(orientation.uiAngle)
            }
            .buttonStyle(.plain)
            .disabled(isLongExposing)
            .opacity(isLongExposing ? 0.4 : 1)
            .opacity(chromeHidden ? 0 : 1)
            .allowsHitTesting(!chromeHidden)
            .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
            Spacer()
            ZStack {
                if let longController, longController.isExposing {
                    LongExposureShutterRing(controller: longController)
                }
                evArc
                    .opacity(chromeHidden ? 0 : 1)
                    .opacity(isLongExposing ? 0 : 1)
                    .allowsHitTesting(false)
                    .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
                    .animation(Theme.motion(Theme.springStandard), value: isLongExposing)
                if engine.values.evBias != 0 {
                    evLabel
                        .opacity(chromeHidden ? 0 : 1)
                        .opacity(isLongExposing ? 0 : 1)
                        .allowsHitTesting(false)
                        .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
                        .animation(Theme.motion(Theme.springStandard), value: isLongExposing)
                        .animation(Theme.motion(Theme.springStandard), value: engine.values.evBias != 0)
                        .transition(.opacity)
                }
                Button {
                    takePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                            .opacity(isLongExposing ? 0 : 1)
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 62, height: 62)
                            .opacity(isLongExposing ? 1 : 0)
                    }
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4).padding(-5))
                    .animation(Theme.motion(Theme.springStandard), value: isLongExposing)
                }
                .buttonStyle(ShutterButtonStyle())
                .scaleEffect(chromeHidden ? 54.0 / 62.0 : 1)
                .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    engine.setZoom(1)
                    zoomBase = 1
                    displayZoom = 1
                } label: {
                    Text(String(format: "%.1f\u{00D7}", displayZoom))
                        .font(Theme.valueFont(11))
                        .foregroundStyle(displayZoom == 1 ? .white : Theme.accent)
                        .contentTransition(.numericText())
                        .animation(Theme.motion(Theme.springStandard), value: displayZoom)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .rotatesWithDevice(orientation.uiAngle)
                }
                .buttonStyle(.plain)
                ForEach(engine.availableLenses, id: \.self) { lens in
                    Button {
                        engine.selectLens(lens)
                        zoomBase = 1
                        displayZoom = 1
                    } label: {
                        Text(lens.displayName)
                            .font(Theme.valueFont(11))
                            .foregroundStyle(engine.activeLens == lens ? Theme.accent : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(engine.activeLens == lens ? 0.2 : 0.1))
                            .clipShape(Capsule())
                            .rotatesWithDevice(orientation.uiAngle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(isLongExposing)
            .opacity(isLongExposing ? 0.4 : 1)
            .opacity(chromeHidden ? 0 : 1)
            .allowsHitTesting(!chromeHidden)
            .animation(Theme.motion(chromeHidden ? Theme.springStandard : Theme.springBouncy), value: chromeHidden)
        }
        .padding(.horizontal, 20)
    }

    /// -1...1: sign gives sweep direction (+clockwise from 12 o'clock, -mirrored),
    /// magnitude is EV bias as a fraction of the device's upper bias range.
    private var evFraction: Double {
        let bias = Double(engine.values.evBias)
        let upperBound = Double(max(engine.ranges.evBias.upperBound, 1))
        let fraction = bias / upperBound
        return min(max(fraction, -1), 1)
    }

    private var evArc: some View {
        let fraction = evFraction
        let trimEnd = CGFloat(abs(fraction) / 2)
        return Circle()
            .trim(from: 0, to: trimEnd)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 80, height: 80)
            .rotationEffect(.degrees(-90))
            .scaleEffect(x: fraction < 0 ? -1 : 1)
            .animation(Theme.motion(Theme.springStandard), value: engine.values.evBias)
    }

    private var evLabel: some View {
        Text(String(format: "EV %+.1f", engine.values.evBias))
            .font(Theme.valueFont(7.5))
            .foregroundStyle(Theme.accent)
            .tracking(0.9)
            .offset(y: -52)
            .rotatesWithDevice(orientation.uiAngle)
    }

    func takePhoto() {
        guard engine.status != .interrupted else { return }
        chromeInteraction()
        if let longController, engine.longMode != .off || longController.isExposing {
            guard !captureInFlight else { return }
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            if longController.isExposing {
                longController.shutterTapped()
            } else {
                startLongExposure(longController)
            }
            return
        }
        if countdownTask != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        guard timerDuration > 0 else { routeCapture(); return }
        var timer = CaptureTimer(duration: timerDuration)
        timer.start()
        countdownTask = Task {
            while case .counting(let remaining) = timer.state {
                countdown = remaining
                Haptics.light()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                timer.tick()
            }
            countdown = nil
            countdownTask = nil
            if timer.state == .fired {
                chromeInteraction()
                routeCapture()
            }
        }
    }

    /// Routes a fired shutter to the NIGHT stack or a normal single capture.
    private func routeCapture() {
        if engine.nightEnabled {
            performNightStack()
        } else {
            performCapture()
        }
    }

    private func startLongExposure(_ controller: LongExposureController) {
        UIApplication.shared.isIdleTimerDisabled = true
        let backgroundGuard = LongExposureBackgroundGuard()
        backgroundGuard.begin(name: "long-exposure-finalize")
        engine.prepareLongExposure()
        engine.beginLongFrames { buffer in controller.ingest(buffer) }
        controller.start(mode: engine.longMode, blend: engine.longBlend) { data in
            UIApplication.shared.isIdleTimerDisabled = false
            engine.endLongFrames()
            engine.endLongExposure()
            chromeInteraction()
            if let data {
                Haptics.success()
                if let image = UIImage(data: data) {
                    setThumbnail(image)
                }
                let resource = CaptureResource(kind: .processedHEIF, data: data)
                Task {
                    await store.store([resource])
                    refreshSaveState()
                    backgroundGuard.end()
                }
            } else {
                backgroundGuard.end()
            }
        }
    }

    private func performCapture() {
        guard !captureInFlight else { return }
        captureInFlight = true
        Haptics.medium()
        withAnimation(.easeOut(duration: 0.1)) { shutterFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { shutterFlash = false }
        }
        engine.capture { resources in
            captureInFlight = false
            guard !resources.isEmpty else {
                showCaptureFailed()
                return
            }
            if let heif = resources.first(where: { $0.kind == .processedHEIF }),
               let image = UIImage(data: heif.data) {
                setThumbnail(image)
            }
            Task {
                await store.store(resources)
                refreshSaveState()
            }
        }
    }

    private func performNightStack() {
        guard !captureInFlight else { return }
        captureInFlight = true
        UIApplication.shared.isIdleTimerDisabled = true
        let backgroundGuard = LongExposureBackgroundGuard()
        backgroundGuard.begin(name: "night-stack-finalize")
        nightProgress = (0, NightStack.frameCount)
        Haptics.medium()
        engine.captureNightStack(onProgress: { current, total in
            nightProgress = (current, total)
        }) { data in
            captureInFlight = false
            nightProgress = nil
            UIApplication.shared.isIdleTimerDisabled = false
            guard let data else {
                backgroundGuard.end()
                showCaptureFailed()
                return
            }
            if let image = UIImage(data: data) {
                setThumbnail(image)
            }
            Task {
                await store.store([CaptureResource(kind: .processedHEIF, data: data)])
                refreshSaveState()
                backgroundGuard.end()
            }
            Haptics.success()
        }
    }

    private func publishWatchStatus() {
        watchRemote?.publishStatus(watchStatusLine)
    }

    /// Updates the on-screen thumbnail and mirrors it to the watch as a small
    /// JPEG. Shared by every capture path (normal, LONG, NIGHT) so the resize/
    /// encode logic lives in exactly one place.
    private func setThumbnail(_ image: UIImage) {
        withAnimation(Theme.motion(Theme.springBouncy)) {
            lastThumbnail = image
            thumbnailID += 1
        }
        guard let watchRemote else { return }
        let maxDimension: CGFloat = 200
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Scale 1 (points == pixels): without this, UIGraphicsImageRenderer
        // renders at the screen's native scale (2x/3x), producing a JPEG
        // several times larger than intended and risking WCSession's
        // sendMessage payload cap (errorHandler is nil, so an oversized send
        // just silently vanishes).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let jpeg = resized.jpegData(compressionQuality: 0.7) {
            watchRemote.pushThumbnail(jpeg)
        }
    }

    private func showCaptureFailed() {
        Haptics.error()
        withAnimation(Theme.motion(Theme.springStandard)) { captureFailed = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Theme.motion(Theme.springStandard)) { captureFailed = false }
        }
    }
}

/// Shutter button press feedback: scales down while pressed, springing back on release.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.motion(Theme.springBouncy), value: configuration.isPressed)
    }
}
