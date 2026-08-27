import Testing
import Foundation
import SwiftData
@testable import Togo

/// «Здоровье» — слой-эпизод поверх обычного ухода: приходит с курсом
/// и уходит вместе с ним, ничего не унося из истории.
@Suite("Курс лечения")
@MainActor
struct TreatmentCourseTests {

    private func setup() throws -> (ModelContext, Dog, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 21 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, dog, medication)
    }

    @Test("Курс идёт — вкладка есть")
    func activeWhileOnTreatment() throws {
        let (_, dog, _) = try setup()
        #expect(TreatmentCourse.isActive(dog))
    }

    @Test("Курс завершён — вкладка прячется")
    func finishHidesTab() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)
        #expect(!TreatmentCourse.isActive(dog))
    }

    @Test("Препараты не удаляются, а помечаются отменёнными")
    func medicationsAreCancelledNotDeleted() throws {
        let (context, dog, medication) = try setup()
        let day = Date()
        TreatmentCourse.finish(dog, at: day, by: "Вика", context: context)

        #expect(dog.medications.count == 1)
        #expect(medication.cancelledAt == day)
        #expect(medication.isPaused)
        #expect(medication.cancelledNote?.isEmpty == false)
    }

    @Test("Отметки прошлых доз остаются, будущие уходят")
    func pastDosesSurvive() throws {
        let (context, dog, medication) = try setup()
        let now = Date()

        let given = DoseRecord(scheduledAt: now.addingTimeInterval(-3600))
        given.givenAt = now.addingTimeInterval(-3500)
        given.medication = medication
        context.insert(given)

        let future = DoseRecord(scheduledAt: now.addingTimeInterval(6 * 3600))
        future.medication = medication
        context.insert(future)
        try context.save()

        TreatmentCourse.finish(dog, at: now, by: "Вика", context: context)

        #expect(medication.doses.count == 1)
        #expect(medication.doses.first?.isGiven == true)
    }

    @Test("Пропущенная доза не считается мусором и остаётся")
    func skippedDoseSurvives() throws {
        let (context, dog, medication) = try setup()
        let now = Date()

        let skipped = DoseRecord(scheduledAt: now.addingTimeInterval(2 * 3600))
        skipped.skippedAt = now
        skipped.skippedBy = "Наталья"
        skipped.medication = medication
        context.insert(skipped)
        try context.save()

        TreatmentCourse.finish(dog, at: now, by: "Вика", context: context)
        #expect(medication.doses.count == 1)
        #expect(medication.doses.first?.isSkipped == true)
    }

    @Test("Курс можно вернуть — препараты оживают")
    func resumeRestoresMedications() throws {
        let (context, dog, medication) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)
        TreatmentCourse.resume(dog, context: context)

        #expect(TreatmentCourse.isActive(dog))
        #expect(medication.cancelledAt == nil)
        #expect(!medication.isPaused)
        #expect(medication.cancelledNote == nil)
    }

    @Test("Перед подтверждением названы препараты, которые уйдут")
    func farewellNamesMedications() throws {
        let (_, dog, _) = try setup()
        let text = TreatmentCourse.farewell(dog)
        #expect(text.contains("Апоквел"))
        #expect(text.contains("истории"))
    }

    @Test("Уже отменённый препарат в прощание не попадает")
    func farewellSkipsCancelled() throws {
        let (context, dog, medication) = try setup()
        medication.cancelledAt = Date()
        try context.save()

        #expect(!TreatmentCourse.farewell(dog).contains("Апоквел"))
        #expect(TreatmentCourse.activeMedications(dog).isEmpty)
    }

    @Test("После завершения курса новых доз на день не заводится")
    func noDosesAfterFinish() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)

        let created = DoseScheduler.ensureDoses(for: dog, on: Date(), context: context)
        #expect(created == 0)
    }

    @Test("Завершение не трогает вес и историю собаки")
    func historySurvives() throws {
        let (context, dog, _) = try setup()
        let weight = WeightEntry(kg: 12.4)
        weight.dog = dog
        context.insert(weight)
        let event = LogEvent(kind: .dose, date: Date(), authorName: "Вика")
        event.dog = dog
        context.insert(event)
        try context.save()

        TreatmentCourse.finish(dog, by: "Вика", context: context)

        #expect(dog.weights.count == 1)
        #expect(dog.events.contains { $0.kind == .dose })
    }

    @Test("Итог курса считает дозы и долю вовремя")
    func summaryCountsDoses() throws {
        let (context, dog, medication) = try setup()
        let now = Date()

        for (offset, lateness) in [(-4, 0.0), (-3, 900.0), (-2, 7200.0)] as [(Int, Double)] {
            let dose = DoseRecord(scheduledAt: now.addingTimeInterval(Double(offset) * 86400))
            dose.givenAt = dose.scheduledAt.addingTimeInterval(lateness)
            dose.medication = medication
            context.insert(dose)
        }
        try context.save()

        let summary = TreatmentCourse.summary(dog, now: now)
        #expect(summary.dosesGiven == 3)
        #expect(summary.dosesOnTime == 2, "два часа опоздания — уже не вовремя")
        #expect(summary.span >= 4 * 86400)
    }

    @Test("Без отметок процента не бывает")
    func noPercentWithoutDoses() throws {
        let (_, dog, _) = try setup()
        let summary = TreatmentCourse.summary(dog)
        #expect(summary.onTimeShare == nil, "иначе экран поздравит со стопроцентным нулём")
        #expect(summary.headline == "Курс закончен")
    }

    @Test("Длинный курс называется неделями")
    func headlineInWeeks() throws {
        let summary = TreatmentCourse.Summary(span: 42 * 86400, dosesGiven: 82,
                                              dosesOnTime: 77, skipped: 1)
        #expect(summary.headline == "6 недель позади")
    }

    @Test("Короткий курс называется днями")
    func headlineInDays() throws {
        let summary = TreatmentCourse.Summary(span: 5 * 86400, dosesGiven: 10,
                                              dosesOnTime: 10, skipped: 0)
        #expect(summary.headline == "5 дней позади")
    }

    @Test("Пропуски в итоге видны отдельно")
    func summaryCountsSkips() throws {
        let (context, dog, medication) = try setup()
        let dose = DoseRecord(scheduledAt: Date().addingTimeInterval(-3600))
        dose.skippedAt = Date()
        dose.medication = medication
        context.insert(dose)
        try context.save()

        #expect(TreatmentCourse.summary(dog).skipped == 1)
    }

    @Test("Контрольный приём заводится делом, а не фразой")
    func checkupBecomesTask() throws {
        let (context, dog, _) = try setup()
        let now = Date()

        let task = try #require(TreatmentCourse.scheduleCheckup(for: dog, from: now, context: context))
        #expect(task.kind == .dated)
        #expect(task.category == .medical)
        let expected = Calendar.current.date(byAdding: .day, value: 14, to: now)
        #expect(task.scheduledDate == expected)
        #expect(dog.careTasks.contains { $0.title == TreatmentCourse.checkupTitle })
    }

    @Test("Повторное нажатие не плодит второй приём")
    func checkupIsNotDuplicated() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.scheduleCheckup(for: dog, context: context)
        TreatmentCourse.scheduleCheckup(for: dog, context: context)

        #expect(dog.careTasks.filter { $0.title == TreatmentCourse.checkupTitle }.count == 1)
    }

    @Test("Приём переживает конец курса")
    func checkupSurvivesFinish() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.scheduleCheckup(for: dog, context: context)
        TreatmentCourse.finish(dog, by: "Вика", context: context)

        #expect(dog.careTasks.contains { $0.title == TreatmentCourse.checkupTitle })
    }
}
