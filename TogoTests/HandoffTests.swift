import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("Запас таблеток")
struct PillSupplyTests {

    @Test("Хватит ровно на столько дней, сколько доз влезает")
    func daysFromDoses() throws {
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 8, packSize: 60, perDay: 2)
        )
        #expect(supply.days == 4)
        #expect(supply.headline == "Таблеток на 4 дня")
    }

    @Test("Пустая пачка означает «не считаем», а не ноль дней")
    func noCountingWithoutTotal() {
        #expect(PillSupplyAdvisor.supply(remaining: 0, packSize: 0, perDay: 2) == nil,
                "навязывать учёт тому, кто покупает коробку в год, незачем")
    }

    @Test("Видно, на сколько дней курса не хватит")
    func shortfallIsNamed() throws {
        let now = Date()
        let ends = Calendar.current.date(byAdding: .day, value: 22, to: now)
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 8, packSize: 60, perDay: 2,
                                     courseEnds: ends, now: now)
        )
        let shortfall = try #require(supply.shortfallDays)
        #expect(shortfall == 18)
    }

    @Test("Предупреждаем за срок доставки, а не когда кончились")
    func warnsBeforeEmpty() throws {
        let three = try #require(PillSupplyAdvisor.supply(remaining: 6, packSize: 60, perDay: 2))
        let ten = try #require(PillSupplyAdvisor.supply(remaining: 20, packSize: 60, perDay: 2))

        #expect(PillSupplyAdvisor.needsWarning(three), "аптека везёт два-три дня")
        #expect(!PillSupplyAdvisor.needsWarning(ten))
    }

    @Test("Нехватки на курс достаточно для предупреждения")
    func shortfallWarnsEvenWithStock() throws {
        let ends = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 20, packSize: 60, perDay: 2, courseEnds: ends)
        )
        #expect(PillSupplyAdvisor.needsWarning(supply))
    }
}

@Suite("Итог смены")
struct ShiftTests {

    private func item(_ title: String, hour: Int, done: Bool, by: String? = nil) -> ShiftItem {
        let due = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour) * 3600)
        return ShiftItem(id: title, title: title, due: due, isDone: done, by: by)
    }

    private var shift: Shift {
        let day = Calendar.current.startOfDay(for: Date())
        return Shift(person: "Игорь",
                     from: day.addingTimeInterval(7 * 3600),
                     to: day.addingTimeInterval(19 * 3600))
    }

    @Test("Считается закрытое из всего")
    func headline() {
        let summary = ShiftSummary(shift: shift, items: [
            item("Утренняя еда", hour: 8, done: true, by: "Игорь"),
            item("Доза", hour: 9, done: true, by: "Игорь"),
            item("Прогулка", hour: 12, done: true, by: "Игорь"),
            item("Прогулка", hour: 15, done: true, by: "Игорь"),
            item("Прогулка", hour: 18, done: true, by: "Игорь"),
            item("Вечерняя еда", hour: 20, done: false),
        ])
        #expect(summary.headline == "5 из 6 закрыто")
        #expect(summary.open.count == 1)
    }

    @Test("Уведомление называет и сделанное, и открытое")
    func notificationNamesBoth() {
        let summary = ShiftSummary(shift: shift, items: [
            item("Доза", hour: 9, done: true, by: "Игорь"),
            item("Вечерняя еда", hour: 20, done: false),
        ])
        let text = summary.notification()
        #expect(text.lowercased().contains("доза"))
        #expect(text.contains("Открыто"))
        #expect(text.contains("вечерняя еда"))
    }

    @Test("Смена без записей не притворяется пустым успехом")
    func emptyShift() {
        let summary = ShiftSummary(shift: shift, items: [])
        #expect(summary.notification() == "Записей за смену нет.")
    }

    @Test("Смена знает, попадает ли час в неё")
    func coverage() {
        let day = Calendar.current.startOfDay(for: Date())
        #expect(shift.covers(day.addingTimeInterval(12 * 3600)))
        #expect(!shift.covers(day.addingTimeInterval(21 * 3600)))
    }
}

@Suite("Смена схемы после врача")
@MainActor
struct ScheduleChangeTests {

    private func setup() throws -> (ModelContext, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 20 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, medication)
    }

    private func change(_ startsFrom: ScheduleChange.StartsFrom) -> ScheduleChange {
        ScheduleChange(oldDoseText: "16 мг", oldTimes: [9 * 60, 20 * 60],
                       newDoseText: "16 мг", newTimes: [9 * 60],
                       startsFrom: startsFrom)
    }

    @Test("Расписание описывается словами, а не списком минут")
    func summaryInWords() {
        #expect(ScheduleChange.summary([9 * 60, 20 * 60]) == "дважды в день")
        #expect(ScheduleChange.summary([9 * 60]) == "один раз · утром")
        #expect(ScheduleChange.summary([20 * 60]) == "один раз · вечером")
    }

    @Test("Прошлые отметки не трогаются")
    func pastIsUntouched() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let given = DoseRecord(scheduledAt: now.addingTimeInterval(-5 * 3600))
        given.givenAt = now.addingTimeInterval(-5 * 3600)
        given.medication = medication
        context.insert(given)
        try context.save()

        ScheduleChangeApplier.apply(change(.tomorrowMorning), to: medication,
                                    now: now, context: context)

        #expect(medication.doses.contains { $0.isGiven },
                "история приёмов задним числом не должна становиться неправдой")
    }

    @Test("Лишняя будущая отметка удаляется и её называют заранее")
    func doomedDoseIsNamedAndRemoved() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let evening = DoseRecord(scheduledAt: calendar.startOfDay(for: now).addingTimeInterval(20 * 3600))
        evening.medication = medication
        context.insert(evening)
        try context.save()

        let plan = change(.tonight)
        #expect(plan.doomedDoses(medication.doses, now: now).count == 1)

        let removed = ScheduleChangeApplier.apply(plan, to: medication, now: now, context: context)
        #expect(removed == 1)
        #expect(medication.times == [9 * 60])
    }

    @Test("«С завтрашнего утра» оставляет сегодняшний вечер по старой схеме")
    func tomorrowKeepsTonight() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let evening = DoseRecord(scheduledAt: calendar.startOfDay(for: now).addingTimeInterval(20 * 3600))
        evening.medication = medication
        context.insert(evening)
        try context.save()

        let removed = ScheduleChangeApplier.apply(change(.tomorrowMorning), to: medication,
                                                  now: now, context: context)
        #expect(removed == 0, "вечером ещё старая схема — так и написано на экране")
        #expect(medication.doses.count == 1)
    }
}

@Suite("Сводка врачу")
@MainActor
struct VetSummaryTests {

    private func setup() throws -> (ModelContext, Dog, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 9)
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, dog, medication)
    }

    @Test("Доля вовремя считается по фактическим отметкам")
    func onTimeShare() throws {
        let (context, _, medication) = try setup()
        let now = Date()

        for (offset, lateness) in [(-5, 0.0), (-4, 600.0), (-3, 7200.0)] as [(Int, Double)] {
            let dose = DoseRecord(scheduledAt: now.addingTimeInterval(Double(offset) * 86400))
            dose.givenAt = dose.scheduledAt.addingTimeInterval(lateness)
            dose.medication = medication
            context.insert(dose)
        }
        try context.save()

        let summary = VetSummaryBuilder.build(
            events: [], doses: medication.doses, weights: [],
            from: now.addingTimeInterval(-30 * 86400), to: now
        )
        #expect(summary.dosesOnTime == 2)
        #expect(summary.dosesShifted == 1)
        let share = try #require(summary.onTimeShare)
        #expect(Int((share * 100).rounded()) == 67)
    }

    @Test("Без доз процента не бывает")
    func noShareWithoutDoses() {
        let summary = VetSummaryBuilder.build(events: [], doses: [], weights: [],
                                              from: Date().addingTimeInterval(-86400), to: Date())
        #expect(summary.onTimeShare == nil)
    }

    @Test("Инциденты группируются и называются одной строкой")
    func incidentsGrouped() throws {
        let (context, dog, _) = try setup()
        let now = Date()
        for _ in 0..<4 {
            let event = LogEvent(kind: .incident, date: now.addingTimeInterval(-3600), authorName: "Вика")
            event.incidentKind = .vomit
            event.dog = dog
            context.insert(event)
        }
        try context.save()

        let summary = VetSummaryBuilder.build(
            events: dog.events, doses: [], weights: [],
            from: now.addingTimeInterval(-86400), to: now
        )
        #expect(summary.incidentTotal == 4)
        #expect(summary.incidentDetail?.contains("все —") == true)
    }

    @Test("Удалённые записи в сводку не попадают")
    func deletedExcluded() throws {
        let (context, dog, _) = try setup()
        let now = Date()
        let event = LogEvent(kind: .incident, date: now.addingTimeInterval(-3600), authorName: "Вика")
        event.incidentKind = .vomit
        event.deletedAt = now
        event.dog = dog
        context.insert(event)
        try context.save()

        let summary = VetSummaryBuilder.build(events: dog.events, doses: [], weights: [],
                                              from: now.addingTimeInterval(-86400), to: now)
        #expect(summary.incidentTotal == 0)
    }

    @Test("Дельта веса считается от первой точки к последней")
    func weightDelta() {
        let now = Date()
        let summary = VetSummaryBuilder.build(
            events: [], doses: [],
            weights: [(now.addingTimeInterval(-30 * 86400), 9.2), (now, 8.8)],
            from: now.addingTimeInterval(-31 * 86400), to: now
        )
        #expect(summary.weightDelta?.contains("0,4") == true)
        #expect(summary.weightDelta?.hasPrefix("−") == true)
    }

    @Test("«Что изменилось» сравнивает с прошлым периодом словами")
    func deltaInWords() {
        let now = Date()
        func summary(incidents: Int) -> VetSummary {
            VetSummary(from: now.addingTimeInterval(-30 * 86400), to: now,
                       dosesOnTime: 0, dosesShifted: 0, dosesSkipped: 0,
                       incidents: incidents > 0 ? [(kind: .vomit, count: incidents)] : [],
                       weights: [])
        }
        let lines = VetSummaryBuilder.delta(current: summary(incidents: 2),
                                            previous: summary(incidents: 9))
        #expect(lines.contains { $0.contains("реже") && $0.contains("2") && $0.contains("9") })
    }
}
