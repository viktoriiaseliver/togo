import Testing
import Foundation
import SwiftData
@testable import Togo

/// Проверки, выросшие из настоящего дневника на телефоне, а не из головы.
///
/// В базе живого устройства нашлось три вещи: три записи еды по 65 г
/// с интервалом в две секунды (человек жал кнопку, не получая отклика),
/// запись, выставленная на вечер того же дня, и девять напоминаний ухода,
/// которые никогда никому ни о чём не напомнили бы.
@Suite("Находки из живого дневника")
@MainActor
struct RealUsageTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private func стич(в context: ModelContext) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.73)
        dog.portionGrams = 65
        dog.mealsPerDay = 3
        context.insert(dog)
        return dog
    }

    // MARK: Двойной тап

    @Test("Три тапа по «Записать» подряд дают одну запись, а не три")
    func doubleTapDoesNotDuplicate() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState())

        // Ровно то, что случилось: 00:20:10, :12, :14, все по 65 г.
        let первая = log.record(.meal, dog: dog, confirmation: "Еда") { $0.grams = 65 }
        let вторая = log.record(.meal, dog: dog, at: .now.addingTimeInterval(2),
                                confirmation: "Еда") { $0.grams = 65 }
        let третья = log.record(.meal, dog: dog, at: .now.addingTimeInterval(4),
                                confirmation: "Еда") { $0.grams = 65 }

        #expect(первая != nil)
        #expect(вторая == nil, "второй тап за две секунды — это тот же тап")
        #expect(третья == nil)
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 1)
    }

    @Test("Человек всё-таки видит, почему запись не появилась")
    func duplicateExplainsItself() throws {
        let context = контекст()
        let dog = стич(в: context)
        let state = AppState()
        let log = EventLog(context: context, appState: state)

        log.record(.meal, dog: dog, confirmation: "Еда") { $0.grams = 65 }
        log.record(.meal, dog: dog, at: .now.addingTimeInterval(3), confirmation: "Еда") { $0.grams = 65 }

        #expect(state.undo?.message.contains("уже записана") == true)
    }

    @Test("Через полтора часа то же кормление — настоящее, а не повтор")
    func laterMealIsReal() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState())

        log.record(.meal, dog: dog, confirmation: nil) { $0.grams = 65 }
        log.record(.meal, dog: dog, at: .now.addingTimeInterval(90 * 60), confirmation: nil) { $0.grams = 65 }

        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 2)
    }

    @Test("Выходы и вода не считаются повторами: собака писает и пьёт когда хочет")
    func repeatableKindsAreNotDeduplicated() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState())

        for _ in 0..<3 {
            log.record(.outing, dog: dog, confirmation: nil)
            log.record(.water, dog: dog, confirmation: nil) { $0.milliliters = 50 }
        }
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 6)
    }

    // MARK: Уход, который молчал

    @Test("Регулярное дело без даты не молчит, а просит дату")
    func undatedTaskAsksForDate() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)

        #expect(когти.needsDate, "дело должно попасть в группу «нужна дата»")
        #expect(!когти.isDue(), "но не притворяться просрочкой")
        #expect(когти.statusText() == "когда делали?")
    }

    @Test("Поставили примерную дату — дело начинает работать")
    func dateMakesTaskWork() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = Calendar.current.date(byAdding: .month, value: -1, to: .now)

        #expect(!когти.needsDate)
        #expect(когти.isDue())
        #expect(когти.isOverdue())
    }

    @Test("Прививка без назначенного дня тоже просит дату")
    func undatedVaccine() {
        let прививка = CareTask(title: "Бешенство", detail: "", kind: .dated,
                                intervalDays: 365, category: .medical)
        #expect(прививка.needsDate)
        #expect(!прививка.isDue())
    }

    // MARK: Починка старого ухода

    @Test("«Уши и зубы» разделяются: зубы каждый день, уши раз в неделю")
    func migrationSplitsEarsAndTeeth() throws {
        let context = контекст()
        let dog = стич(в: context)
        let старое = CareTask(title: "Уши и зубы", detail: "раз в неделю",
                              kind: .periodic, intervalDays: 7)
        старое.dog = dog
        context.insert(старое)

        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        let зубы = дела.first { $0.title == "Зубы" }
        let уши = дела.first { $0.title == "Уши" }

        #expect(зубы?.kind == .daily, "налёт твердеет за сутки")
        #expect(уши?.kind == .periodic)
        #expect(уши?.intervalDays == 7)
        #expect(!дела.contains { $0.title == "Уши и зубы" })
    }

    @Test("Прививки переезжают с «раз в 365 дней» на конкретную дату")
    func migrationMovesVaccinesToDates() throws {
        let context = контекст()
        let dog = стич(в: context)
        for title in ["Бешенство", "Комплексная"] {
            let task = CareTask(title: title, detail: "раз в год", kind: .periodic,
                                intervalDays: 365, category: .medical)
            task.dog = dog
            context.insert(task)
        }

        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        #expect(дела.allSatisfy { $0.kind == .dated })
        #expect(дела.allSatisfy { $0.needsDate }, "дату поставит человек, выдумывать нельзя")
    }

    @Test("Починка не портит то, что уже правильно, и не работает дважды")
    func migrationIsIdempotent() throws {
        let context = контекст()
        let dog = стич(в: context)
        let зубы = CareTask(title: "Зубы", detail: "", kind: .daily, intervalDays: 1)
        зубы.dog = dog
        зубы.streak = 5
        context.insert(зубы)

        CareMigration.run(context: context)
        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        #expect(дела.count == 1, "второй раз ничего не добавилось")
        #expect(дела[0].streak == 5, "серия не сброшена")
    }

    // MARK: Запись в будущем

    @Test("Запись в будущем ломала бы вердикт")
    func futureRecordWouldBreakVerdict() {
        let сейчас = Date()
        let вечером = сейчас.addingTimeInterval(11 * 3600)

        let signals = NeedSignals(
            now: сейчас,
            lastUrine: вечером,
            urineIntervals: Array(repeating: 4 * 3600, count: 10),
            daysOfData: 10,
            lastOutingHadResult: true
        )

        // Интервал получается отрицательным — «только что выходили»,
        // хотя выход записан на вечер. Поэтому время правки ограничено
        // текущим моментом.
        #expect(signals.sinceUrine! < 0)
        #expect(VerdictEngine.evaluate(signals) != .urgent)
    }
}
