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

    // MARK: - Animation
    static let springStandard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy: Animation = .spring(response: 0.4, dampingFraction: 0.6)

    /// Respect Reduce Motion: crossfade instead of spring.
    static func motion(_ spring: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.2) : spring
    }
}
