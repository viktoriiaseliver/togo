import Foundation
import SwiftData

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var name: String = ""
    var roleRaw: String = FamilyRole.helper.rawValue
    var note: String?
    var isMe: Bool = false

    /// Права, выданные поимённо. Пусто — значит «по роли»: так видно
    /// разницу между «мы ничего не меняли» и «мы всё сняли руками».
    var customPermissionsRaw: [String]?

    /// Дежурный получает напоминания; передача дежурства — одно действие.
    var isOnDuty: Bool = false
    var dutyUntil: Date?

    /// Приглашение живёт 24 часа, роль фиксируется до принятия.
    /// Ссылка ситтера гаснет по дате сама.
    var inviteToken: String?
    var inviteExpiresAt: Date?
    var accessExpiresAt: Date?
    var acceptedAt: Date?

    init(name: String, role: FamilyRole, isMe: Bool = false) {
        self.name = name
        self.roleRaw = role.rawValue
        self.isMe = isMe
    }

    var role: FamilyRole {
        get { FamilyRole(rawValue: roleRaw) ?? .helper }
        set { roleRaw = newValue.rawValue }
    }

    var initial: String { String(name.prefix(1)).uppercased() }

    /// Итоговый набор прав: свой, если его выдавали, иначе — из роли.
    var permissions: Set<Permission> {
        get {
            guard let raw = customPermissionsRaw else { return role.defaultPermissions }
            return Set(raw.compactMap(Permission.init))
        }
        set {
            // Владельца нельзя оставить без управления семьёй: иначе
            // права станет некому раздавать.
            var next = newValue
            if role == .owner { next.insert(.manageFamily) }
            customPermissionsRaw = next == role.defaultPermissions ? nil : next.map(\.rawValue).sorted()
        }
    }

    /// Права отличаются от роли — это стоит показать в интерфейсе.
    var hasCustomPermissions: Bool { customPermissionsRaw != nil }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// Вернуть к набору по роли.
    func resetPermissions() { customPermissionsRaw = nil }

    var isInvitePending: Bool { acceptedAt == nil && inviteToken != nil }

    func inviteIsValid(at date: Date = Date()) -> Bool {
        guard let inviteExpiresAt else { return false }
        return date < inviteExpiresAt
    }
}

/// Эпизод: два инцидента за 24 часа или подряд идущие дни с жидким стулом.
/// Пока эпизод активен, вердикт «просится» не считается вовсе.
@Model
final class Episode {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    /// Когда был последний инцидент этого эпизода. От него и считается,
    /// закончился ли он.
    var lastIncidentAt: Date = Date()
    var title: String = ""
    var detail: String = ""

    init(title: String, detail: String, startedAt: Date = Date()) {
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
        self.lastIncidentAt = startedAt
    }

    /// Сколько тишины считается концом эпизода.
    ///
    /// Двое суток без новых инцидентов — значит, прошло. Раньше эпизод
    /// не заканчивался никогда: `endedAt` не выставлял никто, а `isActive`
    /// без него возвращал `true`. То есть после двух инцидентов за сутки
    /// вердикт «просится» замолкал навсегда — и человек не понимал, почему
    /// приложение перестало подсказывать.
    static let quietPeriod: TimeInterval = 48 * 3600

    func isActive(at date: Date = Date()) -> Bool {
        if let endedAt { return date < endedAt }
        return date.timeIntervalSince(lastIncidentAt) < Self.quietPeriod
    }

    /// Продлить: случился ещё один инцидент.
    func extend(to date: Date = Date()) {
        lastIncidentAt = max(lastIncidentAt, date)
        endedAt = nil
    }

    /// Закрыть руками: человек видит, что собаке лучше.
    func close(at date: Date = Date()) {
        endedAt = date
    }

    /// Когда эпизод закончится сам, если больше ничего не случится.
    var quietUntil: Date {
        lastIncidentAt.addingTimeInterval(Self.quietPeriod)
    }
}

/// Поездка включается датой и гаснет сама. Это режим, а не раздел:
/// устроена как «Фокус», а не как место, куда надо ходить.
@Model
final class Trip {
    var id: UUID = UUID()
    var destination: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var transportRaw: String = TransportKind.car.rawValue
    var travelHours: Double = 0
    var lodging: String = ""
    var participants: [String] = []
    var departureMinuteOfDay: Int = 9 * 60
    var packedItems: [String] = []

    var dog: Dog?

    init(destination: String, startDate: Date, endDate: Date, transport: TransportKind) {
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.transportRaw = transport.rawValue
    }

    var transport: TransportKind {
        get { TransportKind(rawValue: transportRaw) ?? .car }
        set { transportRaw = newValue.rawValue }
    }

    // **Календарь аргументом, а не `Calendar.current` внутри.** Он несёт
    // пояс ЧИТАЮЩЕГО, и пока он брался внутри, проверить эти три функции
    // по поясам было нечем: поверхность непроверяемая, а чинится такое
    // переделкой входа, а не старанием. Замер 05.10 — в `CalendarDay`.
    //
    // По умолчанию — `CalendarDay.дневниковыйКалендарь`, а НЕ `.current`:
    // день записи у общего дневника один на семью, иначе двое читают
    // разные числа из одной строки. Для заякоренных записей выбор пояса
    // не меняет ничего (полдень устойчив к ±12 часам); он решает только
    // судьбу записей до 05.10, у которых якоря нет. Допущение, на котором
    // это держится, названо в `CalendarDay.дневниковыйПояс` вместе с тем,
    // что его снимет.

    func dayCount(calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Int {
        max(1, CalendarDay.daysBetween(startDate, endDate, calendar: calendar) + 1)
    }

    func isActive(on date: Date = Date(), calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Bool {
        let from = calendar.startOfDay(for: startDate)
        // Последний день поездки считается целиком: возвращаются вечером.
        guard let until = calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: endDate)) else {
            return false
        }
        return date >= from && date <= until
    }

    func dayNumber(on date: Date = Date(), calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Int {
        CalendarDay.daysBetween(startDate, date, calendar: calendar) + 1
    }
}
