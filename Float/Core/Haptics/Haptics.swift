import UIKit

enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
