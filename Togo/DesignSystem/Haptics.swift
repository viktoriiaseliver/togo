import UIKit

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Маркер должен быть слышен и ощутим мгновенно: телефон в кармане,
    /// обе руки заняты кормом и поводком.
    static func marker() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0) }
}
