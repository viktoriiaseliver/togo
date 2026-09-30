import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Togo

/// Лестница напоминаний о дозе: что планируется и на каком телефоне звенит.
///
/// До 30.09 напоминания на завтра появлялись только после открытия
/// приложения, отметка на другом телефоне не снимала t+30/t+60, а каждый
/// телефон звенел всеми ступенями, хотя обещано «т−10 дежурному».
@Suite("Напоминания о дозе")
@MainActor
struct DoseRemindersTests {

    private func собакаСоСхемой(_ context: ModelContext, минута: Int) -> (Dog, Medication) {
        let dog = Dog(name: "Стич", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let medication = Medication(name: "Эутирокс", doseText: "1 таб",
                                    times: [минута], fastingMinutes: 60)
        medication.dog = dog
        context.insert(medication)
        return (dog, medication)
    }

    @Test("Завтрашняя доза планируется, даже если её отметки ещё нет")
    func завтраПланируется() throws {
        let context = ModelContext(Persistence.container())
        let (dog, _) = собакаСоСхемой(context, минута: 7 * 60)
        try context.save()

        let полдень = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let дозы = ReminderScheduler.plannedDoses(dog: dog, at: полдень)

        #expect(дозы.count == 2, "сегодня и завтра по одной")
        let завтра = Calendar.current.date(byAdding: .day, value: 1, to: полдень) ?? полдень
        #expect(дозы.contains { Calendar.current.isDate($0.at, inSameDayAs: завтра) })
    }

    @Test("Данная и пропущенная доза не планируются — решение уже есть")
    func решениеСнимаетНапоминания() throws {
        let context = ModelContext(Persistence.container())
        let (dog, medication) = собакаСоСхемой(context, минута: 7 * 60)
        let сегодня = Calendar.current.startOfDay(for: Date())
        let завтра = Calendar.current.date(byAdding: .day, value: 1, to: сегодня) ?? сегодня

        let данная = DoseRecord(scheduledAt: сегодня.addingTimeInterval(7 * 3600))
        данная.givenAt = данная.scheduledAt
        данная.medication = medication
        context.insert(данная)
        let пропущенная = DoseRecord(scheduledAt: завтра.addingTimeInterval(7 * 3600))
        пропущенная.skippedAt = Date()
        пропущенная.medication = medication
        context.insert(пропущенная)
        try context.save()

        #expect(ReminderScheduler.plannedDoses(dog: dog, at: сегодня).isEmpty)
    }

    @Test("Не опознали, кто за телефоном, — звенят все ступени")
    func неизвестноВсем() {
        for ступень in DoseReminderStage.allCases {
            #expect(DoseReminderAudience.все.получает(ступень))
        }
    }

    @Test("Дежурный получает т−10, владелец не дежурный — только т+30 и т+60")
    func маршрутПоДежурству() {
        let тео = FamilyMember(name: "Тео", role: .caregiver)
        let виктория = FamilyMember(name: "Виктория", role: .owner)

        let дежурный = DoseReminderAudience.по(я: тео, дежурный: тео, даюДозу: true)
        #expect(DoseReminderStage.allCases.allSatisfy(дежурный.получает))

        let владелец = DoseReminderAudience.по(я: виктория, дежурный: тео, даюДозу: true)
        #expect(!владелец.получает(.before), "т−10 — дежурному")
        #expect(владелец.получает(.late))
        #expect(владелец.получает(.missed))
    }

    @Test("Дежурного нет — т−10 каждому, кто даёт дозу; наблюдателю ничего")
    func безДежурного() {
        let ухаживающий = FamilyMember(name: "Мама", role: .caregiver)
        let наблюдатель = FamilyMember(name: "Сосед", role: .observer)

        let даёт = DoseReminderAudience.по(я: ухаживающий, дежурный: nil, даюДозу: true)
        #expect(даёт.получает(.before))
        #expect(!даёт.получает(.late), "т+30 — дежурному и владельцам")
        #expect(даёт.получает(.missed))

        let смотрит = DoseReminderAudience.по(я: наблюдатель, дежурный: nil, даюДозу: false)
        #expect(!DoseReminderStage.allCases.contains(where: смотрит.получает))
    }
}

@Suite("День с собакой · вода")
@MainActor
struct DayOutWaterTests {

    @Test("Предложенная вода переживает перезапуск и забывается с концом дня")
    func водаПомнится() {
        let day = DayOut(startedAt: Date(), plannedHours: 5)
        let когда = Date(timeIntervalSince1970: 1_800_000_000)

        DayOutWater.offered(day, at: когда)
        #expect(DayOutWater.last(for: day) == когда)

        DayOutWater.forget(day)
        #expect(DayOutWater.last(for: day) == nil)
    }
}

/// «Отменить» на тосте отметки пункта плана — то же, что повторный тап
/// по кругу. До 30.09 тост убирал только строку в ленте, а доза
/// оставалась отмеченной: окно натощак живо, вторую дать нельзя.
@Suite("Режим дня · отмена отметки тостом")
@MainActor
struct PlanItemUndoTests {

    @Test("Отмена тостом снимает и запись, и отметку дозы")
    func отменаСнимаетДозу() throws {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let время = Calendar.current.startOfDay(for: Date()).addingTimeInterval(7 * 3600)
        let medication = Medication(name: "Эутирокс", doseText: "1 таб", times: [7 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()

        let appState = AppState.наСвоёмТелефоне()
        let actions = DayPlanActions(context: context, appState: appState, settings: Settings(),
                                     dog: dog, день: время, сейчас: время,
                                     careUndo: .constant([:]))
        let item = DayPlanItem(id: "dose-1", time: время, title: "Эутирокс", kind: .dose,
                               isDone: false, medication: medication)

        actions.complete(item, givenAt: время)

        guard case .revertPlanItem(let id)? = appState.undo?.action else {
            Issue.record("тост отметки пункта должен откатывать пункт, а не только запись")
            return
        }
        let откат = try #require(appState.забратьОткатПункта(id))
        откат()

        #expect(medication.doses.allSatisfy { !$0.isGiven }, "доза снова не дана")
        let записи = try context.fetch(FetchDescriptor<LogEvent>())
        #expect(записи.allSatisfy { $0.deletedAt != nil }, "строка в ленте снята")
    }
}
