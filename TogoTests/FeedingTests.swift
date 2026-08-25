import Testing
import Foundation
@testable import Togo

@Suite("Питание · сколько, сколько раз и во сколько")
@MainActor
struct FeedingTests {
    private let calendar = Calendar.current

    private func дата(_ дней: Int, час: Int, минута: Int = 0) -> Date {
        let день = calendar.date(byAdding: .day, value: -дней, to: calendar.startOfDay(for: .now))!
        return день.addingTimeInterval(Double(час * 60 + минута) * 60)
    }

    private func еда(_ дней: Int, час: Int, минута: Int = 0, граммы: Int) -> LogEvent {
        let event = LogEvent(kind: .meal, date: дата(дней, час: час, минута: минута), authorName: "Виктория")
        event.grams = граммы
        return event
    }

    private func стич() -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        dog.mealsPerDay = 2
        dog.mealTimes = [7 * 60 + 30, 18 * 60 + 30]
        return dog
    }

    @Test("Меньше трёх полных дней — выводов не делаем")
    func notEnoughData() {
        let events = [еда(1, час: 8, граммы: 60), еда(2, час: 8, граммы: 60)]
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .notEnoughData(days: 2))
        #expect(report.suggestedPortionGrams == nil)
    }

    @Test("Ест по норме — менять нечего")
    func onNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 60))
            events.append(еда(день, час: 18, минута: 30, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .onNorm)
        #expect(report.averageGramsPerDay == 120)
        #expect(report.suggestedPortionGrams == nil)
    }

    @Test("Переедание видно и меряется в процентах")
    func overNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 80))
            events.append(еда(день, час: 18, минута: 30, граммы: 80))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .overNorm)
        #expect(report.deviationPercent == 33)
    }

    @Test("Недоедание тоже видно")
    func underNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 40))
            events.append(еда(день, час: 18, минута: 30, граммы: 40))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .underNorm)
        #expect(report.deviationPercent < 0)
    }

    @Test("Меньше грамм за раз — меньше во всех кормлениях сразу")
    func portionAppliesToEveryMeal() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, граммы: 90))
            events.append(еда(день, час: 19, граммы: 90))
        }
        let dog = стич()
        let report = FeedingAnalyzer.report(events: events, dog: dog)

        // Норма 120 г делится на два кормления — по 60 г, а не «уменьшить ужин».
        #expect(report.suggestedPortionGrams == 60)
        #expect(report.suggestedPortionGrams! * dog.mealsPerDay == dog.dailyGrams)
    }

    @Test("Предложенная порция округляется до пяти граммов")
    func portionRoundsToFive() {
        let dog = стич()
        dog.portionGrams = 47
        dog.mealsPerDay = 3
        var events: [LogEvent] = []
        for день in 1...5 {
            for час in [7, 13, 19] { events.append(еда(день, час: час, граммы: 70)) }
        }
        let report = FeedingAnalyzer.report(events: events, dog: dog)
        #expect(report.suggestedPortionGrams! % 5 == 0)
    }

    @Test("Дни без записей в среднее не попадают")
    func emptyDaysAreNotZeroes() {
        var events: [LogEvent] = []
        for день in [1, 2, 3, 8, 9] {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.averageGramsPerDay == 120)
        #expect(report.status == .onNorm)
    }

    @Test("Время кормления берётся из наблюдений, а не из расписания")
    func observedTimes() {
        var events: [LogEvent] = []
        // Кормит около восьми и около семи вечера — плюс-минус двадцать минут.
        for день in 1...7 {
            events.append(еда(день, час: 8, минута: день % 3 * 10, граммы: 60))
            events.append(еда(день, час: 19, минута: день % 2 * 15, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.observedMealTimes.count == 2)
        #expect(abs(report.observedMealTimes[0] - 8 * 60) <= 30)
        #expect(abs(report.observedMealTimes[1] - 19 * 60) <= 30)
    }

    @Test("Случайный ночной перекус расписанием не становится")
    func rareMealIsNotSchedule() {
        var events: [LogEvent] = []
        for день in 1...9 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        events.append(еда(4, час: 2, граммы: 10))
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.observedMealTimes.count == 2)
    }

    @Test("Три кормления раскладываются равномерно между первым и последним")
    func threeMealsSpread() {
        let dog = стич()
        dog.mealsPerDay = 3
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 40))
            events.append(еда(день, час: 20, граммы: 40))
        }
        let report = FeedingAnalyzer.report(events: events, dog: dog)
        #expect(report.suggestedMealTimes.count == 3)
        let intervals = zip(report.suggestedMealTimes, report.suggestedMealTimes.dropFirst()).map { $1 - $0 }
        #expect(Set(intervals).count == 1, "интервалы должны быть одинаковыми")
    }

    @Test("Задержка еда → стул считается по медиане")
    func stoolLag() {
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 60))
            let stool = LogEvent(kind: .stool, date: дата(день, час: 9, минута: 30), authorName: "Виктория")
            stool.stoolForm = .sausage
            events.append(stool)
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.stoolLagMinutes == 90)
        #expect(!report.suggestedOutingTimes.isEmpty)
    }

    @Test("Выходы предлагаются после каждого кормления и утром до еды")
    func outingsFollowMeals() {
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
            for час in [9, 20] {
                let stool = LogEvent(kind: .stool, date: дата(день, час: час), authorName: "Виктория")
                stool.stoolForm = .sausage
                events.append(stool)
            }
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.suggestedOutingTimes.count >= 3)
        // Утренний выход стоит до первого кормления.
        #expect(report.suggestedOutingTimes.first! < report.suggestedMealTimes.first!)
    }

    @Test("Стич на лечении: кормление внутри окна натощак показывается как конфликт")
    func fastingConflict() {
        // Доза в 07:00, натощак 45 минут → окно 07:00–07:45.
        let conflicts = FeedingAnalyzer.conflicts(
            mealTimes: [7 * 60 + 30, 19 * 60],
            fastingWindows: [(start: 7 * 60, end: 7 * 60 + 45)]
        )
        #expect(conflicts.count == 1)
        #expect(conflicts[0].contains("07:30"))
    }

    @Test("Окно натощак через полночь считается правильно")
    func fastingWindowWrapsMidnight() {
        let conflicts = FeedingAnalyzer.conflicts(
            mealTimes: [23 * 60 + 30, 12 * 60],
            fastingWindows: [(start: 23 * 60, end: 30)]
        )
        #expect(conflicts.count == 1)
    }

    @Test("Сегодняшний день считается отдельно и показывает остаток")
    func todayRemaining() {
        var events: [LogEvent] = []
        for день in 1...5 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        events.append(еда(0, час: 8, граммы: 60))
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.todayGrams == 60)
        #expect(report.todayMeals == 1)
        #expect(report.remainingGramsToday == 60)
    }

    @Test("Пустой дневник не роняет отчёт")
    func emptyDiary() {
        let report = FeedingAnalyzer.report(events: [], dog: стич())
        #expect(report.status == .notEnoughData(days: 0))
        #expect(report.todayGrams == 0)
        #expect(report.observedMealTimes.isEmpty)
        #expect(report.conflicts.isEmpty)
    }

    @Test("Без собаки отчёт тоже собирается")
    func noDog() {
        let report = FeedingAnalyzer.report(events: [], dog: nil)
        #expect(report.normGramsPerDay == 0)
        #expect(report.suggestedPortionGrams == nil)
    }
}
