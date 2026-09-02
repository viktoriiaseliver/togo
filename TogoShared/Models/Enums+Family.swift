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
        case .logBasics: "Записывать бытовое"
        case .editRecords: "Править и удалять записи"
        case .seeMedical: "Видеть медицинское"
        case .giveDose: "Отмечать дозы"
        case .editTreatment: "Менять схему лечения"
        case .editProfile: "Менять профиль и уход"
        case .manageFamily: "Приглашать и менять роли"
        case .exportData: "Выгружать данные и отчёты"
        }
    }

    var detail: String {
        switch self {
        case .logBasics: "выходы, еда, вода, прогулки, стул"
        case .editRecords: "чужие записи тоже"
        case .seeMedical: "схемы, дозы, анализы, отчёты"
        case .giveDose: "и брать дозу на себя"
        case .editTreatment: "препараты, часы, окно натощак"
        case .editProfile: "порция, вес, напоминания, занятия"
        case .manageFamily: "и выдавать права"
        case .exportData: "CSV и отчёт врачу"
        }
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
        case .owner: "Владелец"
        case .coOwner: "Со-владелец"
        case .caregiver: "Ухаживающий"
        case .helper: "Помощник"
        case .observer: "Наблюдатель"
        }
    }

    var permissionSummary: String {
        switch self {
        case .owner: "всё"
        case .coOwner: "доза, правка, приглашения"
        case .caregiver: "доза, правка 24 ч"
        case .helper: "выход, еда, прогулка"
        case .observer: "читает всё, не пишет"
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

    var canWrite: Bool { defaultPermissions.contains(.logBasics) }
    var canSeeMedical: Bool { defaultPermissions.contains(.seeMedical) }
    /// По умолчанию схему лечения меняет только владелец — но это можно выдать.
    var canEditTreatment: Bool { defaultPermissions.contains(.editTreatment) }
    var canInvite: Bool { defaultPermissions.contains(.manageFamily) }
}
