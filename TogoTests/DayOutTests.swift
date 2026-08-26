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
}
