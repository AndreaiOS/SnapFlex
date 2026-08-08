// App/GridLevelOverlay.swift
import CoreMotion
import Observation
import SwiftUI

@Observable
final class LevelModel {
    private let motion = CMMotionManager()
    var roll: Double = 0

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.roll = atan2(data.gravity.x, -data.gravity.y) * 180 / .pi
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

struct GridLevelOverlay: View {
    let showGrid: Bool
    let showLevel: Bool
    @State private var level = LevelModel()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showGrid {
                    Path { path in
                        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                            path.move(to: CGPoint(x: geo.size.width * fraction, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width * fraction, y: geo.size.height))
                            path.move(to: CGPoint(x: 0, y: geo.size.height * fraction))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * fraction))
                        }
                    }
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                }
                if showLevel {
                    let isLevel = abs(level.roll) < 1
                    Rectangle()
                        .fill(isLevel ? Theme.accent : Color.white.opacity(0.7))
                        .frame(width: 90, height: 1.5)
                        .rotationEffect(.degrees(-level.roll))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { if showLevel { level.start() } }
        .onDisappear { level.stop() }
        .onChange(of: showLevel) { _, isOn in isOn ? level.start() : level.stop() }
    }
}
