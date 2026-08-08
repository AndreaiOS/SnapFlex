// App/LongExposureHUD.swift
import CoreMotion
import Observation
import SwiftUI

/// Publishes whether the device is currently shaking too much to trust the
/// in-progress long exposure — sampled the same way as `LevelModel`.
@Observable
final class ShakeModel {
    private let motion = CMMotionManager()
    var isShaky: Bool = false

    private static let threshold = 0.35   // rad/s

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let rate = data.rotationRate
            let magnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            self?.isShaky = magnitude > Self.threshold
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

/// Elapsed time / progress / shake status for an in-progress LONG exposure.
/// The caller is responsible for placing the progress ring around the shutter
/// button; this view surfaces the elapsed label, the BULB indicator, and the
/// shake warning above the parameter bar.
struct LongExposureHUD: View {
    let controller: LongExposureController
    @State private var shake = ShakeModel()

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if shake.isShaky {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                if controller.progress == nil {
                    Text("BULB")
                        .font(Theme.valueFont(14))
                        .foregroundStyle(Theme.accent)
                }
                Text(String(format: "%.1fs", controller.elapsed))
                    .font(Theme.valueFont(22))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.chrome, in: Capsule())
        .allowsHitTesting(false)
        .onAppear { shake.start() }
        .onDisappear { shake.stop() }
    }
}

/// Progress ring meant to be layered directly behind/around the shutter button
/// while a preset LONG exposure is running. Bulb mode has no determinate
/// progress, so it draws nothing here (the HUD's "BULB" label communicates it).
struct LongExposureShutterRing: View {
    let controller: LongExposureController

    var body: some View {
        if let progress = controller.progress {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 84, height: 84)
        }
    }
}
