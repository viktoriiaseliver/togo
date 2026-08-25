import SwiftUI
import SwiftData
import Observation

/// Четыре флага определяют почти всё, что видно на экранах.
/// Ни один не переключается вручную с главного — все включаются событием или датой.
@Observable
final class AppState {
    /// Роль текущего человека на этом телефоне.
    var role: FamilyRole = .owner
    /// Кто сейчас за рулём: подставляется в автора записи.
    var currentUserName: String = "Виктория"

    /// Активный эпизод: 2+ инцидента за 24 часа.
    var activeEpisode: Episode?
    /// Идущий выход — Live Activity с секундами, видна всей семье.
    var walkStartedAt: Date?
    var walkStartedBy: String?

    /// Тост отмены: каждая запись отменяется, удаление обратимо 5 секунд.
    var undo: UndoToast?

    var isEpisodeActive: Bool { activeEpisode?.isActive() ?? false }

    struct UndoToast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var eventID: UUID?
    }

    func startWalk(by name: String) {
        walkStartedAt = Date()
        walkStartedBy = name
    }

    func stopWalk() -> TimeInterval {
        defer { walkStartedAt = nil; walkStartedBy = nil }
        guard let walkStartedAt else { return 0 }
        return Date().timeIntervalSince(walkStartedAt)
    }

    func showUndo(_ message: String, eventID: UUID? = nil) {
        undo = UndoToast(message: message, eventID: eventID)
    }
}

/// Пользовательские настройки. Ничего из этого не уходит с телефона.
@Observable
final class Settings {
    /// Один пуш в выбранный час. Прерывают только доза и окно натощак.
    var briefHour: Int {
        didSet { UserDefaults.standard.set(briefHour, forKey: Keys.briefHour) }
    }
    var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }
    var lastSeenVersion: String {
        didSet { UserDefaults.standard.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }
    var notificationsAsked: Bool {
        didSet { UserDefaults.standard.set(notificationsAsked, forKey: Keys.notificationsAsked) }
    }
    var quietHoursStart: Int {
        didSet { UserDefaults.standard.set(quietHoursStart, forKey: Keys.quietHoursStart) }
    }
    var quietHoursEnd: Int {
        didSet { UserDefaults.standard.set(quietHoursEnd, forKey: Keys.quietHoursEnd) }
    }
    var haptics: Bool {
        didSet { UserDefaults.standard.set(haptics, forKey: Keys.haptics) }
    }

    enum Keys {
        static let briefHour = "settings.briefHour"
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let lastSeenVersion = "settings.lastSeenVersion"
        static let notificationsAsked = "settings.notificationsAsked"
        static let quietHoursStart = "settings.quietHoursStart"
        static let quietHoursEnd = "settings.quietHoursEnd"
        static let haptics = "settings.haptics"
    }

    init(defaults: UserDefaults = .standard) {
        briefHour = defaults.object(forKey: Keys.briefHour) as? Int ?? 8
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) ?? ""
        notificationsAsked = defaults.bool(forKey: Keys.notificationsAsked)
        quietHoursStart = defaults.object(forKey: Keys.quietHoursStart) as? Int ?? 23
        quietHoursEnd = defaults.object(forKey: Keys.quietHoursEnd) as? Int ?? 7
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// В тихие часы приложение не спрашивает результат выхода —
    /// собирает утром одной карточкой.
    func isQuietHour(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return quietHoursStart <= quietHoursEnd
            ? (hour >= quietHoursStart && hour < quietHoursEnd)
            : (hour >= quietHoursStart || hour < quietHoursEnd)
    }
}
