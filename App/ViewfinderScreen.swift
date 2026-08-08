import AVFoundation
import SwiftUI
import SnapFlexCore
import UIKit

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
    @State private var zoomBase: Double = 1

    var body: some View {
        ZStack {
            PreviewView(session: session, onCaptureEvent: { takePhoto() })
                .ignoresSafeArea()
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
                TopBar(engine: engine, aspect: $aspect, timerDuration: $timerDuration,
                       showGrid: $showGrid, showLevel: $showLevel)
                if engine.overlaySettings.histogramEnabled, let bins = engine.histogramBins {
                    HStack {
                        Spacer()
                        HistogramView(bins: bins).padding(8)
                    }
                }
                Spacer()
                if let parameter = selected {
                    ParameterDial(engine: engine, parameter: parameter)
                }
                ParameterBar(engine: engine, selected: $selected)
                    .padding(.vertical, 8)
                    .background(Theme.chrome)
                bottomRow
                    .padding(.vertical, 10)
                    .background(Theme.chrome)
            }
        }
        .statusBarHidden()
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    engine.setZoom(zoomBase * value.magnification)
                }
                .onEnded { value in
                    zoomBase = min(max(zoomBase * value.magnification,
                                       engine.ranges.zoom.lowerBound),
                                   engine.ranges.zoom.upperBound)
                }
        )
    }

    private var bottomRow: some View {
        HStack {
            Button {
                if let url = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                if let lastThumbnail {
                    Image(uiImage: lastThumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.2))
                        .frame(width: 40, height: 40)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                takePhoto()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4).padding(-5))
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                ForEach(engine.availableLenses, id: \.self) { lens in
                    Button {
                        engine.selectLens(lens)
                    } label: {
                        Text(lens.displayName)
                            .font(Theme.valueFont(11))
                            .foregroundStyle(engine.activeLens == lens ? Theme.accent : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(engine.activeLens == lens ? 0.2 : 0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    func takePhoto() {
        if countdownTask != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        guard timerDuration > 0 else { performCapture(); return }
        var timer = CaptureTimer(duration: timerDuration)
        timer.start()
        countdownTask = Task {
            while case .counting(let remaining) = timer.state {
                countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                timer.tick()
            }
            countdown = nil
            countdownTask = nil
            if timer.state == .fired { performCapture() }
        }
    }

    private func performCapture() {
        withAnimation(.easeOut(duration: 0.1)) { shutterFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { shutterFlash = false }
        }
        engine.capture { resources in
            if let heif = resources.first(where: { $0.kind == .processedHEIF }),
               let image = UIImage(data: heif.data) {
                lastThumbnail = image
            }
            Task { await store.store(resources) }
        }
    }
}
