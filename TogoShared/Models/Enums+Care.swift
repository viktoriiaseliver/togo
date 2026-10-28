import Foundation

// MARK: - Поездка

nonisolated enum TransportKind: String, Codable, CaseIterable, Sendable {
    case car, plane, train

    var title: String {
        switch self {
        case .car: String(localized: "машина")
        case .plane: String(localized: "самолёт")
        case .train: String(localized: "поезд")
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
        case .grooming: String(localized: "груминг")
        case .medical: String(localized: "уколы, таблетки, прививки")
        }
    }
}

nonisolated enum DogSex: String, Codable, CaseIterable, Sendable {
    case female, male, unknown

    var title: String {
        switch self {
        case .female: String(localized: "Девочка")
        case .male: String(localized: "Мальчик")
        case .unknown: String(localized: "Не указан")
        }
    }
}

/// Уход бывает трёх разных сортов, и путать их нельзя — иначе приложение
/// в первый же день кричит «сегодня» про всё сразу.
///
/// * **Ежедневное** — привычка: зубы, лапы после улицы, вычёсывание в линьку.
///   У неё нет просрочки, у неё есть серия. Пропустил день — не беда,
///   пропустил неделю — видно.
/// * **Регулярное** — раз в N дней от последнего раза: когти, купание, уши.
///   Пока ни разу не делали, срок неизвестен — и приложение так и говорит,
///   вместо того чтобы выдумывать просрочку.
/// * **По дате** — прививки и визиты. У них есть конкретный день,
///   а не «раз в год от последнего раза».
nonisolated enum CareKind: String, Codable, CaseIterable, Sendable {
    case daily
    case periodic
    case dated

    var title: String {
        switch self {
        case .daily: String(localized: "каждый день")
        case .periodic: String(localized: "регулярно")
        case .dated: String(localized: "по дате")
        }
    }

    var sectionTitle: String {
        switch self {
        case .daily: String(localized: "каждый день")
        case .periodic: String(localized: "регулярно")
        case .dated: String(localized: "прививки и визиты")
        }
    }

    var symbol: String {
        switch self {
        case .daily: "repeat"
        case .periodic: "arrow.triangle.2.circlepath"
        case .dated: "calendar"
        }
    }
}

/// Часть дня, в которую приходит сводка по уходу.
///
/// **Выводится из часа, а не хранится рядом с ним.** Час у сводки один
/// (`Settings.briefHour`), и если положить часть дня вторым полем, две
/// величины об одном разойдутся молча — у нас это уже стоило трёх
/// реализаций «не кормить», из которых две молчали.
///
/// Границы 12 и 17 взяты не на глаз: ровно так делил сутки
/// `ScheduleChange.summary` («один раз · утром»), и это была ВТОРАЯ
/// копия того же правила. Теперь она зовёт отсюда.
///
/// **Зачем это понадобилось.** Выбор часа стоял в диапазоне 5…12,
/// то есть человек не мог поставить сводку на день или вечер вовсе,
/// а подпись называла её «утренней» в любом случае. Живой отзыв
/// 28.10.2026: «Хочу выбирать часть дня сама».
nonisolated enum ЧастьДня: String, CaseIterable, Identifiable, Sendable {
    case утро, день, вечер

    public var id: String { rawValue }

    /// Как это называется в строке «придёт …».
    var title: String {
        switch self {
        case .утро: String(localized: "утром")
        case .день: String(localized: "днём")
        case .вечер: String(localized: "вечером")
        }
    }

    var symbol: String {
        switch self {
        case .утро: "sunrise"
        case .день: "sun.max"
        case .вечер: "moon"
        }
    }

    /// Часы, между которыми можно выбирать внутри части дня.
    ///
    /// Не «любой час суток»: сводка — не прерывание, и ставить её
    /// на 03:00 значило бы обойти тихие часы молча.
    var часы: ClosedRange<Int> {
        switch self {
        case .утро: 5...11
        case .день: 12...16
        case .вечер: 17...21
        }
    }

    /// Куда встать, когда человек только что выбрал часть дня.
    var часПоУмолчанию: Int {
        switch self {
        case .утро: 8
        case .день: 14
        case .вечер: 19
        }
    }

    /// В какую часть дня попадает час. Единственное место правила.
    ///
    /// Час вне всех трёх диапазонов (ночь) отвечает «утро»: сводка там
    /// не ставится ни одним путём экрана, и выдумывать четвёртую часть
    /// дня ради недостижимого значения незачем.
    static func по(часу: Int) -> ЧастьДня {
        allCases.first { $0.часы.contains(часу) } ?? .утро
    }
}

/// В чём мерят препарат.
///
/// **Зачем вообще единица.** «Осталось 7» ничего не значит, пока
/// неизвестно, чего семь: семь таблеток — это неделя, семь миллилитров
/// — один приём капель. Экран запаса показывает уровень «хватит
/// на N дней», и без единицы он врёт в разы.
///
/// `dose` — для назначений без счётной единицы: ингалятор, мазь,
/// «один пакетик». Запас у них обычно не считают, и навязывать счёт
/// незачем.
/// Единица массы ВЕЩЕСТВА — только для ввода и показа.
///
/// **Стоит рядом с `MedUnit` нарочно: это ДВЕ РАЗНЫЕ ОСИ, и путать их
/// нельзя.** `MedUnit` — форма приёма (таблетки, миллилитры, дозы),
/// то есть «сколько штук». `ЕдиницаМассы` — сколько вещества,
/// то есть «сколько действующего». «2 таблетки» и «100 мкг» отвечают
/// на разные вопросы, и именно их смешение делало рост дозы невидимым
/// на графике Т4.
///
/// В хранилище этой единицы НЕТ: `Medication.massPerUnitMcg` всегда
/// в микрограммах. Enum живёт только на вводе и на показе —
/// пара «значение + единица» в базе позволила бы сложить `0,1 мг`
/// с `50 мкг`, а множитель между ними тысяча.
nonisolated enum ЕдиницаМассы: String, CaseIterable, Identifiable, Sendable {
    case мкг, мг

    public var id: String { rawValue }

    /// Множитель до микрограммов. Единственное место, где он записан.
    var вМикрограммах: Double {
        switch self {
        case .мкг: 1
        case .мг: 1000
        }
    }
}

nonisolated enum MedUnit: String, Codable, CaseIterable, Sendable {
    case tab
    case ml
    case dose

    var title: String {
        switch self {
        case .tab: String(localized: "таблетки")
        case .ml: String(localized: "миллилитры")
        case .dose: String(localized: "дозы")
        }
    }

    /// Как подписать количество рядом с числом.
    var shortName: String {
        switch self {
        case .tab: String(localized: "таб.")
        case .ml: String(localized: "мл")
        case .dose: String(localized: "дозы")
        }
    }

    /// Бывают ли половинки. Таблетку делят, миллилитр — мера сам по себе.
    var allowsHalves: Bool { self == .tab }

    var symbol: String {
        switch self {
        case .tab: "pills"
        case .ml: "drop"
        case .dose: "cross.vial"
        }
    }
}

/// Вид документа собаки.
///
/// Шаг 0 медицинского слоя, 07.10.2026. Виды взяты из карты Стича,
/// а не придуманы: паспорт, чип, договор, сертификат — каждый
/// встречается в ней не меньше трёх раз (§2.5 ТЗ). Пятый случай
/// `other` нужен затем, чтобы человек не выбирал неверный вид вместо
/// «не знаю»: пустого значения у `Raw` быть не должно — это ключ
/// группировки списка.
nonisolated enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case passport
    case chip
    case contract
    case certificate
    case other

    var title: String {
        switch self {
        case .passport: String(localized: "паспорт")
        case .chip: String(localized: "чип")
        case .contract: String(localized: "договор")
        case .certificate: String(localized: "сертификат")
        case .other: String(localized: "прочее")
        }
    }
}
