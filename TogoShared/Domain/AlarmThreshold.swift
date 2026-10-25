import Foundation

/// Порог тревоги: когда записей стало достаточно, чтобы звонить.
///
/// Порог задаёт не магия, а счёт: N эпизодов за окно времени. Смысл
/// не в том, чтобы приложение поставило диагноз, — оно и не ставит.
/// Смысл в том, чтобы человек в три часа ночи не решал в одиночку,
/// «уже пора или ещё нет», и не искал слова для звонка.
struct AlarmThreshold: Equatable, Identifiable {
    /// Что именно повторилось.
    var kind: IncidentKind
    /// Эпизоды в окне, от раннего к позднему.
    var episodes: [LogEvent]
    /// Окно наблюдения.
    var window: TimeInterval

    /// Порог опознаётся видом инцидента и последним эпизодом:
    /// новый эпизод — новый повод показать экран.
    var id: String { "\(kind.rawValue)-\(episodes.last?.id.uuidString ?? "")" }

    var count: Int { episodes.count }

    /// Заголовок строкой: «Рвота · третий раз за 6 часов».
    var headline: String {
        let hours = Int(window / 3600)
        return "\(kind.title) · \(Fmt.ordinal(count)) раз за \(String(localized: "\(hours) часов"))"
    }
}

enum AlarmThresholdAnalyzer {
    /// Сколько повторов за какое окно считаются поводом позвонить.
    ///
    /// Шесть часов и три раза — не выдумка: это та частота, при которой
    /// собака перестаёт удерживать воду, и обезвоживание становится
    /// вопросом часов, а не дней.
    static let window: TimeInterval = 6 * 3600
    static let minimumEpisodes = 3

    static func evaluate(
        events: [LogEvent],
        now: Date = Date()
    ) -> AlarmThreshold? {
        let since = now.addingTimeInterval(-window)
        let recent = Diary.active(events)
            .filter { $0.kind == .incident && $0.date >= since }

        // Считаем по видам: три рвоты подряд — повод, а рвота плюс
        // лужа плюс хромота — три разных наблюдения.
        let byKind = Dictionary(grouping: recent) { $0.incidentKind ?? .other }
        guard let hit = byKind
            .filter({ $0.value.count >= minimumEpisodes })
            .max(by: { $0.value.count < $1.value.count })
        else { return nil }

        return AlarmThreshold(kind: hit.key,
                              episodes: hit.value.sorted { $0.date < $1.date },
                              window: window)
    }

    /// Что сказать врачу.
    ///
    /// Собирается из уже записанного: сколько раз и с какого часа, чем
    /// лечимся и когда дали последнюю дозу, когда ел в последний раз.
    /// Ровно те вопросы, которые задают в клинике первыми.
    static func vetText(
        _ threshold: AlarmThreshold,
        dog: Dog,
        medications: [Medication],
        events: [LogEvent],
        now: Date = Date()
    ) -> String {
        var parts: [String] = []

        if let first = threshold.episodes.first {
            parts.append("\(threshold.kind.title.lowercased()) "
                         + "\(String(localized: "\(threshold.count) раз")) "
                         + String(localized: "с \(Fmt.clock(first.date))"))
        }

        // Детали эпизодов — то, что человек уже отметил и что в панике
        // не вспомнит: кровь, пена, «не смотрела».
        let details = threshold.episodes.compactMap(\.vomitDetail).map { $0.title.lowercased() }
        if !details.isEmpty {
            parts.append(Set(details).sorted().joined(separator: ", "))
        }

        if let medication = medications.first(where: { !$0.isPaused }) {
            var line = String(localized: "на \(medication.name.lowercased()) \(medication.doseText)")
            if let given = medication.doses.filter(\.isGiven)
                .max(by: { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) })?.givenAt {
                line += String(localized: ", последняя доза в \(Fmt.clock(given))")
            }
            parts.append(line)
        }

        if let meal = Diary.last(events, kind: .meal, before: now) {
            parts.append(String(localized: "ел в \(Fmt.clock(meal.date))"))
        }

        let body = parts.joined(separator: ". ")
        // Вес выпадает из шапки, когда не записан: «Стич, —. Ел
        // в 14:00» читается как обрыв строки. Ключа в каталоге
        // у этой фразы нет — она собирается конкатенацией,
        // поэтому правка новых строк не заводит (замер 25.10.2026).
        let шапка = [dog.displayName, Fmt.weightIfKnown(dog.weightKg)]
            .compactMap { $0 }.joined(separator: ", ")
        return "\(шапка). " + body.prefix(1).uppercased() + body.dropFirst() + "."
    }
}
