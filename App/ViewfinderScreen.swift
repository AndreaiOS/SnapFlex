import AVFoundation
import SwiftUI
import SnapFlexCore

struct ViewfinderScreen: View {
    let engine: CameraEngine
    let session: AVCaptureSession
    let driver: OverlayFrameDriver?

    @State private var selected: SelectedParameter?
    @State private var shutterFlash = false

    var body: some View {
        ZStack {
            PreviewView(session: session)
                .ignoresSafeArea()
            if let driver, engine.overlaySettings.peakingEnabled || engine.overlaySettings.zebraEnabled {
                OverlayMetalView(driver: driver)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            Color.white
                .ignoresSafeArea()
                .opacity(shutterFlash ? 0.7 : 0)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
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
    }

    private var bottomRow: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.2))
                .frame(width: 40, height: 40)
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
        withAnimation(.easeOut(duration: 0.1)) { shutterFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { shutterFlash = false }
        }
        engine.capture { _ in }
    }
}
