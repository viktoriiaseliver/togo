import Foundation

/// Выборки по ленте. Отдельно от SwiftData, чтобы считалось одинаково
/// в приложении, в виджете и в тестах.
nonisolated enum Diary {
    static func active(_ events: [LogEvent]) -> [LogEvent] {
        events.filter { !$0.isDeleted }
    }

    static func onDay(_ events: [LogEvent], _ day: Date, calendar: Calendar = .current) -> [LogEvent] {
        active(events)
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    static func last(_ events: [LogEvent], kind: LogKind, before date: Date = Date()) -> LogEvent? {
        active(events)
            .filter { $0.kind == kind && $0.date <= date }
            .max { $0.date < $1.date }
    }

    /// Выходы, закончившиеся мочой (или мочой и стулом).
    static func urineEvents(_ events: [LogEvent]) -> [LogEvent] {
        active(events)
            .filter { $0.kind == .outing && ($0.outcome == .urine || $0.outcome == .both) }
            .sorted { $0.date < $1.date }
    }

    /// Сколько времени собака способна терпеть — это промежуток между
    /// **опорожнениями**, а не между отметками.
    ///
    /// За одну прогулку собака метит три раза за десять минут, и раньше
    /// это давало три интервала по десять минут вперемешку с настоящими
    /// четырёхчасовыми. Медиана уезжала вниз, и вердикт начинал считать
    /// нормой десять минут — то есть переставал работать у любого, кто
    /// отмечает прогулку подробно.
    static let sameEmptyingWindow: TimeInterval = 45 * 60

    static func urineIntervals(_ events: [LogEvent]) -> [TimeInterval] {
        let dates = urineEvents(events).map(\.date)
        guard dates.count > 1 else { return [] }
        return zip(dates, dates.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .filter { $0 > sameEmptyingWindow }
    }

    static func daysOfData(_ events: [LogEvent], now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let first = active(events).map(\.date).min() else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days + 1
    }

    static func signals(_ events: [LogEvent], now: Date = Date(), episodeActive: Bool) -> NeedSignals {
        let urine = urineEvents(events).last
        let lastOuting = last(events, kind: .outing, before: now)
        return NeedSignals(
            now: now,
            lastUrine: urine?.date,
            lastStool: active(events)
                .filter { $0.kind == .stool || ($0.kind == .outing && ($0.outcome == .stool || $0.outcome == .both)) }
                .max { $0.date < $1.date }?.date,
            lastMeal: last(events, kind: .meal, before: now)?.date,
            lastWalk: last(events, kind: .walk, before: now)?.date,
            urineIntervals: urineIntervals(events),
            daysOfData: daysOfData(events, now: now),
            episodeActive: episodeActive,
            lastOutingHadResult: lastOuting?.outcome != nil && lastOuting?.outcome != OutingOutcome.none
        )
    }

    // MARK: Сводка «ел и пил»

    struct DaySummary {
        var eatenGrams: Int
        var dailyGrams: Int
        var drankMl: Int
        var outings: Int
        var walkMinutes: Int
        var trainingGrams: Int
    }

    static func summary(_ events: [LogEvent], day: Date, dog: Dog?) -> DaySummary {
        let today = onDay(events, day)
        return DaySummary(
            // Лакомства, взятые из дневной порции, — это та же еда.
            // Не считать их значит показывать «съел 60 из 120», когда
            // тридцать граммов ушло на занятие.
            eatenGrams: today
                .filter { $0.kind == .meal || ($0.kind == .treat && $0.fromPortion) }
                .compactMap(\.grams)
                .reduce(0, +),
            dailyGrams: dog?.dailyGrams ?? 0,
            drankMl: today.filter { $0.kind == .water }.compactMap(\.milliliters).reduce(0, +),
            outings: today.filter { $0.kind == .outing }.count,
            walkMinutes: today.filter { $0.kind == .walk }.compactMap(\.durationSeconds).reduce(0, +) / 60,
            trainingGrams: today.filter { $0.kind == .training }.compactMap(\.grams).reduce(0, +)
        )
    }

    // MARK: «Как попросил»

    /// Спрашиваем не каждый раз: при смене сигнала или раз в пять выходов.
    static func shouldAskHowAsked(_ events: [LogEvent], now: Date = Date()) -> Bool {
        let outings = active(events).filter { $0.kind == .outing }.sorted { $0.date < $1.date }
        guard outings.count >= 2 else { return true }
        let answered = outings.compactMap(\.askSignal)
        guard let lastAnswered = answered.last else { return true }
        let sinceAnswered = outings.reversed().prefix { $0.askSignal == nil }.count
        if sinceAnswered >= 5 { return true }
        // Смена сигнала: последние два ответа разошлись по «спокойный / не спокойный».
        if answered.count >= 2, answered[answered.count - 2].isCalm != lastAnswered.isCalm { return true }
        return false
    }

    struct SignalTally {
        var calm: Int
        var barking: Int
        var total: Int
    }

    static func signalTally(_ events: [LogEvent], from: Date, to: Date) -> SignalTally {
        let signals = active(events)
            .filter { $0.kind == .outing && $0.date >= from && $0.date < to }
            .compactMap(\.askSignal)
        return SignalTally(
            calm: signals.filter(\.isCalm).count,
            barking: signals.filter { $0 == .barked || $0 == .scratchedDoor }.count,
            total: signals.count
        )
    }

    /// Лай вытесняет спокойный сигнал — сравниваем эту неделю с позапрошлой.
    static func barkingIsDisplacingCalm(_ events: [LogEvent], now: Date = Date()) -> Bool {
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) else { return false }
        let past = signalTally(events, from: twoWeeksAgo, to: weekAgo)
        let current = signalTally(events, from: weekAgo, to: now)
        guard past.total >= 5, current.total >= 5 else { return false }
        let pastShare = Double(past.barking) / Double(past.total)
        let nowShare = Double(current.barking) / Double(current.total)
        return nowShare > 0.4 && nowShare > pastShare * 1.5
    }

    // MARK: Инциденты и эпизод

    /// Второй инцидент за сутки поднимает флаг эпизода.
    static func incidentsInLast24h(_ events: [LogEvent], now: Date = Date()) -> [LogEvent] {
        active(events).filter { $0.kind == .incident && now.timeIntervalSince($0.date) < 24 * 3600 }
    }

    /// Час предыстории после лужи: вода, одиночество, последний выход.
    static func hourBefore(_ events: [LogEvent], incident: Date) -> [LogEvent] {
        active(events)
            .filter { $0.date < incident && incident.timeIntervalSince($0.date) < 6 * 3600 && $0.kind != .incident }
            .sorted { $0.date > $1.date }
            .prefix(4)
            .reversed()
    }

    // MARK: Стул

    /// «Как всегда» доступно, только если последние 4 записи совпадают.
    static func usualStool(_ events: [LogEvent]) -> StoolForm? {
        let recent = active(events)
            .filter { $0.kind == .stool && $0.stoolForm != nil }
            .sorted { $0.date > $1.date }
            .prefix(4)
        guard recent.count == 4 else { return nil }
        let forms = Set(recent.compactMap(\.stoolForm))
        let flags = recent.map(\.stoolFlags)
        guard forms.count == 1, flags.allSatisfy(\.isEmpty) else { return nil }
        return forms.first
    }

    /// Два жидких с кровью подряд предлагают выписку.
    static func suggestsVetReport(_ events: [LogEvent]) -> Bool {
        let recent = active(events)
            .filter { $0.kind == .stool }
            .sorted { $0.date > $1.date }
            .prefix(2)
        guard recent.count == 2 else { return false }
        return recent.allSatisfy { $0.stoolForm == .liquid && $0.stoolFlags.contains(.blood) }
    }

    // MARK: Слияние офлайн-записей

    /// Две записи об одном событии в пределах 20 минут дают карточку слияния
    /// обоим авторам — а не тихую перезапись.
    static func mergeCandidates(_ events: [LogEvent], now: Date = Date()) -> [(LogEvent, LogEvent)] {
        // Смотрим только последние сутки: карточка слияния нужна сразу,
        // а не через месяц, и разбирать ради неё всю историю незачем.
        let recent = active(events).filter { now.timeIntervalSince($0.date) < 24 * 3600 }
        let sorted = recent.sorted { $0.date < $1.date }
        var pairs: [(LogEvent, LogEvent)] = []
        for (index, event) in sorted.enumerated() {
            for other in sorted[(index + 1)...] {
                guard other.date.timeIntervalSince(event.date) < 20 * 60 else { break }
                if other.kind == event.kind, other.authorName != event.authorName {
                    pairs.append((event, other))
                }
            }
        }
        return pairs
    }
}
