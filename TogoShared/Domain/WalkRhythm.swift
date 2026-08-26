import Foundation

/// Как часто собаку выводят на самом деле.
///
/// Нормы «гуляйте три раза в день» бесполезны: у щенка и у пожилой собаки
/// они разные, и у каждой семьи свой день. Зато есть записи — по ним видно,
/// сколько раз в день выходят обычно и сколько собака в среднем терпит
/// между выходами.
///
/// Это не рекомендация и не цель. Это зеркало: человек смотрит и сам решает,
/// достаточно ли. Приложение только считает то, что он записал.
nonisolated struct WalkRhythm: Equatable, Sendable {
    /// Сколько дней с записями попало в расчёт.
    var days: Int
    /// Сколько раз в день выводят обычно.
    var outingsPerDay: Double
    /// Сколько собака в среднем проводит дома между выходами.
    var averageIndoors: TimeInterval
    /// Самый долгий промежуток дома за окно наблюдения.
    var longestIndoors: TimeInterval
    /// Во сколько выходят чаще всего — минуты от полуночи.
    var usualTimes: [Int]

    static let empty = WalkRhythm(days: 0, outingsPerDay: 0, averageIndoors: 0,
                                  longestIndoors: 0, usualTimes: [])

    /// Ниже этого выводов не делаем и говорим об этом прямо.
    static let minimumDays = 3

    var isReliable: Bool { days >= Self.minimumDays }
}

nonisolated enum WalkRhythmAnalyzer {
    /// Две недели: достаточно, чтобы увидеть режим, и мало, чтобы тащить
    /// прошлую жизнь — переезд, болезнь, другой график работы.
    static let windowDays = 14

    /// Промежутки длиннее этого в среднее не берём: это ночь, а не
    /// «собака терпела». Ночной перерыв — отдельный разговор.
    static let nightThreshold: TimeInterval = 7 * 3600

    static func rhythm(
        events: [LogEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WalkRhythm {
        let outings = Diary.active(events)
            // Отметки внутри прогулки не считаются отдельными выходами:
            // иначе одна прогулка с тремя отметками выглядела бы как
            // четыре выхода, и цифра врала бы втрое.
            .filter { ($0.kind == .walk || $0.kind == .outing) && $0.walkEventID == nil }
            .sorted { $0.date < $1.date }

        let from = calendar.date(byAdding: .day, value: -windowDays,
                                 to: calendar.startOfDay(for: now)) ?? now
        let recent = outings.filter { $0.date >= from }
        guard !recent.isEmpty else { return .empty }

        let byDay = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.date) }
        let days = byDay.count

        // Промежутки считаются от конца выхода: пока гуляли, собака
        // не была дома.
        var gaps: [TimeInterval] = []
        for (index, outing) in recent.enumerated() where index + 1 < recent.count {
            let ended = outing.date.addingTimeInterval(Double(outing.durationSeconds ?? 0))
            let gap = recent[index + 1].date.timeIntervalSince(ended)
            guard gap > 0, gap < nightThreshold else { continue }
            gaps.append(gap)
        }

        return WalkRhythm(
            days: days,
            outingsPerDay: Double(recent.count) / Double(max(1, days)),
            averageIndoors: gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count),
            longestIndoors: gaps.max() ?? 0,
            usualTimes: FeedingAnalyzer.mealTimeClusters(
                days: byDay.map { day, items in
                    FeedingReport.Day(
                        date: day,
                        grams: 0,
                        mealMinutes: items.map { minuteOfDay($0.date, calendar: calendar) }.sorted(),
                        isComplete: true
                    )
                }.sorted { $0.date < $1.date }
            )
        )
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
