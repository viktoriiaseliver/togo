import Foundation

// MARK: - Записи ленты

/// Вид записи в ленте дня. Слов «событие» и «лог» в интерфейсе нет —
/// они живут только здесь, в коде.
nonisolated enum LogKind: String, Codable, CaseIterable, Sendable {
    case outing        // выход по нужде
    case walk          // прогулка
    case meal          // еда
    /// Вода. Записывать её вручную больше негде: сколько собака выпила,
    /// человек всё равно не знает — миска стоит целый день, и цифра
    /// бралась из воздуха. Вид записи оставлен, чтобы уже записанное
    /// не превратилось в нечитаемое.
    case water
    case stool         // стул
    case treat         // лакомство
    case incident      // рвота, лужа, стул в доме
    case dose          // приём препарата
    case training      // занятие
    case reaction      // срыв на прогулке
    case weight        // взвешивание
    case care          // груминг, когти, антипаразитарка
    case travelStop    // остановка в дороге
    case note          // заметка

    /// Какое право нужно, чтобы такую запись создать.
    ///
    /// Права описаны поимённо и выдаются каждому участнику отдельно,
    /// но до этого проверялись только три из восьми. Здесь собрано
    /// соответствие целиком, а проверяется оно в `EventLog` — в одном
    /// месте, через которое проходит любая запись.
    var requiredPermission: Permission {
        switch self {
        // Приём препарата — отдельное право: двое, дающие дозу порознь,
        // это не путаница в дневнике, а передозировка.
        case .dose:
            .giveDose
        // Всё остальное — запись в дневник. Инцидент здесь же намеренно:
        // «собаку вырвало» замечает тот, кто рядом, а не тот, кому открыта
        // медицинская часть. Отдать инцидент под `seeMedical` было бы
        // ошибкой в другую сторону: у наблюдателя это право есть, а писать
        // ему нельзя ничего.
        case .outing, .walk, .meal, .water, .stool, .treat, .training,
             .reaction, .travelStop, .note, .care, .weight, .incident:
            .logBasics
        }
    }

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
        case .reaction: "Срыв"
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
        case .reaction: "bolt"
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
    case vomit, puddle, stoolIndoors, reaction, other

    var title: String {
        switch self {
        case .vomit: "Вырвал"
        case .puddle: "Лужа в доме"
        case .stoolIndoors: "Стул в доме"
        case .reaction: "Сорвался"
        case .other: "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .vomit: "arrow.up.circle"
        case .puddle: "drop.triangle"
        case .stoolIndoors: "house"
        case .reaction: "bolt"
        case .other: "questionmark.circle"
        }
    }

    /// «Сказать остальным» включено по умолчанию для рвоты и крови,
    /// выключено для лужи: лужа — не новость для семьи.
    var notifiesFamilyByDefault: Bool { self == .vomit }

    /// После лужи показываем строку «не наказывай» и час предыстории.
    var showsPunishmentWarning: Bool { self == .puddle || self == .stoolIndoors }

    /// Срыв просит уточнить, на что и как близко.
    var asksReactionDetails: Bool { self == .reaction }
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


/// На что собака сорвалась.
///
/// Срыв — это не плохое поведение и не «агрессия»: это порог. Собака,
/// которая сорвалась, в этот момент не может учиться, и ругать её
/// бессмысленно. Ценность записи в другом: видно, **на что** и **как часто**,
/// а значит видно, растёт порог или падает.
nonisolated enum ReactionTrigger: String, Codable, CaseIterable, Sendable {
    case dog, person, child, bike, car, cat, sound, unclear

    var title: String {
        switch self {
        case .dog: "Другая собака"
        case .person: "Человек"
        case .child: "Ребёнок"
        case .bike: "Велосипед, самокат"
        case .car: "Машина"
        case .cat: "Кошка"
        case .sound: "Звук"
        case .unclear: "Не поняла"
        }
    }

    var symbol: String {
        switch self {
        case .dog: "dog"
        case .person: "figure.stand"
        case .child: "figure.and.child.holdinghands"
        case .bike: "bicycle"
        case .car: "car"
        case .cat: "cat"
        case .sound: "speaker.wave.3"
        case .unclear: "questionmark"
        }
    }
}

/// Насколько близко это было. Дистанция — главная ручка в работе
/// с реактивной собакой: то, что рвёт в двух метрах, часто спокойно
/// проходится в двадцати.
nonisolated enum ReactionDistance: String, Codable, CaseIterable, Sendable {
    case close, medium, far

    var title: String {
        switch self {
        case .close: "Вплотную"
        case .medium: "Метров пять"
        case .far: "Далеко"
        }
    }
}
