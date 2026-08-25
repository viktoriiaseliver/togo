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
    var title: String = ""
    var detail: String = ""

    init(title: String, detail: String, startedAt: Date = Date()) {
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard let endedAt else { return true }
        return date < endedAt
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

    var dayCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
    }

    func isActive(on date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: startDate)
        // Последний день поездки считается целиком: возвращаются вечером.
        guard let until = calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: endDate)) else {
            return false
        }
        return date >= from && date <= until
    }

    func dayNumber(on date: Date = Date()) -> Int {
        (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate),
                                         to: Calendar.current.startOfDay(for: date)).day ?? 0) + 1
    }
}
