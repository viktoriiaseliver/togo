import Foundation
import UserNotifications

/// Всё повторяющееся собирается в одну сводку в выбранный час.
/// Прерывают только доза по расписанию, окно натощак и лестница эскалации.
enum NotificationCenterService {
    enum Category: String {
        case morningBrief = "brief"
        case dose = "dose"
        case fasting = "fasting"
        case escalation = "escalation"
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        } catch {
            log.error("Не удалось запросить разрешение: \(error.localizedDescription)")
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Один пуш в выбранный час со всеми сроками сразу.
    static func scheduleMorningBrief(at hour: Int, lines: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Category.morningBrief.rawValue])
        guard !lines.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Togo · утренняя сводка"
        content.body = lines.prefix(4).joined(separator: "\n")
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = Category.morningBrief.rawValue

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: Category.morningBrief.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    /// Доза — единственное, что имеет право на time-sensitive.
    static func scheduleDose(id: String, at date: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.dose.rawValue

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Окно натощак: не ошибка, а «подожди». Одно уведомление на конец окна.
    static func scheduleFastingEnd(id: String, at date: Date, dogName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Можно кормить"
        content.body = "Окно натощак закончилось. \(dogName) может есть."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.fasting.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
