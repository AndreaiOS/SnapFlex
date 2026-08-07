import SwiftUI

enum Theme {
    /// Accent green #4ADE80
    static let accent = Color(red: 0x4A / 255.0, green: 0xDE / 255.0, blue: 0x80 / 255.0)
    static let chrome = Color.black.opacity(0.6)
    static let inactiveText = Color(white: 0.6)

    static func valueFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static let labelFont: Font = .system(size: 9, weight: .medium, design: .monospaced)
}
