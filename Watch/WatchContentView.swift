import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("READY")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color(red: 0.29, green: 0.87, blue: 0.50))

            Circle()
                .fill(Color.white)
                .frame(width: 64, height: 64)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray)
                .frame(width: 40, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    WatchContentView()
}
