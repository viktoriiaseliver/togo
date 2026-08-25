import Foundation

// MARK: - Записи ленты

/// Вид записи в ленте дня. Слов «событие» и «лог» в интерфейсе нет —
/// они живут только здесь, в коде.
nonisolated enum LogKind: String, Codable, CaseIterable, Sendable {
    case outing        // выход по нужде
    case walk          // прогулка
    case meal          // еда
    case water         // вода
    case stool         // стул
    case treat         // лакомство
    case incident      // рвота, лужа, стул в доме
    case dose          // приём препарата
    case training      // занятие
    case weight        // взвешивание
    case care          // груминг, когти, антипаразитарка
    case travelStop    // остановка в дороге
    case note          // заметка

    var title: String {
        switch self {
        case .outing: "Выход"
        case .walk: "Прогулка"
        case .meal: "Еда"
        case .water: "Вода"
        case .stool: "Стул"
        case .treat: "Лакомство"
        case .incident: "Инцидент"
        case .dose: "Доза"
        case .training: "Занятие"
        case .weight: "Взвешивание"
        case .care: "Уход"
        case .travelStop: "Остановка"
        case .note: "Заметка"
        }
    }

    var symbol: String {
        switch self {
        case .outing: "figure.walk.departure"
        case .walk: "figure.walk"
        case .meal: "fork.knife"
        case .water: "drop"
        case .stool: "leaf"
        case .treat: "sparkles"
        case .incident: "exclamationmark.triangle"
        case .dose: "pills"
        case .training: "target"
        case .weight: "scalemass"
        case .care: "scissors"
        case .travelStop: "car"
        case .note: "text.alignleft"
        }
    }

    /// Помощник видит бытовое и не видит медицинского.
    var isMedical: Bool {
        self == .dose || self == .weight
    }
}

/// Результат выхода. Спрашивается один раз; не ответили — запись остаётся без результата.
nonisolated enum OutingOutcome: String, Codable, CaseIterable, Sendable {
    case urine, stool, both, none

    var title: String {
        switch self {
        case .urine: "Пописал"
        case .stool: "Стул"
        case .both: "И то и другое"
        case .none: "Не сходил"
        }
    }

    var shortTitle: String {
        switch self {
        case .urine: "моча"
        case .stool: "стул"
        case .both: "моча и стул"
        case .none: "без результата"
        }
    }
}

/// Как именно попросил. Единственная запись, которая меняет поведение, а не фиксирует его.
nonisolated enum AskSignal: String, Codable, CaseIterable, Sendable {
    case satAtDoor, cameAndLooked, barked, scratchedDoor, ownerNoticed

    var title: String {
        switch self {
        case .satAtDoor: "Сел у двери"
        case .cameAndLooked: "Подошёл, смотрит"
        case .barked: "Лает"
        case .scratchedDoor: "Царапает дверь"
        case .ownerNoticed: "Я сама заметила, он не просил"
        }
    }

    var symbol: String {
        switch self {
        case .satAtDoor: "dog"
        case .cameAndLooked: "eye"
        case .barked: "speaker.wave.3"
        case .scratchedDoor: "hand.raised"
        case .ownerNoticed: "person"
        }
    }

    /// Спокойный сигнал — то, что учим. Лай и царапанье вытесняют его,
    /// если дверь открывается в этот момент.
    var isCalm: Bool { self == .satAtDoor || self == .cameAndLooked }
}

/// Форма стула. Бристольская шкала существует, но только в базе и в отчёте врачу:
/// человек выбирает форму, а не цифру.
nonisolated enum StoolForm: String, Codable, CaseIterable, Sendable {
    case hard, sausage, soft, mushy, liquid

    var title: String {
        switch self {
        case .hard: "Твёрдый"
        case .sausage: "Колбаска"
        case .soft: "Мягкий"
        case .mushy: "Кашица"
        case .liquid: "Лужа"
        }
    }

    var bristolScore: Int {
        switch self {
        case .hard: 2
        case .sausage: 4
        case .soft: 5
        case .mushy: 6
        case .liquid: 7
        }
    }

    var symbol: String {
        switch self {
        case .hard: "circle.grid.2x2"
        case .sausage: "capsule"
        case .soft: "cloud"
        case .mushy: "cloud.fill"
        case .liquid: "drop.fill"
        }
    }
}

/// Особенности стула. Кровь — единственный флаг, поднимающий событие в терракот.
nonisolated enum StoolFlag: String, Codable, CaseIterable, Sendable {
    case mucus, blood, undigested, foreign, wormLike

    var title: String {
        switch self {
        case .mucus: "Слизь"
        case .blood: "Кровь"
        case .undigested: "Непереваренное"
        case .foreign: "Инородное"
        case .wormLike: "Похоже на глистов"
        }
    }

    var raisesAlarm: Bool { self == .blood }
}

nonisolated enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case vomit, puddle, stoolIndoors, other

    var title: String {
        switch self {
        case .vomit: "Вырвал"
        case .puddle: "Лужа в доме"
        case .stoolIndoors: "Стул в доме"
        case .other: "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .vomit: "arrow.up.circle"
        case .puddle: "drop.triangle"
        case .stoolIndoors: "house"
        case .other: "questionmark.circle"
        }
    }

    /// «Сказать остальным» включено по умолчанию для рвоты и крови,
    /// выключено для лужи: лужа — не новость для семьи.
    var notifiesFamilyByDefault: Bool { self == .vomit }

    /// После лужи показываем строку «не наказывай» и час предыстории.
    var showsPunishmentWarning: Bool { self == .puddle || self == .stoolIndoors }
}

nonisolated enum VomitDetail: String, Codable, CaseIterable, Sendable {
    case food, bile, grass, blood, unclear

    var title: String {
        switch self {
        case .food: "едой"
        case .bile: "желчью"
        case .grass: "травой"
        case .blood: "с кровью"
        case .unclear: "не разобрала"
        }
    }

    var raisesAlarm: Bool { self == .blood }
}

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
    var canGiveDose: Bool { defaultPermissions.contains(.giveDose) }
    /// По умолчанию схему лечения меняет только владелец — но это можно выдать.
    var canEditTreatment: Bool { defaultPermissions.contains(.editTreatment) }
    var canInvite: Bool { defaultPermissions.contains(.manageFamily) }
}

// MARK: - Обучение

/// Обучение не бинарно: «выучена / не выучена» — вредная рамка.
nonisolated enum SkillStatus: String, Codable, CaseIterable, Sendable {
    case notStarted, learning, works

    var title: String {
        switch self {
        case .notStarted: "не начинали"
        case .learning: "учится"
        case .works: "получается"
        }
    }

}

/// Оценка описывает условия, а не животное. «Хуже» из макета убрана.
nonisolated enum SessionObservation: String, Codable, CaseIterable, Sendable {
    case easy, distracted, yawned, refusedFood

    var title: String {
        switch self {
        case .easy: "легко, можно сложнее"
        case .distracted: "отвлекался"
        case .yawned: "зевал, отворачивался"
        case .refusedFood: "не брал еду"
        }
    }

    /// Отказ от корма останавливает занятие и снимает оценку:
    /// собака за порогом и учиться сейчас не может.
    var stopsSession: Bool { self == .refusedFood }
}

/// Чем маркируешь. Маркер всегда один и тот же и больше ничего не значит.
nonisolated enum MarkerKind: String, Codable, CaseIterable, Sendable {
    case clicker, wordYes, tongueClick

    var title: String {
        switch self {
        case .clicker: "кликер"
        case .wordYes: "слово «да»"
        case .tongueClick: "щелчок языком"
        }
    }
}

/// Оценка одной отметки маркера по задержке.
nonisolated enum MarkAccuracy: String, Sendable {
    case onTime, almost, late

    static func from(delayMilliseconds ms: Int) -> MarkAccuracy {
        // До полусекунды собака связывает маркер со своим действием.
        // После секунды она уже сделала что-то другое.
        if ms <= 500 { return .onTime }
        if ms <= 1000 { return .almost }
        return .late
    }

    var title: String {
        switch self {
        case .onTime: "в момент"
        case .almost: "почти"
        case .late: "поздно"
        }
    }

}

// MARK: - Поездка

nonisolated enum TransportKind: String, Codable, CaseIterable, Sendable {
    case car, plane, train

    var title: String {
        switch self {
        case .car: "машина"
        case .plane: "самолёт"
        case .train: "поезд"
        }
    }

    var symbol: String {
        switch self {
        case .car: "car"
        case .plane: "airplane"
        case .train: "tram"
        }
    }
}

// MARK: - Уход

nonisolated enum CareCategory: String, Codable, CaseIterable, Sendable {
    case grooming, medical

    var title: String {
        switch self {
        case .grooming: "груминг"
        case .medical: "уколы, таблетки, прививки"
        }
    }
}
