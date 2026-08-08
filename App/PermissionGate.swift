import AVFoundation
import SwiftUI

struct PermissionGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                content()
            case .notDetermined:
                Color.black.ignoresSafeArea()
                    .task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
            default:
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.inactiveText)
                    Text("SnapFlex needs camera access.")
                        .font(Theme.valueFont(15))
                        .foregroundStyle(.white)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(Theme.valueFont(14))
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
}
