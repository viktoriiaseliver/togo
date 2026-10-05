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
