import SwiftUI
import SwiftData
import Observation

/// Четыре флага определяют почти всё, что видно на экранах.
/// Ни один не переключается вручную с главного — все включаются событием или датой.
@Observable
final class AppState {
    /// Роль текущего человека на этом телефоне.
    var role: FamilyRole = .owner {
        didSet { if customPermissions != nil { customPermissions = nil } }
    }
    /// Права, выданные ему поимённо. Пусто — значит «по роли».
    var customPermissions: Set<Permission>?

    /// Экраны спрашивают про право, а не про роль: роль — это пресет,
    /// и владелец может его переопределить для любого участника.
    var permissions: Set<Permission> { customPermissions ?? role.defaultPermissions }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// Подтянуть права текущего человека из карточки участника.
    func adopt(_ member: FamilyMember) {
        role = member.role
        customPermissions = member.hasCustomPermissions ? member.permissions : nil
    }
    /// Кто сейчас за рулём: подставляется в автора записи.
    var currentUserName: String = "Виктория"

    /// Активный эпизод: 2+ инцидента за 24 часа.
    var activeEpisode: Episode?
    /// Идущий выход или прогулка. Одновременно идёт что-то одно:
    /// выход — это короткий поход по нужде, прогулка — долгая, с отметками.
    var session: ActiveSession?

    /// Тост отмены: каждая запись отменяется, удаление обратимо 5 секунд.
    var undo: UndoToast?

    var isEpisodeActive: Bool { activeEpisode?.isActive() ?? false }

    struct UndoToast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var eventID: UUID?
    }

    // MARK: Идущая сессия

    var isWalking: Bool { session?.kind == .walk }
    var walkStartedAt: Date? { session?.startedAt }
    var walkStartedBy: String? { session?.startedBy }

    func startOuting(by name: String, at date: Date = Date()) {
        session = ActiveSession(kind: .outing, startedAt: date, startedBy: name)
    }

    func startWalk(by name: String, at date: Date = Date()) {
        session = ActiveSession(kind: .walk, startedAt: date, startedBy: name)
    }

    /// Отметить, что собака что-то сделала прямо сейчас.
    func mark(_ kind: ActiveSession.Mark.Kind, at date: Date = Date()) {
        session?.marks.append(ActiveSession.Mark(kind: kind, at: date))
    }

    func pauseSession() {
        session?.pause()
    }

    func resumeSession() {
        session?.resume()
    }

    /// Убрать последнюю отметку: на морозе одной рукой промахнуться легко.
    @discardableResult
    func undoLastMark() -> ActiveSession.Mark? {
        guard session?.marks.isEmpty == false else { return nil }
        return session?.marks.removeLast()
    }

    @discardableResult
    func finishSession() -> ActiveSession? {
        defer { session = nil }
        return session
    }

    /// Совместимость со старым кодом выхода: возвращает длительность.
    @discardableResult
    func stopWalk() -> TimeInterval {
        guard let finished = finishSession() else { return 0 }
        return Date().timeIntervalSince(finished.startedAt)
    }

    /// Подтверждение записи. Показывается всегда, когда что-то записано:
    /// человек должен видеть, что тап сработал, — и иметь возможность
    /// тут же его отменить.
    func showUndo(_ message: String, eventID: UUID? = nil) {
        withAnimation(.spring(duration: 0.28)) {
            undo = UndoToast(message: message, eventID: eventID)
        }
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
    /// Язык интерфейса. Пусто — как в системе.
    ///
    /// iOS применяет `AppleLanguages` при следующем запуске: на лету
    /// перерисовать всё приложение нельзя, и притворяться, что можно,
    /// хуже, чем сказать прямо.
    var preferredLanguage: String {
        didSet {
            if preferredLanguage.isEmpty {
                UserDefaults.standard.removeObject(forKey: Keys.appleLanguages)
            } else {
                UserDefaults.standard.set([preferredLanguage], forKey: Keys.appleLanguages)
            }
            UserDefaults.standard.set(preferredLanguage, forKey: Keys.preferredLanguage)
        }
    }

    enum Keys {
        static let briefHour = "settings.briefHour"
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let lastSeenVersion = "settings.lastSeenVersion"
        static let notificationsAsked = "settings.notificationsAsked"
        static let quietHoursStart = "settings.quietHoursStart"
        static let quietHoursEnd = "settings.quietHoursEnd"
        static let haptics = "settings.haptics"
        static let preferredLanguage = "settings.preferredLanguage"
        static let appleLanguages = "AppleLanguages"
    }

    init(defaults: UserDefaults = .standard) {
        briefHour = defaults.object(forKey: Keys.briefHour) as? Int ?? 8
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) ?? ""
        notificationsAsked = defaults.bool(forKey: Keys.notificationsAsked)
        quietHoursStart = defaults.object(forKey: Keys.quietHoursStart) as? Int ?? 23
        quietHoursEnd = defaults.object(forKey: Keys.quietHoursEnd) as? Int ?? 7
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        preferredLanguage = defaults.string(forKey: Keys.preferredLanguage) ?? ""
    }

    /// Языки, которые приложение реально умеет. Берём из бандла, а не из
    /// списка в коде: так в настройках не появится язык без перевода.
    var availableLanguages: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted()
    }

    /// Есть ли для языка настоящий перевод. Пока переведён только русский,
    /// и приложение об этом честно пишет.
    func isTranslated(_ code: String) -> Bool {
        guard code != "ru" else { return true }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return false }
        let probe = "Просится"
        return bundle.localizedString(forKey: probe, value: probe, table: nil) != probe
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
