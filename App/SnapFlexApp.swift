import SwiftUI

@main
struct SnapFlexApp: App {
    private let device = RealCameraDevice()
    private let driver = OverlayFrameDriver()
    private let store = CaptureStore(
        library: PhotoKitLibrary(),
        spoolDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("spool"))
    @State private var engine: CameraEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let device = self.device
        let driver = self.driver
        _engine = State(initialValue: CameraEngine(device: device, overlayDriver: driver))
    }

    var body: some Scene {
        WindowGroup {
            PermissionGate {
                ViewfinderScreen(engine: engine, session: device.session,
                                 driver: driver, store: store)
                    .onAppear { engine.start() }
                    .task { await store.flushSpool() }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let store = self.store
                Task { await store.flushSpool() }
            }
        }
    }
}
