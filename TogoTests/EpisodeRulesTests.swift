import Testing
import Foundation
import SwiftData
@testable import Togo

/// Эпизод по жидкому стулу и дни, которые эпизод накрывает.
///
/// До 30.09.2026 экран истории обещал эпизод «по нескольким дням подряд
/// с жидким стулом», а поднимали его только два инцидента за сутки.
@Suite("Правила эпизода")
@MainActor
struct EpisodeRulesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }

    /// 30.09.2026, 10:00 по Парижу.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)) ?? Date()
    }

    private func stool(_ form: StoolForm, daysAgo: Int, hour: Int = 9) -> LogEvent {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        let event = LogEvent(kind: .stool, date: date, authorName: "Виктория")
        event.stoolForm = form
        return event
    }

    @Test("Жидкий — это Бристоль 6 и выше: кашица и лужа")
    func looseIsBristolSix() {
        #expect(EpisodeRules.isLoose(stool(.mushy, daysAgo: 0)))
        #expect(EpisodeRules.isLoose(stool(.liquid, daysAgo: 0)))
        #expect(!EpisodeRules.isLoose(stool(.soft, daysAgo: 0)))
        #expect(!EpisodeRules.isLoose(stool(.sausage, daysAgo: 0)))
    }

    @Test("Вчера и сегодня жидкий — эпизод открывается")
    func twoDaysInARowOpen() {
        let events = [stool(.liquid, daysAgo: 1, hour: 20), stool(.mushy, daysAgo: 0, hour: 8)]
        #expect(EpisodeRules.shouldOpenForLooseStool(events, hasActiveEpisode: false,
                                                     now: now, calendar: calendar))
        #expect(EpisodeRules.looseStoolStreak(events, now: now, calendar: calendar).count == 2)
    }

    @Test("Два жидких за один день — ещё не серия дней")
    func sameDayIsNotAStreak() {
        let events = [stool(.liquid, daysAgo: 0, hour: 7), stool(.liquid, daysAgo: 0, hour: 9)]
        #expect(!EpisodeRules.shouldOpenForLooseStool(events, hasActiveEpisode: false,
                                                      now: now, calendar: calendar))
    }

    @Test("Разрыв в день или нормальный стул сегодня — эпизода нет")
    func gapOrNormalTodayDoesNotOpen() {
        let gap = [stool(.liquid, daysAgo: 2), stool(.liquid, daysAgo: 0)]
        #expect(!EpisodeRules.shouldOpenForLooseStool(gap, hasActiveEpisode: false,
                                                      now: now, calendar: calendar))
        let normalToday = [stool(.liquid, daysAgo: 1), stool(.sausage, daysAgo: 0, hour: 8)]
        #expect(!EpisodeRules.shouldOpenForLooseStool(normalToday, hasActiveEpisode: false,
                                                      now: now, calendar: calendar))
    }

    @Test("Поверх идущего эпизода второй не открывается")
    func noSecondEpisode() {
        let events = [stool(.liquid, daysAgo: 1), stool(.liquid, daysAgo: 0, hour: 8)]
        #expect(!EpisodeRules.shouldOpenForLooseStool(events, hasActiveEpisode: true,
                                                      now: now, calendar: calendar))
    }

    @Test("Удалённая запись в серию не входит")
    func deletedDoesNotCount() {
        let вчера = stool(.liquid, daysAgo: 1)
        вчера.deletedAt = now
        let events = [вчера, stool(.liquid, daysAgo: 0, hour: 8)]
        #expect(!EpisodeRules.shouldOpenForLooseStool(events, hasActiveEpisode: false,
                                                      now: now, calendar: calendar))
    }

    @Test("Эпизод накрывает дни от начала до тишины, но не дальше сегодня")
    func windowCoversDays() {
        let started = calendar.date(byAdding: .day, value: -5, to: now) ?? now
        let window = EpisodeRules.window(startedAt: started, endedAt: nil,
                                         quietUntil: started.addingTimeInterval(Episode.quietPeriod),
                                         now: now)
        let day = { (ago: Int) in calendar.date(byAdding: .day, value: -ago, to: now) ?? now }
        #expect(EpisodeRules.isCovered(day(5), by: [window], calendar: calendar))
        #expect(EpisodeRules.isCovered(day(3), by: [window], calendar: calendar))
        #expect(!EpisodeRules.isCovered(day(2), by: [window], calendar: calendar))
        #expect(!EpisodeRules.isCovered(day(6), by: [window], calendar: calendar))
    }

    @Test("Закрытый руками эпизод кончается в момент закрытия")
    func closedWindowEndsAtClose() {
        let started = calendar.date(byAdding: .day, value: -4, to: now) ?? now
        let closed = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let window = EpisodeRules.window(startedAt: started, endedAt: closed,
                                         quietUntil: now, now: now)
        #expect(window.upperBound == closed)
        #expect(EpisodeRules.touches(window, anyOf: [started.addingTimeInterval(3600)]))
        #expect(!EpisodeRules.touches(window, anyOf: [now]))
    }
}

/// Выгрузка истории врачу: строка на день, пустое — пусто, а не ноль.
@Suite("История врачу · CSV")
@MainActor
struct HistoryExportTests {
    @Test("День без значения — пустая клетка, дозы с временем и названием")
    func rowsPerDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let meal = LogEvent(kind: .meal, date: today.addingTimeInterval(9 * 3600), authorName: "Виктория")
        meal.grams = 60
        let dose = HistoryExport.Dose(at: today.addingTimeInterval(8 * 3600), name: "Forthyron")

        let csv = HistoryExport.csv(days: [yesterday, today], valueTitle: "Вес",
                                    values: [today: 4.1], events: [meal],
                                    doses: [dose], episodeDays: [yesterday],
                                    calendar: calendar)
        let rows = csv.components(separatedBy: "\n")
        #expect(rows.count == 3)
        let вчера = rows[1].components(separatedBy: ";")
        let сегодня = rows[2].components(separatedBy: ";")
        #expect(вчера[1].isEmpty, "день без взвешивания — не ноль килограммов")
        #expect(!вчера[5].isEmpty, "день эпизода помечен")
        #expect(сегодня[1] == "4,1")
        #expect(сегодня[2] == "60")
        #expect(сегодня[3] == "1")
        #expect(сегодня[4].contains("Forthyron"))
        #expect(сегодня[5].isEmpty)
    }
}
