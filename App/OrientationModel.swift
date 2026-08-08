// App/OrientationModel.swift
import Observation
import SwiftUI
import UIKit

/// Publishes the rotation angle UI items use to stay upright while the app
/// itself remains locked to portrait (native Camera behavior).
@Observable @MainActor
final class OrientationModel {
    private(set) var uiAngle: Double = 0
    private var observer: NSObjectProtocol?

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            let orientation = UIDevice.current.orientation
            Task { @MainActor in self?.update(orientation) }
        }
        update(UIDevice.current.orientation)
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func update(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait: uiAngle = 0
        case .landscapeLeft: uiAngle = 90
        case .landscapeRight: uiAngle = -90
        case .portraitUpsideDown: uiAngle = 180
        default: break   // faceUp/faceDown/unknown: keep the last angle
        }
    }
}

extension View {
    /// Rotates a compact UI item in place to follow the physical device orientation.
    func rotatesWithDevice(_ angle: Double) -> some View {
        rotationEffect(.degrees(angle))
            .animation(.easeInOut(duration: 0.25), value: angle)
    }
}
