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
        case .outing: String(localized: "Выход")
        case .walk: String(localized: "Прогулка")
        case .meal: String(localized: "Еда")
        case .water: String(localized: "Вода")
        case .stool: String(localized: "Стул")
        case .treat: String(localized: "Лакомство")
        case .incident: String(localized: "Инцидент")
        case .dose: String(localized: "Доза")
        case .training: String(localized: "Занятие")
        case .reaction: String(localized: "Срыв")
        case .weight: String(localized: "Взвешивание")
        case .care: String(localized: "Уход")
        case .travelStop: String(localized: "Остановка")
        case .note: String(localized: "Заметка")
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
        case .urine: String(localized: "Пописал")
        case .stool: String(localized: "Стул")
        case .both: String(localized: "И то и другое")
        case .none: String(localized: "Не сходил")
        }
    }

    var shortTitle: String {
        switch self {
        case .urine: String(localized: "моча")
        case .stool: String(localized: "стул")
        case .both: String(localized: "моча и стул")
        case .none: String(localized: "без результата")
        }
    }
}

/// Как именно попросил. Единственная запись, которая меняет поведение, а не фиксирует его.
nonisolated enum AskSignal: String, Codable, CaseIterable, Sendable {
    case satAtDoor, cameAndLooked, barked, scratchedDoor, ownerNoticed

    var title: String {
        switch self {
        case .satAtDoor: String(localized: "Сел у двери")
        case .cameAndLooked: String(localized: "Подошёл, смотрит")
        case .barked: String(localized: "Лает")
        case .scratchedDoor: String(localized: "Царапает дверь")
        case .ownerNoticed: String(localized: "Я сама заметила, он не просил")
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
        case .hard: String(localized: "Твёрдый")
        case .sausage: String(localized: "Колбаска")
        case .soft: String(localized: "Мягкий")
        case .mushy: String(localized: "Кашица")
        case .liquid: String(localized: "Лужа")
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
        case .mucus: String(localized: "Слизь")
        case .blood: String(localized: "Кровь")
        case .undigested: String(localized: "Непереваренное")
        case .foreign: String(localized: "Инородное")
        case .wormLike: String(localized: "Похоже на глистов")
        }
    }

    var raisesAlarm: Bool { self == .blood }
}

nonisolated enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case vomit, puddle, stoolIndoors, reaction, other

    var title: String {
        switch self {
        case .vomit: String(localized: "Вырвал")
        case .puddle: String(localized: "Лужа в доме")
        case .stoolIndoors: String(localized: "Стул в доме")
        case .reaction: String(localized: "Сорвался")
        case .other: String(localized: "Другое")
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
        case .food: String(localized: "едой")
        case .bile: String(localized: "желчью")
        case .grass: String(localized: "травой")
        case .blood: String(localized: "с кровью")
        case .unclear: String(localized: "не разобрала")
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
        case .dog: String(localized: "Другая собака")
        case .person: String(localized: "Человек")
        case .child: String(localized: "Ребёнок")
        case .bike: String(localized: "Велосипед, самокат")
        case .car: String(localized: "Машина")
        case .cat: String(localized: "Кошка")
        case .sound: String(localized: "Звук")
        case .unclear: String(localized: "Не поняла")
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
        case .close: String(localized: "Вплотную")
        case .medium: String(localized: "Метров пять")
        case .far: String(localized: "Далеко")
        }
    }
}
