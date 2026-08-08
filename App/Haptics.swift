import UIKit

enum Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
