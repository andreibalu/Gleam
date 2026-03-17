import UIKit

enum AppHaptics {
    static func scanComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func buttonTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
