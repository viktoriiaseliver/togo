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
        // «занятия» убраны 03.11.2026: право перечисляло то, чего
        // в приложении нет с 28.10 (`82ba1e46`). Вес остаётся названным
        // поимённо — на эту строку ссылается выбор права у взвешивания
        // (`HealthScreen.swift:1405`), и ссылка от правки не страдает.
        case .editProfile: String(localized: "порция, вес, напоминания")
        case .manageFamily: String(localized: "и выдавать права")
        case .exportData: String(localized: "CSV и отчёт врачу")
        }
    }

    /// Заголовок плашки «этого права у тебя нет» — **до первого
    /// отказа**, а не после нажатия.
    ///
    /// Правило дизайна круга 5, п. 1: выключенный орган допустим,
    /// только если рядом словом сказано, чего не хватает. `.disabled`
    /// молчит по устройству, и человек без права видел выключенные
    /// строки, жал их и получал тишину.
    ///
    /// > **Отказ, о котором сказали заранее, — это граница. Отказ,
    /// > о котором сказали после нажатия, — это наша поломка в глазах
    /// > человека.**
    ///
    /// Лежит у перечисления, а не у плашки: подпись плашки строится
    /// из `title` (`ПлашкаПрава`), и две копии одного отказа разошлись
    /// бы молча. Имя права человек ищет в «Семье» ПО ЭТОМУ ЖЕ `title`,
    /// поэтому своими словами его называть нельзя — на этом
    /// `QuotedNamesTests` ловил трижды за сутки.
    var отказ: String {
        switch self {
        case .logBasics: String(localized: "Записывает владелец")
        case .editRecords: String(localized: "Записи правит владелец")
        case .seeMedical: String(localized: "Медицинское видит владелец")
        case .giveDose: String(localized: "Дозы отмечает владелец")
        case .editTreatment: String(localized: "Схему меняет владелец")
        case .editProfile: String(localized: "Профиль меняет владелец")
        case .manageFamily: String(localized: "Семью меняет владелец")
        case .exportData: String(localized: "Выгрузка недоступна")
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

    var canWrite: Bool { defaultPermissions.contains(.logBasics) }
}
