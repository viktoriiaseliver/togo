import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("Выборки по ленте")
@MainActor
struct DiaryTests {
    /// Каждый тест получает свою базу в памяти — они не мешают друг другу.
    private func makeContext() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private func event(_ kind: LogKind, minutesAgo: Int, author: String = "Виктория") -> LogEvent {
        LogEvent(kind: kind, date: Date().addingTimeInterval(-Double(minutesAgo) * 60), authorName: author)
    }

    @Test("«Как всегда» доступно только при четырёх одинаковых записях подряд")
    func usualStoolNeedsFourMatching() {
        var events: [LogEvent] = []
        for index in 0..<4 {
            let stool = event(.stool, minutesAgo: index * 600)
            stool.stoolForm = .sausage
            events.append(stool)
        }
        #expect(Diary.usualStool(events) == .sausage)

        // Одна запись с особенностью — и «как всегда» пропадает.
        events[1].stoolFlags = [.mucus]
        #expect(Diary.usualStool(events) == nil)

        // Трёх совпадений мало.
        #expect(Diary.usualStool(Array(events.prefix(3))) == nil)
    }

    @Test("Разные формы подряд не дают «как всегда»")
    func usualStoolNeedsSameForm() {
        var events: [LogEvent] = []
        for (index, form) in [StoolForm.sausage, .soft, .sausage, .sausage].enumerated() {
            let stool = event(.stool, minutesAgo: index * 600)
            stool.stoolForm = form
            events.append(stool)
        }
        #expect(Diary.usualStool(events) == nil)
    }

    @Test("Два жидких с кровью подряд предлагают выписку")
    func vetReportSuggestion() {
        var events: [LogEvent] = []
        for index in 0..<2 {
            let stool = event(.stool, minutesAgo: index * 300)
            stool.stoolForm = .liquid
            stool.stoolFlags = [.blood]
            events.append(stool)
        }
        #expect(Diary.suggestsVetReport(events))

        events[0].stoolFlags = []
        #expect(!Diary.suggestsVetReport(events))
    }

    @Test("Кровь поднимает запись в терракот, слизь — нет")
    func bloodRaisesAlarm() {
        let stool = event(.stool, minutesAgo: 10)
        stool.stoolFlags = [.mucus]
        #expect(!stool.raisesAlarm)
        stool.stoolFlags = [.mucus, .blood]
        #expect(stool.raisesAlarm)
    }

    @Test("Второй инцидент за сутки попадает в окно эпизода")
    func incidentsWindow() {
        let events = [
            event(.incident, minutesAgo: 30),
            event(.incident, minutesAgo: 400),
            event(.incident, minutesAgo: 60 * 30),   // сутки с лишним назад
        ]
        #expect(Diary.incidentsInLast24h(events).count == 2)
    }

    @Test("Две записи об одном событии от разных людей дают карточку слияния")
    func mergeCandidates() {
        let mine = event(.meal, minutesAgo: 10, author: "Тео")
        let hers = event(.meal, minutesAgo: 17, author: "Мама")
        let later = event(.meal, minutesAgo: 200, author: "Мама")
        let pairs = Diary.mergeCandidates([mine, hers, later])
        #expect(pairs.count == 1)
    }

    @Test("Свои же записи подряд слиянием не считаются")
    func sameAuthorIsNotConflict() {
        let first = event(.meal, minutesAgo: 10, author: "Тео")
        let second = event(.meal, minutesAgo: 15, author: "Тео")
        #expect(Diary.mergeCandidates([first, second]).isEmpty)
    }

    @Test("Удалённые записи не участвуют ни в одной выборке")
    func deletedAreInvisible() {
        let alive = event(.outing, minutesAgo: 10)
        let removed = event(.outing, minutesAgo: 20)
        removed.deletedAt = Date()
        #expect(Diary.active([alive, removed]).count == 1)
    }

    @Test("«Как попросил» спрашивают раз в пять выходов")
    func askCadence() {
        var events: [LogEvent] = []
        for index in 0..<2 {
            let outing = event(.outing, minutesAgo: 1000 - index * 100)
            outing.askSignal = .satAtDoor
            events.append(outing)
        }
        // Сразу после ответа не спрашиваем.
        #expect(!Diary.shouldAskHowAsked(events))

        for index in 0..<5 {
            events.append(event(.outing, minutesAgo: 500 - index * 60))
        }
        #expect(Diary.shouldAskHowAsked(events))
    }

    @Test("Сводка дня складывает граммы, миллилитры и выходы")
    func daySummary() {
        // День задан явно, а не «час назад»: под утро такой тест уезжает
        // во вчера и падает на ровном месте. Полдень — безопасная точка.
        let полдень = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: .now
        ) ?? .now

        func запись(_ kind: LogKind, час: Int) -> LogEvent {
            LogEvent(kind: kind,
                     date: полдень.addingTimeInterval(Double(час - 12) * 3600),
                     authorName: "Виктория")
        }

        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        let meal = запись(.meal, час: 8); meal.grams = 60
        let outing = запись(.outing, час: 11)
        let summary = Diary.summary([meal, outing], day: полдень, dog: dog)
        #expect(summary.eatenGrams == 60)
        #expect(summary.outings == 1)
        #expect(summary.dailyGrams == 120)
    }
}
