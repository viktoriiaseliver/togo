import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Togo

/// Стыки между потоками правок 30.09: каждое правило здесь было написано
/// в одном месте и не доходило до соседнего пути.
@Suite("Стыки 30.09")
@MainActor
struct SeamsTests {

    private let сейчас = Date(timeIntervalSince1970: 1_900_000_000)

    private func собака(_ context: ModelContext) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        return dog
    }

    // MARK: Снять отметку — то же право, что удалить

    @Test("Ухаживающий не снимает отметку старше суток повторным тапом")
    func старуюОтметкуНеСнять() throws {
        let context = ModelContext(Persistence.container())
        let dog = собака(context)
        let давно = сейчас.addingTimeInterval(-3 * 24 * 3600)
        let запись = LogEvent(kind: .meal, date: давно, authorName: "Мама")
        запись.dog = dog
        context.insert(запись)
        try context.save()

        let appState = AppState()
        appState.role = .caregiver
        let actions = DayPlanActions(context: context, appState: appState, settings: Settings(),
                                     dog: dog, день: давно, сейчас: сейчас,
                                     careUndo: .constant([:]))
        let item = DayPlanItem(id: "meal-1", time: давно, title: "Завтрак", kind: .meal, isDone: true)

        actions.uncomplete(item)

        #expect(запись.deletedAt == nil, "срок роли — 24 ч, а запись трёхдневная")
        // Без этой проверки тест прошёл бы и вхолостую — если бы запись
        // просто не нашлась.
        #expect(appState.undo?.message == "Отметка старше суток · снимет владелец или со-владелец")
    }

    @Test("«Отменить» на тосте своей отметки проходит и без права править")
    func откатТостаПроходит() throws {
        let context = ModelContext(Persistence.container())
        let dog = собака(context)
        try context.save()

        let appState = AppState()
        appState.role = .helper   // записывает бытовое, править не может
        let время = Date()
        let actions = DayPlanActions(context: context, appState: appState, settings: Settings(),
                                     dog: dog, день: время, сейчас: время,
                                     careUndo: .constant([:]))
        let item = DayPlanItem(id: "meal-1", time: время, title: "Завтрак", kind: .meal, isDone: false)

        actions.complete(item, givenAt: время)
        guard case .revertPlanItem(let id)? = appState.undo?.action else {
            Issue.record("тост отметки должен откатывать пункт")
            return
        }
        let откат = try #require(appState.забратьОткатПункта(id))
        откат()

        let записи = try context.fetch(FetchDescriptor<LogEvent>())
        #expect(!записи.isEmpty)
        #expect(записи.allSatisfy { $0.deletedAt != nil }, "только что сделанная отметка снимается всегда")
    }

    // MARK: Чужая «беру на себя»

    private func дозаНаСемь(_ context: ModelContext) -> (Dog, Medication, DoseRecord, DayPlanItem) {
        let dog = собака(context)
        let время = Calendar.current.startOfDay(for: сейчас).addingTimeInterval(7 * 3600)
        let medication = Medication(name: "Эутирокс", doseText: "1 таб", times: [7 * 60])
        medication.dog = dog
        context.insert(medication)
        let dose = DoseRecord(scheduledAt: время)
        dose.medication = medication
        context.insert(dose)
        let item = DayPlanItem(id: "dose-1", time: время, title: "Эутирокс", kind: .dose,
                               isDone: false, medication: medication)
        return (dog, medication, dose, item)
    }

    private func actions(_ context: ModelContext, _ dog: Dog, _ appState: AppState) -> DayPlanActions {
        DayPlanActions(context: context, appState: appState, settings: Settings(),
                       dog: dog, день: сейчас, сейчас: сейчас, careUndo: .constant([:]))
    }

    @Test("Действующая чужая бронь спрашивается: кто и до скольких")
    func чужаяБронь() throws {
        let context = ModelContext(Persistence.container())
        let (dog, _, dose, item) = дозаНаСемь(context)
        let appState = AppState.наСвоёмТелефоне()
        dose.claimedBy = appState.currentUserName + " и не я"
        dose.claimedAt = сейчас.addingTimeInterval(-10 * 60)

        let чужая = try #require(actions(context, dog, appState).claimedByOther(item, givenAt: сейчас))
        #expect(чужая.claimedBy == dose.claimedBy)
        #expect(чужая.until == сейчас.addingTimeInterval(-10 * 60 + DoseRecord.claimTTL))
        #expect(чужая.givenAt == сейчас, "после подтверждения пишется выбранный час")
    }

    @Test("Своя, протухшая бронь и данная доза не спрашиваются")
    func безВопроса() throws {
        let context = ModelContext(Persistence.container())
        let (dog, _, dose, item) = дозаНаСемь(context)
        let appState = AppState.наСвоёмТелефоне()
        let a = actions(context, dog, appState)

        dose.claimedBy = appState.currentUserName
        dose.claimedAt = сейчас.addingTimeInterval(-60)
        #expect(a.claimedByOther(item, givenAt: сейчас) == nil, "своя бронь")

        dose.claimedBy = appState.currentUserName + " и не я"
        dose.claimedAt = сейчас.addingTimeInterval(-DoseRecord.claimTTL - 60)
        #expect(a.claimedByOther(item, givenAt: сейчас) == nil, "бронь истекла")

        dose.claimedAt = сейчас.addingTimeInterval(-60)
        dose.givenAt = сейчас.addingTimeInterval(-30)
        #expect(a.claimedByOther(item, givenAt: сейчас) == nil, "доза уже дана")
    }

    // MARK: Siri и замок второй собаки

    private func двеСобаки() -> (Dog, Dog) {
        let стич = Dog(name: "Стич", weightKg: 4.7)
        стич.createdAt = Date(timeIntervalSince1970: 1_000)
        let багира = Dog(name: "Багира", weightKg: 12)
        багира.createdAt = Date(timeIntervalSince1970: 2_000)
        return (стич, багира)
    }

    @Test("Без Pro голос пишет в основную, а не в закрытую выбранную")
    func голосБезPro() {
        let (стич, багира) = двеСобаки()
        let собаки = [багира, стич]
        #expect(QuickLog.собака(из: собаки, выбранная: багира.id, pro: false, гость: false)?.id == стич.id)
        #expect(QuickLog.собака(из: собаки, выбранная: nil, pro: false, гость: false)?.id == стич.id,
                "без выбора — основная, а не первая в массиве")
        #expect(QuickLog.собака(из: собаки, выбранная: багира.id, pro: true, гость: false)?.id == багира.id)
        #expect(QuickLog.собака(из: собаки, выбранная: багира.id, pro: false, гость: true)?.id == багира.id,
                "гостя не закрываем — как на экранах")
    }

    // MARK: Срок правки не продлевается переносом времени

    @Test("Перенос записи на «сейчас» не продлевает срок ухаживающего")
    func переносНеПродлевает() {
        let appState = AppState()
        appState.role = .caregiver
        let запись = LogEvent(kind: .meal, date: сейчас.addingTimeInterval(-23 * 3600), authorName: "Мама")
        #expect(appState.canEdit(запись, at: сейчас))

        запись.закрепитьМоментЗаписи()
        запись.date = сейчас
        #expect(!appState.canEdit(запись, at: сейчас.addingTimeInterval(2 * 3600)),
                "окно считается от записи, а не от нового времени")
    }

    @Test("Момент записи по памяти не перетирается")
    func поПамятиНеТрогаем() {
        let запись = LogEvent(kind: .stool, date: сейчас.addingTimeInterval(-5 * 24 * 3600), authorName: "Мама")
        запись.enteredAt = сейчас
        запись.закрепитьМоментЗаписи()
        #expect(запись.enteredAt == сейчас)
    }

    // MARK: Чужая доза → напоминания

    @Test("Чужое «дано» рядом с нашей открытой отметкой снимает напоминания")
    func чужаяДанаяСнимает() throws {
        let context = ModelContext(Persistence.container())
        let (dog, medication, _, item) = дозаНаСемь(context)
        let чужая = DoseRecord(scheduledAt: item.time)
        чужая.givenAt = item.time
        чужая.medication = medication
        context.insert(чужая)
        try context.save()

        let до = Calendar.current.startOfDay(for: сейчас).addingTimeInterval(6 * 3600)
        let дозы = ReminderScheduler.plannedDoses(dog: dog, at: до)
        #expect(!дозы.contains { $0.at == item.time }, "доза уже дана на другом телефоне")
    }

    private final class Пойманное: @unchecked Sendable {
        var касается = false
    }

    @Test("Приём чужой дозы сохраняется так, что экран пересобирает напоминания")
    func приёмЧужойДозыВиденЭкрану() throws {
        let context = ModelContext(Persistence.container())
        let пойманное = Пойманное()
        let слушатель = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { note in
            if TodayScreen.касаетсяНапоминаний(note) { пойманное.касается = true }
        }
        defer { NotificationCenter.default.removeObserver(слушатель) }

        let payload = DosePayload(
            id: UUID(), medicationID: nil, medicationName: nil,
            scheduledAt: Date(), givenAt: Date(), givenBy: "Мама",
            skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
            cancelledAt: nil, cancelReason: nil, changedAt: Date()
        )
        SharedDiaryInbox.accept(payload, medication: nil, context: context)

        #expect(пойманное.касается, """
            чужая доза записалась мимо `ModelContext.didSave` или фильтр её \
            не узнал — отдельного сигнала больше нет, и напоминания останутся
            """)
    }

    // MARK: Коридор веса

    @Test("Коридор: пусто — нет коридора, одна граница и «от ≥ до» — нельзя")
    func коридор() {
        #expect(WeightCorridor.parse(low: "", high: " ") == .empty)
        #expect(WeightCorridor.parse(low: "4,0", high: "4.3") == .range(low: 4.0, high: 4.3))
        #expect(WeightCorridor.parse(low: "4", high: "") == .invalid(.oneEmpty))
        #expect(WeightCorridor.parse(low: "4,3", high: "4,3") == .invalid(.notAscending))
        #expect(WeightCorridor.parse(low: "0", high: "4") == .invalid(.notNumber))
        #expect(WeightCorridor.parse(low: "четыре", high: "5") == .invalid(.notNumber))
        #expect(WeightCorridor.parse(low: "", high: "").bounds != nil, "пусто — сохранить «без коридора»")
        #expect(WeightCorridor.parse(low: "4", high: "3").bounds == nil)
    }
}
