import SwiftUI

@main
struct SnapFlexApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SnapFlex")
                .font(Theme.valueFont(24))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}
