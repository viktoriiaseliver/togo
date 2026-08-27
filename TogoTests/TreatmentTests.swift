import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("Зависимая доза")
@MainActor
struct DoseGateTests {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private func инсулин() -> Medication {
        let medication = Medication(name: "Инсулин", doseText: "4 ед", times: [8 * 60])
        medication.minutesAfterMeal = 20
        return medication
    }

    private func еда(_ hour: Int, _ minute: Int) -> LogEvent {
        LogEvent(kind: .meal, date: at(hour, minute), authorName: "Наталья")
    }

    @Test("Обычная доза открыта всегда")
    func plainDoseIsOpen() {
        let apoquel = Medication(name: "Апоквел", doseText: "16 мг", times: [20 * 60])
        #expect(DoseGate.state(for: apoquel, events: [], scheduledAt: at(20)) == .open)
    }

    @Test("Таймер идёт от фактической отметки еды, а не от расписания")
    func timerStartsFromTheMark() {
        // Покормили в 8:05, а не в 8:00 — укол сдвигается ровно на эти
        // пять минут.
        let state = DoseGate.state(for: инсулин(), events: [еда(8, 5)],
                                   scheduledAt: at(8), now: at(8, 10))
        #expect(state == .waiting(until: at(8, 25), since: at(8, 5)))
    }

    @Test("Прошло двадцать минут — доза открылась")
    func opensAfterDelay() {
        let state = DoseGate.state(for: инсулин(), events: [еда(8, 5)],
                                   scheduledAt: at(8), now: at(8, 25))
        #expect(state == .open)
    }

    @Test("Не поела — укол не открывается вовсе")
    func noMealNoDose() {
        // Это не «подожди», а вопрос к врачу: колоть инсулин в пустой
        // желудок нельзя.
        let state = DoseGate.state(for: инсулин(), events: [], scheduledAt: at(8), now: at(9))
        #expect(state == .noMeal)
    }

    @Test("Вчерашний ужин утренний укол не открывает")
    func yesterdayMealDoesNotCount() {
        let вчера = LogEvent(kind: .meal,
                             date: at(19).addingTimeInterval(-86_400),
                             authorName: "Наталья")
        let state = DoseGate.state(for: инсулин(), events: [вчера],
                                   scheduledAt: at(8), now: at(9))
        #expect(state == .noMeal)
    }

    @Test("Подпись говорит, чего ждём")
    func captionExplains() {
        #expect(DoseGate.caption(.open) == nil)
        #expect(DoseGate.caption(.noMeal) == "ждёт кормления")
        let waiting = DoseGate.State.waiting(until: at(8, 25), since: at(8, 5))
        #expect(DoseGate.caption(waiting, now: at(8, 10))?.hasPrefix("откроется через") == true)
    }
}

@Suite("Пропущенная доза · три выхода")
@MainActor
struct MissedDoseTests {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private func дважды() -> Medication {
        Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 21 * 60])
    }

    @Test("Пока окно открыто, доза не считается пропущенной")
    func notMissedInsideWindow() {
        #expect(MissedDoseAdvisor.evaluate(medication: дважды(), scheduledAt: at(9),
                                           now: at(9, 40)) == nil)
    }

    @Test("Окно закрылось — предлагаем три выхода")
    func missedAfterWindow() throws {
        let missed = try #require(
            MissedDoseAdvisor.evaluate(medication: дважды(), scheduledAt: at(9), now: at(12, 40))
        )
        #expect(missed.windowClosedAt == at(10))
        #expect(missed.nextScheduled == at(21))
        // Дать сейчас — вечерняя сдвинется на тот же интервал, что
        // и в расписании: двенадцать часов от 12:40.
        #expect(missed.intervalIfGivenNow == Double(12 * 3600))
        #expect(missed.nextIfGivenNow == at(12, 40).addingTimeInterval(12 * 3600))
    }

    @Test("Сколько осталось до следующей по расписанию")
    func timeToNext() throws {
        let missed = try #require(
            MissedDoseAdvisor.evaluate(medication: дважды(), scheduledAt: at(9), now: at(12, 40))
        )
        #expect(missed.timeToNext(from: at(12, 40)) == Double(8 * 3600 + 20 * 60))
    }

    @Test("У вечерней дозы следующая — завтрашняя утренняя")
    func eveningLooksToTomorrow() throws {
        let missed = try #require(
            MissedDoseAdvisor.evaluate(medication: дважды(), scheduledAt: at(21), now: at(23))
        )
        let завтра = try #require(
            Calendar.current.date(byAdding: .day, value: 1, to: at(9))
        )
        #expect(missed.nextScheduled == завтра,
                "вечернюю пропускают чаще всего — именно здесь строка «до следующей» и пропадала")
        #expect(missed.intervalIfGivenNow == Double(12 * 3600))
    }

    @Test("У дозы раз в день следующая тоже есть — завтра")
    func onceADayStillHasNext() throws {
        let раз = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60])
        let missed = try #require(
            MissedDoseAdvisor.evaluate(medication: раз, scheduledAt: at(9), now: at(12))
        )
        let завтра = try #require(
            Calendar.current.date(byAdding: .day, value: 1, to: at(9))
        )
        #expect(missed.nextScheduled == завтра)
    }

    @Test("У дозы раз в день сдвигать нечего")
    func onceADayHasNoShift() throws {
        let раз = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60])
        let missed = try #require(
            MissedDoseAdvisor.evaluate(medication: раз, scheduledAt: at(9), now: at(12))
        )
        #expect(missed.nextIfGivenNow == nil)
        #expect(missed.intervalIfGivenNow == nil)
    }
}

@Suite("Порог тревоги")
@MainActor
struct AlarmThresholdTests {

    private func инцидент(_ hoursAgo: Double, kind: IncidentKind = .vomit,
                          detail: VomitDetail? = nil) -> LogEvent {
        let event = LogEvent(kind: .incident,
                             date: Date().addingTimeInterval(-hoursAgo * 3600),
                             authorName: "Наталья")
        event.incidentKind = kind
        event.vomitDetail = detail
        return event
    }

    @Test("Двух эпизодов мало")
    func twoIsNotEnough() {
        #expect(AlarmThresholdAnalyzer.evaluate(events: [инцидент(5), инцидент(1)]) == nil)
    }

    @Test("Три за шесть часов — порог")
    func threeInWindow() throws {
        let threshold = try #require(
            AlarmThresholdAnalyzer.evaluate(events: [инцидент(5.5), инцидент(3), инцидент(0.2)])
        )
        #expect(threshold.count == 3)
        #expect(threshold.kind == .vomit)
        #expect(threshold.headline.contains("третий раз"))
    }

    @Test("Старое за окном не считается")
    func outsideWindowIgnored() {
        #expect(AlarmThresholdAnalyzer.evaluate(
            events: [инцидент(20), инцидент(15), инцидент(1)]) == nil)
    }

    @Test("Разные инциденты в один порог не складываются")
    func differentKindsDoNotStack() {
        // Рвота плюс лужа плюс хромота — три разных наблюдения,
        // а не «третий раз».
        let events = [инцидент(4, kind: .vomit),
                      инцидент(2, kind: .puddle),
                      инцидент(1, kind: .other)]
        #expect(AlarmThresholdAnalyzer.evaluate(events: events) == nil)
    }

    @Test("Текст врачу собирается из записанного")
    func vetTextIsAssembled() throws {
        let dog = Dog(name: "Бим", weightKg: 12)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [8 * 60])
        let meal = LogEvent(kind: .meal, date: Date().addingTimeInterval(-9 * 3600),
                            authorName: "Наталья")
        let threshold = try #require(AlarmThresholdAnalyzer.evaluate(
            events: [инцидент(5.5, detail: .blood), инцидент(3), инцидент(0.2)]))

        let text = AlarmThresholdAnalyzer.vetText(threshold, dog: dog,
                                                  medications: [medication],
                                                  events: [meal])
        #expect(text.contains("Бим"))
        #expect(text.contains("апоквел"))
        #expect(text.contains("ел в"))
        // Приложение не ставит диагноз — только пересказывает записи.
        #expect(!text.lowercased().contains("диагноз"))
    }
}

@Suite("Пропуск — это запись, а не пустота")
@MainActor
struct SkippedDoseTests {

    private func setup() throws -> (ModelContext, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Бим", weightKg: 12)
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 21 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, medication)
    }

    @Test("Пропущенная доза остаётся в истории с автором")
    func skipIsRecorded() throws {
        let (context, medication) = try setup()
        let scheduled = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

        DoseScheduler.markSkipped(medication, scheduledAt: scheduled,
                                  by: "Наталья", context: context)

        let dose = try #require(medication.doses.first)
        #expect(dose.isSkipped)
        #expect(!dose.isGiven)
        #expect(dose.skippedBy == "Наталья")
    }

    @Test("Уже данную дозу пропущенной не отметить")
    func givenCannotBeSkipped() throws {
        let (context, medication) = try setup()
        let scheduled = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

        _ = DoseScheduler.markGiven(medication, scheduledAt: scheduled,
                                    by: "Аня", context: context)
        DoseScheduler.markSkipped(medication, scheduledAt: scheduled,
                                  by: "Наталья", context: context)

        let dose = try #require(medication.doses.first)
        #expect(dose.isGiven)
        #expect(!dose.isSkipped)
    }

    @Test("Снятие отметки убирает и пропуск")
    func unmarkClearsSkip() throws {
        let (context, medication) = try setup()
        let scheduled = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

        DoseScheduler.markSkipped(medication, scheduledAt: scheduled,
                                  by: "Наталья", context: context)
        DoseScheduler.unmark(medication, scheduledAt: scheduled, context: context)

        let dose = try #require(medication.doses.first)
        #expect(!dose.isSkipped)
        #expect(!dose.isGiven)
    }
}
