import Foundation

/// Когда доза откроется.
///
/// Три случая, и человеку важно различать их словами, а не одинаковым
/// серым: доза открыта; доза ждёт таймера от еды; еды сегодня не было
/// вовсе — и тогда это не «подожди», а «спроси врача».
nonisolated enum DoseGate {
    enum State: Equatable, Sendable {
        /// Открыта: можно отмечать.
        case open
        /// Ждёт таймера, запущенного отметкой еды.
        case waiting(until: Date, since: Date)
        /// Еды сегодня ещё не было — цепочка не началась.
        case noMeal

        var isOpen: Bool { self == .open }
    }

    /// Состояние дозы на момент `now`.
    ///
    /// Отсчёт идёт от **фактической отметки еды**, а не от расписания:
    /// покормили в 8:05, а не в 8:00, и укол сдвигается ровно на эти
    /// пять минут.
    static func state(
        for medication: Medication,
        events: [LogEvent],
        scheduledAt scheduled: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> State {
        guard medication.dependsOnMeal else { return .open }

        // Берём последнее кормление до планового времени дозы: утренний
        // укол считается от утренней еды, а не от вчерашнего ужина.
        let meals = Diary.active(events)
            .filter { $0.kind == .meal && calendar.isDate($0.date, inSameDayAs: scheduled) }
            .filter { $0.date <= max(now, scheduled) }
            .sorted { $0.date < $1.date }

        guard let meal = meals.last else { return .noMeal }

        let opens = meal.date.addingTimeInterval(Double(medication.minutesAfterMeal) * 60)
        return now >= opens ? .open : .waiting(until: opens, since: meal.date)
    }

    /// Подпись под названием дозы.
    static func caption(_ state: State, now: Date = Date()) -> String? {
        switch state {
        case .open: return nil
        case .waiting(let until, _):
            return String(localized: "откроется через ") + Fmt.stopwatch(max(0, until.timeIntervalSince(now)))
        case .noMeal: return String(localized: "ждёт кормления")
        }
    }
}

/// Что делать с пропущенной дозой.
///
/// Три выхода, и ни один из них не называет человека виноватым: не «вы
/// забыли», а «что сделать сейчас». Рекомендация берётся из интервала
/// между приёмами, а решение остаётся за человеком — приложение
/// не назначает лечение.
nonisolated struct MissedDose: Equatable, Sendable {
    /// Плановое время пропущенной дозы.
    var scheduledAt: Date
    /// Когда закрылось окно.
    var windowClosedAt: Date
    /// Следующая доза по расписанию.
    var nextScheduled: Date?
    /// Куда сдвинется следующая, если дать сейчас.
    var nextIfGivenNow: Date?
    /// Интервал между «дать сейчас» и сдвинутой следующей.
    var intervalIfGivenNow: TimeInterval?

    /// Сколько осталось до следующей по расписанию.
    func timeToNext(from now: Date) -> TimeInterval? {
        nextScheduled.map { max(0, $0.timeIntervalSince(now)) }
    }
}

nonisolated enum MissedDoseAdvisor {
    /// Насколько доза считается просроченной, а не «вот-вот дадут».
    static let window: TimeInterval = 60 * 60

    static func evaluate(
        medication: Medication,
        scheduledAt scheduled: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MissedDose? {
        let closed = scheduled.addingTimeInterval(window)
        guard now > closed else { return nil }

        // Следующая доза может быть и завтра — а пропускают чаще всего
        // как раз вечернюю, последнюю за день. Без завтрашней точки
        // строка «до следующей дозы» пропадала ровно там, где нужнее
        // всего.
        let startOfDay = calendar.startOfDay(for: scheduled)
        let times = medication.times.sorted()
        let today = times.map { calendar.date(minuteOfDay: $0, on: startOfDay) }
        let upcoming = today.first { $0 > scheduled }
            ?? times.first.flatMap { minute in
                calendar.date(byAdding: .day, value: 1, to: startOfDay)
                    .map { calendar.date(minuteOfDay: minute, on: $0) }
            }

        // Интервал между приёмами — из расписания самого препарата.
        // Если приём один в день, сдвигать нечего.
        var shifted: Date?
        var interval: TimeInterval?
        if let upcoming, medication.times.count > 1 {
            let planned = upcoming.timeIntervalSince(scheduled)
            shifted = now.addingTimeInterval(planned)
            interval = planned
        }

        return MissedDose(scheduledAt: scheduled,
                          windowClosedAt: closed,
                          nextScheduled: upcoming,
                          nextIfGivenNow: shifted,
                          intervalIfGivenNow: interval)
    }
}
