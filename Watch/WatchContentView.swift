import SwiftUI
import WatchKit

struct WatchContentView: View {
    @StateObject private var session = WatchSessionModel()

    private var statusText: String { session.isReachable ? session.statusLine : "OFFLINE" }

    var body: some View {
        VStack(spacing: 12) {
            Text(statusText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color(red: 0.29, green: 0.87, blue: 0.50))

            Button {
                session.sendCapture()
                WKInterfaceDevice.current().play(.click)
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            Group {
                if let thumbnail = session.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray)
                        .frame(width: 40, height: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    WatchContentView()
}
