import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("День с собакой")
@MainActor
struct DayOutTests {

    private func стич(meals: [Int] = [8 * 60, 14 * 60, 20 * 60]) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.7)
        dog.mealsPerDay = meals.count
        dog.setDailyGrams(195)
        dog.mealTimes = meals
        return dog
    }

    private func today(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    @Test("Еды берём по кормлениям в окне, а не по норме, делённой на часы")
    func packingCountsMeals() {
        // Собака ест порциями. Половину порции с собой не берут.
        let dog = стич()
        let packing = DayOutPlan.packing(for: dog, hours: 8, from: today(10))

        // В окно 10:00–18:00 попадает одно кормление — в 14:00.
        #expect(packing.meals == 1)
        #expect(packing.grams == dog.servingGrams)
        // Плюс одна запасная порция.
        #expect(packing.totalGrams == dog.servingGrams * 2)
    }

    @Test("Короткая отлучка обходится без корма")
    func shortTripNeedsNoFood() {
        let packing = DayOutPlan.packing(for: стич(), hours: 2, from: today(10))
        #expect(packing.meals == 0)
        #expect(packing.grams == 0)
    }

    @Test("Длинный день переваливает за полночь и не теряет кормления")
    func longDayCrossesMidnight() {
        let packing = DayOutPlan.packing(for: стич(), hours: 14, from: today(16))
        // 16:00 + 14 ч = 06:00 следующего дня: ужин сегодня в 20:00.
        #expect(packing.meals == 1)
    }

    @Test("День идёт, пока его не закончили")
    func dayRunsUntilFinished() {
        let day = DayOut(startedAt: today(9), plannedHours: 5)
        #expect(day.isActive(at: today(12)))

        day.endedAt = today(15)
        #expect(!day.isActive(at: today(16)))
        #expect(day.duration() == 6 * 3600)
    }

    @Test("Про завтра говорим только после долгого дня")
    func restAdviceOnlyWhenLong() {
        #expect(DayOutPlan.restAdvice(hours: 3) == nil)
        #expect(DayOutPlan.restAdvice(hours: 7) != nil)
        #expect(DayOutPlan.restAdvice(hours: 12) != DayOutPlan.restAdvice(hours: 7))
    }

    @Test("Вода предлагается по расписанию, а не когда вспомнили")
    func waterCadence() {
        let start = today(9)
        #expect(DayOutPlan.nextWater(after: nil, start: start) == start.addingTimeInterval(2 * 3600))
        let offered = today(10, 30)
        #expect(DayOutPlan.nextWater(after: offered, start: start)
                == offered.addingTimeInterval(2 * 3600))
    }
}

@Suite("След долгих дней")
@MainActor
struct DayOutTraceTests {

    private func день(_ daysAgo: Int, hours: Double) -> DayOut {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let day = DayOut(startedAt: start, plannedHours: Int(hours))
        day.endedAt = start.addingTimeInterval(hours * 3600)
        return day
    }

    private func запись(_ daysAgo: Int, kind: LogKind, stool: StoolForm? = nil,
                       grams: Int? = nil) -> LogEvent {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let event = LogEvent(kind: kind, date: date, authorName: "Виктория")
        event.stoolForm = stool
        event.grams = grams
        return event
    }

    @Test("Двух случаев мало — приложение молчит")
    func twoDaysIsNotAPattern() {
        let trace = DayOutAnalyzer.trace(
            daysOut: [день(5, hours: 8), день(3, hours: 9)],
            events: [запись(4, kind: .stool, stool: .liquid), запись(2, kind: .stool, stool: .liquid)],
            norm: 195
        )
        #expect(!trace.isReliable)
        #expect(trace.findings.isEmpty)
    }

    @Test("Совпадение находится и называется совпадением")
    func patternIsFound() {
        let days = [день(9, hours: 8), день(7, hours: 8), день(5, hours: 9), день(3, hours: 10)]
        let events = [
            запись(8, kind: .stool, stool: .liquid),
            запись(6, kind: .stool, stool: .liquid),
            запись(4, kind: .stool, stool: .liquid),
            запись(2, kind: .stool, stool: .sausage),
        ]
        let trace = DayOutAnalyzer.trace(daysOut: days, events: events, norm: 195)

        #expect(trace.longDays == 4)
        #expect(trace.followedByLooseStool == 3)
        #expect(trace.findings.contains { $0.contains("жиже") })
    }

    @Test("Короткие дни в наблюдение не идут")
    func shortDaysIgnored() {
        let trace = DayOutAnalyzer.trace(
            daysOut: [день(5, hours: 2), день(4, hours: 3), день(3, hours: 1)],
            events: [запись(4, kind: .stool, stool: .liquid)],
            norm: 195
        )
        #expect(trace.longDays == 0)
    }

    @Test("День без записей на следующий ничего не говорит")
    func silentNextDayCountsForNothing() {
        let trace = DayOutAnalyzer.trace(
            daysOut: [день(9, hours: 8), день(7, hours: 8), день(5, hours: 8)],
            events: [],
            norm: 195
        )
        #expect(trace.longDays == 3)
        #expect(trace.followedByLooseStool == 0)
        #expect(trace.findings.isEmpty)
    }
}

@Suite("Как часто гуляем")
@MainActor
struct WalkRhythmTests {

    private func выход(_ daysAgo: Int, hour: Int, minutes: Int = 0) -> LogEvent {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo,
                                        to: Calendar.current.startOfDay(for: Date()))!
        let event = LogEvent(kind: .walk, date: day.addingTimeInterval(Double(hour) * 3600),
                             authorName: "Виктория")
        if minutes > 0 { event.durationSeconds = minutes * 60 }
        return event
    }

    @Test("Считаются выходы, а не отметки внутри них")
    func marksDoNotInflateTheCount() {
        // Одна прогулка с тремя отметками — это один выход, а не четыре.
        let walk = выход(1, hour: 9, minutes: 30)
        let marks = (0..<3).map { index -> LogEvent in
            let mark = LogEvent(kind: .outing,
                                date: walk.date.addingTimeInterval(Double(index) * 300),
                                authorName: "Виктория")
            mark.walkEventID = walk.id
            return mark
        }
        let rhythm = WalkRhythmAnalyzer.rhythm(events: [walk] + marks)
        #expect(rhythm.outingsPerDay == 1)
    }

    @Test("Промежуток меряется от конца выхода")
    func gapFromEnd() {
        let events = [выход(1, hour: 9, minutes: 60), выход(1, hour: 13)]
        let rhythm = WalkRhythmAnalyzer.rhythm(events: events)
        // С 10:00 до 13:00 — три часа, а не четыре от начала прогулки.
        #expect(rhythm.averageIndoors == 3 * 3600)
    }

    @Test("Ночь в среднее не идёт")
    func nightIsNotWaiting() {
        let events = [выход(2, hour: 21), выход(1, hour: 8)]
        let rhythm = WalkRhythmAnalyzer.rhythm(events: events)
        #expect(rhythm.averageIndoors == 0)
    }

    @Test("Меньше трёх дней — выводов не делаем")
    func notEnoughDays() {
        let rhythm = WalkRhythmAnalyzer.rhythm(events: [выход(1, hour: 9)])
        #expect(!rhythm.isReliable)
    }

    /// # Три дня с выходами дают ТРИ дня, а не два
    ///
    /// Повод — кадр отзыва 30.10.2026: экран говорил «нужно хотя бы
    /// 3 дня с записями — пока их 2», а в журнале действий того же
    /// телефона выходы отмечены в ТРИ разных дня (27, 28, 29 октября;
    /// смещение +1 ни одной записи через полночь не переносит).
    ///
    /// **Этот тест — различитель, а не починка.** Он отвечает ровно
    /// на один вопрос: ошибается ли арифметика. Если зелёный — считает
    /// она верно, и расхождение надо искать в данных: у человека
    /// в базе были записи-дубли собаки, а ритм считается по АКТИВНОЙ,
    /// то есть часть дней достаётся второй записи и до экрана
    /// не доходит.
    ///
    /// Несколько выходов в один день берутся нарочно: день обязан
    /// считаться один раз, иначе порог «три дня» брался бы за сутки.
    @Test("Три дня с выходами дают три дня, сколько бы их ни было за день")
    func тридняСчитаютсяТремя() {
        let события = [
            выход(3, hour: 8), выход(3, hour: 14), выход(3, hour: 21),
            выход(2, hour: 9),
            выход(1, hour: 7), выход(1, hour: 19),
        ]
        let ритм = WalkRhythmAnalyzer.rhythm(events: события)

        #expect(ритм.days == 3, """
            дней с записями насчитано \(ритм.days) при трёх разных \
            датах. Экран показывает это число человеку словами \
            «пока их N», и ошибка здесь читается как «ты мало гуляешь».
            """)
        #expect(ритм.isReliable, "три дня — это порог, а не «меньше трёх»")
        #expect(ритм.outingsPerDay == 2, """
            выходов в день \(ритм.outingsPerDay) при шести выходах \
            за три дня. Два — это среднее, и считается оно по тем же \
            дням, что и порог.
            """)
    }
}

@Suite("Сколько прошло с прогулки")
@MainActor
struct SinceWalkTests {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    @Test("Считается от конца прогулки, а не от начала")
    func countsFromEnd() {
        let walk = LogEvent(kind: .walk, date: at(6, 34), authorName: "Виктория")
        walk.durationSeconds = 43 * 60          // как в живом дневнике

        let blocks = TimelineBuilder.blocks([walk])
        let indoors = try! #require(
            TimelineBuilder.timeIndoorsNow(blocks, now: at(9, 17), threshold: 0)
        )
        // С 07:17 до 09:17 — два часа, а не два сорок три от начала.
        #expect(indoors == 2 * 3600)
    }

    @Test("Кормление между прогулками счётчик не сбивает")
    func mealDoesNotReset() {
        // Раньше «сейчас» считалось от последней записи любого вида,
        // и ужин обнулял цифру: «прошло десять минут» при трёх часах.
        let walk = LogEvent(kind: .walk, date: at(6, 34), authorName: "Виктория")
        walk.durationSeconds = 43 * 60
        let meal = LogEvent(kind: .meal, date: at(8, 49), authorName: "Виктория")

        let blocks = TimelineBuilder.blocks([walk, meal])
        let indoors = try! #require(
            TimelineBuilder.timeIndoorsNow(blocks, now: at(9, 17), threshold: 0)
        )
        #expect(indoors == 2 * 3600)
    }

    @Test("Отметки внутри прогулки не считаются выходами")
    func marksAreNotOutings() {
        let walk = LogEvent(kind: .walk, date: at(6, 34), authorName: "Виктория")
        walk.durationSeconds = 43 * 60
        let mark = LogEvent(kind: .outing, date: at(6, 42), authorName: "Виктория")
        mark.walkEventID = walk.id

        let blocks = TimelineBuilder.blocks([walk, mark])
        let indoors = try! #require(
            TimelineBuilder.timeIndoorsNow(blocks, now: at(9, 17), threshold: 0)
        )
        // От конца прогулки в 07:17, а не от отметки в 06:42.
        #expect(indoors == 2 * 3600)
    }

    @Test("Без выходов сегодня цифры нет")
    func noOutingsNoNumber() {
        let meal = LogEvent(kind: .meal, date: at(8, 49), authorName: "Виктория")
        let blocks = TimelineBuilder.blocks([meal])
        #expect(TimelineBuilder.timeIndoorsNow(blocks, now: at(9, 17), threshold: 0) == nil)
    }

    /// От обратного: утверждение «выход был» обязано дожить до экрана.
    /// «Не все выходы теряются» выполнялось бы и при потере каждого.
    @Test("Только что вернувшаяся прогулка обязана дать число, а не nil")
    func justReturnedStillCounts() {
        // Ровно кадр тестировщицы 24.09: прогулка 14:13–16:01, а снимок
        // `now` у экрана отстал на минуту — тик ходит раз в тридцать
        // секунд. Конец выхода оказался в будущем, разность ушла в минус,
        // и минус возвращался тем же `nil`, что и «выходов не было»:
        // экран писал «Сегодня ещё не выходили» над лентой с двумя
        // прогулками, Siri отвечала то же самое.
        let walk = LogEvent(kind: .walk, date: at(14, 13), authorName: "Виктория")
        walk.durationSeconds = 108 * 60          // до 16:01

        let blocks = TimelineBuilder.blocks([walk])
        let indoors = try! #require(
            TimelineBuilder.timeIndoorsNow(blocks, now: at(16, 0), threshold: 0)
        )
        // Дома нисколько — только что вернулись. Не «не выходили».
        #expect(indoors == 0)
    }

    @Test("Отставший снимок времени не рвёт промежуток в ленте")
    func staleNowKeepsGapQuiet() {
        // Оборотная сторона того же: у промежутка в ленте порог час,
        // и ноль его не проходит — строки «0 ч дома» не появляется.
        let walk = LogEvent(kind: .walk, date: at(14, 13), authorName: "Виктория")
        walk.durationSeconds = 108 * 60

        let blocks = TimelineBuilder.blocks([walk])
        #expect(TimelineBuilder.timeIndoorsNow(blocks, now: at(16, 0), threshold: 3600) == nil)
    }
}

@Suite("Молчащие напоминания ухода")
@MainActor
struct SilentCareTests {

    @Test("Дело без точки отсчёта не становится сроком — и это видно")
    func periodicWithoutLastDone() {
        // В живом дневнике таких дел оказалось шесть из девяти: заведены,
        // выглядят настроенными и не напоминают ни о чём.
        let task = CareTask(title: "Капли от клещей", detail: "",
                            kind: .periodic, intervalDays: 28, category: .medical)
        #expect(task.needsDate)
        #expect(task.dueDate == nil)
        #expect(!task.isDue())
    }

    @Test("Прививка без даты тоже молчит")
    func datedWithoutDate() {
        let task = CareTask(title: "Бешенство", detail: "",
                            kind: .dated, intervalDays: 365, category: .medical)
        #expect(task.needsDate)
        #expect(!task.isDue())
    }

    @Test("Ежедневное работает без даты — у него точка отсчёта каждый день")
    func dailyNeedsNothing() {
        let task = CareTask(title: "Зубы", detail: "", kind: .daily,
                            intervalDays: 1, category: .grooming)
        #expect(!task.needsDate)
        #expect(task.isDue())
    }

    @Test("Поставили дату — дело ожило")
    func dateMakesItLive() {
        let task = CareTask(title: "Уши", detail: "", kind: .periodic,
                            intervalDays: 7, category: .grooming)
        task.lastDone = Calendar.current.date(byAdding: .day, value: -8, to: Date())

        #expect(!task.needsDate)
        #expect(task.isDue())
    }
}
