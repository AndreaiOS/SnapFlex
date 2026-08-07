import SwiftUI

@main
struct SnapFlexApp: App {
    private let device = RealCameraDevice()
    private let driver = OverlayFrameDriver()
    @State private var engine: CameraEngine

    init() {
        let device = self.device
        let driver = self.driver
        _engine = State(initialValue: CameraEngine(device: device, overlayDriver: driver))
    }

    var body: some Scene {
        WindowGroup {
            ViewfinderScreen(engine: engine, session: device.session, driver: driver)
                .preferredColorScheme(.dark)
                .onAppear { engine.start() }
        }
    }
}
