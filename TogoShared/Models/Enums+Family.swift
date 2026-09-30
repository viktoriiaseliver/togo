import Foundation

// MARK: - Семья

/// Что человеку разрешено делать с собакой.
///
/// Роль — это пресет прав, а не потолок. Владелец может выдать любому
/// участнику любое право поимённо: у семьи бывает мама, которая по факту
/// ухаживает за собакой больше всех, и ситтер, которому на неделю нужен
/// полный доступ.
nonisolated enum Permission: String, Codable, CaseIterable, Sendable {
    case logBasics       // выходы, еда, вода, прогулки
    case editRecords     // правка и удаление записей в ленте
    case seeMedical      // медицинская часть вообще
    case giveDose        // отмечать приёмы
    case editTreatment   // менять схему лечения
    case editProfile     // профиль, питание, уход, занятия
    case manageFamily    // приглашать и менять роли
    case exportData      // выгрузка и отчёты врачу

    var title: String {
        switch self {
        case .logBasics: String(localized: "Записывать бытовое")
        case .editRecords: String(localized: "Править и удалять записи")
        case .seeMedical: String(localized: "Видеть медицинское")
        case .giveDose: String(localized: "Отмечать дозы")
        case .editTreatment: String(localized: "Менять схему лечения")
        case .editProfile: String(localized: "Менять профиль и уход")
        case .manageFamily: String(localized: "Приглашать и менять роли")
        case .exportData: String(localized: "Выгружать данные и отчёты")
        }
    }

    var detail: String {
        switch self {
        case .logBasics: String(localized: "выходы, еда, вода, прогулки, стул")
        case .editRecords: String(localized: "чужие записи тоже")
        case .seeMedical: String(localized: "схемы, дозы, анализы, отчёты")
        case .giveDose: String(localized: "и брать дозу на себя")
        case .editTreatment: String(localized: "препараты, часы, окно натощак")
        case .editProfile: String(localized: "порция, вес, напоминания, занятия")
        case .manageFamily: String(localized: "и выдавать права")
        case .exportData: String(localized: "CSV и отчёт врачу")
        }
    }

    /// Чего человек без этого права не увидит или не сможет.
    ///
    /// Для предпросмотра «как видит ситтер»: раньше там стоял зашитый
    /// абзац про помощника, одинаковый для любой роли и любых поимённых
    /// прав, — и обещал скрывать «историю за прошлые месяцы и контакты
    /// семьи», чего в коде не скрывается нигде. Теперь список собирается
    /// из прав, и соврать ему нечем.
    var withoutIt: String {
        switch self {
        case .logBasics: String(localized: "не запишет выходы, еду, прогулки и стул")
        case .editRecords: String(localized: "не поправит и не удалит записи в ленте")
        case .seeMedical: String(localized: "не увидит медицинское: схемы, дозы, анализы, отчёты")
        case .giveDose: String(localized: "не отметит дозу и не возьмёт её на себя")
        case .editTreatment: String(localized: "не поменяет схему лечения")
        case .editProfile: String(localized: "не поменяет профиль, порцию, уход и занятия")
        case .manageFamily: String(localized: "не позовёт людей и не поменяет роли")
        case .exportData: String(localized: "не выгрузит CSV и отчёт врачу")
        }
    }

    /// Чего нет в наборе — в порядке `allCases`, как на экране прав.
    static func missing(from granted: Set<Permission>) -> [Permission] {
        allCases.filter { !granted.contains($0) }
    }

    /// Право, без которого приложение перестаёт быть безопасным.
    /// Такие нельзя снять у владельца.
    var isOwnerOnlyByDefault: Bool { self == .manageFamily }
}

/// Роли — не лестница. Врач читает много и не пишет; ребёнок пишет бытовое
/// и не видит медицинского.
nonisolated enum FamilyRole: String, Codable, CaseIterable, Sendable {
    case owner, coOwner, caregiver, helper, observer

    var title: String {
        switch self {
        case .owner: String(localized: "Владелец")
        case .coOwner: String(localized: "Со-владелец")
        case .caregiver: String(localized: "Ухаживающий")
        case .helper: String(localized: "Помощник")
        case .observer: String(localized: "Наблюдатель")
        }
    }

    var permissionSummary: String {
        switch self {
        case .owner: String(localized: "всё")
        case .coOwner: String(localized: "доза, правка, приглашения")
        // «правка 24 ч» — правда с 30.09: `editWindow` ниже. До этого
        // сводка обещала срок, которого в коде не было нигде.
        case .caregiver: String(localized: "доза, правка 24 ч")
        case .helper: String(localized: "выход, еда, прогулка")
        case .observer: String(localized: "читает всё, не пишет")
        }
    }

    /// Что роль даёт по умолчанию. Владелец может это изменить поимённо —
    /// см. `FamilyMember.permissions`.
    var defaultPermissions: Set<Permission> {
        switch self {
        case .owner:
            Set(Permission.allCases)
        case .coOwner:
            [.logBasics, .editRecords, .seeMedical, .giveDose, .editProfile, .manageFamily, .exportData]
        case .caregiver:
            [.logBasics, .editRecords, .seeMedical, .giveDose]
        case .helper:
            [.logBasics]
        case .observer:
            [.seeMedical, .exportData]
        }
    }

    /// Сколько после записи её ещё можно править и удалять. Пусто —
    /// без срока.
    ///
    /// Ухаживающий правит только свежее: вчерашнюю опечатку он заметит
    /// и поправит сам, а переписывать недельную историю — дело
    /// владельца. Срок привязан к роли, а не к праву: право
    /// «Править и удалять записи» выдаётся поимённо любому, и владелец,
    /// выдавший его ухаживающему, выдаёт его в рамках роли.
    var editWindow: TimeInterval? {
        self == .caregiver ? 24 * 3600 : nil
    }

    /// Можно ли править запись, сделанную в `recordedAt`.
    ///
    /// Одна проверка на все места правки: право `editRecords` плюс срок
    /// роли. Будущая запись (часы телефона разошлись) считается свежей.
    func mayEdit(recordedAt: Date, with permissions: Set<Permission>,
                 at now: Date = Date()) -> Bool {
        guard permissions.contains(.editRecords) else { return false }
        guard let editWindow else { return true }
        return now.timeIntervalSince(recordedAt) < editWindow
    }

    var canWrite: Bool { defaultPermissions.contains(.logBasics) }
    var canSeeMedical: Bool { defaultPermissions.contains(.seeMedical) }
    /// По умолчанию схему лечения меняет только владелец — но это можно выдать.
    var canEditTreatment: Bool { defaultPermissions.contains(.editTreatment) }
    var canInvite: Bool { defaultPermissions.contains(.manageFamily) }
}
