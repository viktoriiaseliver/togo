import Foundation

/// Когда приложение само поднимает эпизод и какие дни он накрывает.
///
/// Эпизод поднимается двумя путями: два инцидента за сутки
/// (`Diary.incidentsInLast24h`, зовёт `IncidentSheet`) и жидкий стул
/// несколько дней подряд — это правило здесь, зовёт его `StoolSheet`.
/// До 30.09.2026 второй путь был только обещанием на экране истории:
/// эпизод по стулу не поднимался ничем.
nonisolated enum EpisodeRules {
    /// «Жидкий» в проекте — Бристоль 6 и выше, то есть кашица и лужа.
    /// Та же граница, что в `DayOutAnalyzer`: два определения жидкого
    /// в одном приложении дали бы два ответа на один вопрос.
    static let looseBristol = 6

    /// Сколько календарных дней подряд, включая сегодня, нужно жидкого
    /// стула, чтобы поднять эпизод.
    static let looseStoolDays = 2

    static func isLoose(_ event: LogEvent) -> Bool {
        (event.stoolForm?.bristolScore ?? 0) >= looseBristol
    }

    /// Записи жидкого стула за последние `looseStoolDays` календарных дня,
    /// если жидкий был в **каждый** из них, включая сегодня. Иначе пусто.
    ///
    /// Дни календарные, а не «последние 48 часов»: вечер вчера и утро
    /// сегодня — это два дня подряд, как их и называет человек.
    static func looseStoolStreak(_ events: [LogEvent],
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> [LogEvent] {
        let loose = Diary.active(events).filter { $0.date <= now && isLoose($0) }
        let today = calendar.startOfDay(for: now)
        var streak: [LogEvent] = []
        for offset in 0..<looseStoolDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            let ofDay = loose.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard !ofDay.isEmpty else { return [] }
            streak += ofDay
        }
        return streak
    }

    /// Открыть эпизод по стулу: серия есть, а идущего эпизода нет.
    /// Второй эпизод поверх идущего не заводится — это то же самое
    /// расстройство, а не новое.
    static func shouldOpenForLooseStool(_ events: [LogEvent],
                                        hasActiveEpisode: Bool,
                                        now: Date = Date(),
                                        calendar: Calendar = .current) -> Bool {
        guard !hasActiveEpisode else { return false }
        return !looseStoolStreak(events, now: now, calendar: calendar).isEmpty
    }

    // MARK: Какие дни накрывает эпизод

    /// Промежуток эпизода: от начала до ручного закрытия или до конца
    /// тишины (`Episode.quietUntil`), но не дальше `now`.
    static func window(startedAt: Date, endedAt: Date?, quietUntil: Date,
                       now: Date = Date()) -> ClosedRange<Date> {
        let end = min(endedAt ?? quietUntil, now)
        return startedAt...max(startedAt, end)
    }

    static func window(of episode: Episode, now: Date = Date()) -> ClosedRange<Date> {
        window(startedAt: episode.startedAt, endedAt: episode.endedAt,
               quietUntil: episode.quietUntil, now: now)
    }

    /// Накрыт ли календарный день хотя бы одним эпизодом.
    static func isCovered(_ day: Date, by windows: [ClosedRange<Date>],
                          calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return windows.contains { $0.lowerBound < end && $0.upperBound >= start }
    }

    /// Есть ли в промежутке эпизода хоть одна из дат.
    static func touches(_ span: ClosedRange<Date>, anyOf dates: [Date]) -> Bool {
        dates.contains { span.contains($0) }
    }
}
