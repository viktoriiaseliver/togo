import Foundation
import UserNotifications

/// Напоминание протокола контроля: за 30 минут до каждой точки забора
/// крови — T+4 и T+6 от отмеченной дозы.
///
/// До 30.09 экран «Протокол» писал «напомним за 30 минут», а напоминания
/// не было нигде. Живёт отдельно от `ReminderScheduler`: тот пересобирает
/// повторяющееся по расписанию, а это разовое и считается от конкретной
/// отметки дозы.
///
/// Ставится с экрана «Протокол», а не с каждой дозы: забор крови бывает
/// не после каждого приёма, и звонить о нём ежедневно было бы неправдой.
enum ProtocolReminder {
    /// За сколько до точки напоминать.
    nonisolated static let lead: TimeInterval = 30 * 60
    /// Точки забора от дозы, в часах.
    nonisolated static let pointHours = [4, 6]
    nonisolated static let prefix = "protocol-"

    /// Чем кончилась постановка. Экран говорит это вместо безусловного
    /// «напомним»: обещание без исполнителя здесь уже было.
    enum Outcome: Equatable {
        /// Поставлено; ближайшее напоминание — в этот момент.
        case scheduled(Date)
        /// Впереди ни одной точки — напоминать не о чем.
        case nothingAhead
        /// Уведомления выключены в системе.
        case notAllowed
        /// Система не приняла напоминание.
        case failed
    }

    nonisolated static func identifier(dose: UUID, hours: Int) -> String {
        "\(prefix)\(dose.uuidString)-\(hours)"
    }

    /// Когда напоминать: только то, что ещё впереди, и без точек,
    /// где забор уже отмечен.
    nonisolated static func plan(givenAt: Date, now: Date,
                                 skipping done: Set<Int> = []) -> [(hours: Int, fireAt: Date)] {
        var result: [(hours: Int, fireAt: Date)] = []
        for hours in pointHours where !done.contains(hours) {
            let fireAt = givenAt.addingTimeInterval(TimeInterval(hours) * 3600 - lead)
            if fireAt > now { result.append((hours: hours, fireAt: fireAt)) }
        }
        return result
    }

    /// Какую точку закрывает забор, отмеченный в `drawnAt`, — ближайшую
    /// по времени. Забор в 13:50 при точках 14:00 и 16:00 — это +4.
    nonisolated static func point(covering drawnAt: Date, givenAt: Date) -> Int {
        func distance(_ hours: Int) -> TimeInterval {
            abs(drawnAt.timeIntervalSince(givenAt.addingTimeInterval(TimeInterval(hours) * 3600)))
        }
        return pointHours.min { distance($0) < distance($1) } ?? pointHours[0]
    }

    /// Поставить напоминания для дозы. Повторный вызов безвреден:
    /// тот же идентификатор заменяет прежнее напоминание.
    static func schedule(doseID: UUID, givenAt: Date,
                         skipping done: Set<Int> = [],
                         now: Date = Date()) async -> Outcome {
        guard await isAllowed() else { return .notAllowed }
        let center = UNUserNotificationCenter.current()

        // Протокол идёт один. Напоминания от прошлой дозы снимаем —
        // иначе звенело бы по времени, которое уже ничего не значит.
        // Как и снятые точки этой же дозы, где забор уже отмечен.
        let ahead = plan(givenAt: givenAt, now: now, skipping: done)
        let keep = Set(ahead.map { identifier(dose: doseID, hours: $0.hours) })
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard let first = ahead.first else { return .nothingAhead }
        for (hours, fireAt) in ahead {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Через 30 минут забор крови")
            content.body = String(localized: "Точка +\(hours) ч от дозы в \(Fmt.clock(givenAt)). Отметь забор в «Протоколе» — интервал посчитается сам.")
            content.sound = .default
            // Не time-sensitive: это право оставлено самой дозе
            // (`NotificationCenterService.scheduleDose`).
            content.interruptionLevel = .active
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireAt.timeIntervalSince(now)),
                repeats: false
            )
            do {
                try await center.add(UNNotificationRequest(
                    identifier: identifier(dose: doseID, hours: hours),
                    content: content, trigger: trigger))
            } catch {
                log.error("Напоминание протокола не встало: \(error.localizedDescription)")
                return .failed
            }
        }
        return .scheduled(first.fireAt)
    }

    /// Снять напоминание точки — забор отмечен, звонить незачем.
    static func cancel(doseID: UUID, hours: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(dose: doseID, hours: hours)])
    }

    /// Та же проверка, что в `ReminderScheduler.isAllowed`: там она
    /// приватная, а трогать чужой файл ради одной строки незачем.
    private static func isAllowed() async -> Bool {
        switch await NotificationCenterService.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}
