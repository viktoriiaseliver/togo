import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Togo

/// Пачка 1 `docs/аудит-рефакторинга-2026-11-04.md`: запись, у которой
/// результат сохранения выбрасывался, теперь отдаёт его наружу —
/// и откатывает ВСЁ, что тронула, а не одно поле.
///
/// Отказ настоящий, а не подделанный флагом: хранилище открыто
/// с `allowsSave: false` (`НеЗаписывающееХранилище` в
/// `SilentFailureTests.swift`, там же проверка, что `save()` правда
/// бросает). Тест читает с диска только своё временное хранилище.
///
/// **Чего здесь нет:** экранные ветки (`StoolSheet`, `passDuty`,
/// `MergeConflictCard.merge`) — функции `private` у вида, шва к ним нет.
/// Их держит форма: хаптик успеха стоит после `guard persist`.
@Suite("Исход записи на отказе хранилища")
@MainActor
struct ИсходЗаписиНаОтказеTests {

    // MARK: Курс лечения

    /// Собака на лечении, одна живая схема и одна будущая доза.
    private static func курс(_ ctx: ModelContext) {
        let dog = Dog(name: "Стич", weightKg: 12)
        dog.isOnTreatment = true
        ctx.insert(dog)
        let схема = Medication(name: "Эутирокс", doseText: "1 таб", times: [480])
        схема.dog = dog
        ctx.insert(схема)
        let доза = DoseRecord(scheduledAt: Date().addingTimeInterval(86_400))
        доза.medication = схема
        ctx.insert(доза)
    }

    private static func собака(_ ctx: ModelContext) throws -> Dog {
        try #require(try ctx.fetch(FetchDescriptor<Dog>()).first)
    }

    @Test("Курс, который не записался, не закончен ни в одном поле")
    func завершениеНаОтказе() throws {
        let ctx = try НеЗаписывающееХранилище.контекст(наполнить: Self.курс)
        let dog = try Self.собака(ctx)
        let схема = try #require(dog.medications.first)
        #expect(схема.doses.count == 1, "наполнение не дошло — тест проверял бы пустоту")

        let записано = TreatmentCourse.finish(dog, by: "Вика", context: ctx)

        #expect(записано == false, "отказ хранилища обязан дойти до экрана")
        #expect(dog.isOnTreatment == true)
        #expect(схема.cancelledAt == nil, """
            схема осталась отменённой в памяти — до 04.11.2026 откат \
            возвращал только флаг, и отмена уезжала автосохранением
            """)
        #expect(схема.isPaused == false)
        #expect(схема.cancelledNote == nil)
        #expect(схема.doses.count == 1, """
            будущая доза удалена у курса, который не записался: лечение \
            пошло бы без приёмов. Удаление обязано идти вторым шагом
            """)
    }

    @Test("Курс, который записался, закончен и чист от будущих доз")
    func завершениеНаУдаче() throws {
        let ctx = try НеЗаписывающееХранилище.рабочийКонтекст()
        Self.курс(ctx)
        try ctx.save()
        let dog = try Self.собака(ctx)
        let схема = try #require(dog.medications.first)

        #expect(TreatmentCourse.finish(dog, by: "Вика", context: ctx))
        #expect(dog.isOnTreatment == false)
        #expect(схема.cancelledAt != nil)
        #expect(схема.isPaused)
        #expect(try ctx.fetch(FetchDescriptor<DoseRecord>()).isEmpty)
    }

    @Test("Возврат курса, который не записался, не возвращает схем")
    func возвратНаОтказе() throws {
        let ctx = try НеЗаписывающееХранилище.контекст { ctx in
            Self.курс(ctx)
            let dog = try #require(try ctx.fetch(FetchDescriptor<Dog>()).first)
            dog.isOnTreatment = false
            dog.medications.first?.отменить(заметка: "Курс завершён")
        }
        let dog = try Self.собака(ctx)
        let схема = try #require(dog.medications.first)
        #expect(схема.cancelledAt != nil, "наполнение не дошло")

        #expect(TreatmentCourse.resume(dog, context: ctx) == false)
        #expect(dog.isOnTreatment == false)
        #expect(схема.cancelledAt != nil)
        #expect(схема.isPaused)
        #expect(схема.cancelledNote == "Курс завершён")
    }

    // MARK: Приём из общего дневника

    private static func запись(_ id: UUID) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(), authorName: "Аня",
                     note: nil, outcome: nil, durationSeconds: nil, stoolForm: nil,
                     stoolFlags: [], grams: 65, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil, deletedAt: nil,
                     deletedBy: nil, changedAt: Date())
    }

    @Test("Приём, который не записался, — отказ, а не «принято»")
    func приёмНаОтказе() throws {
        let ctx = try НеЗаписывающееХранилище.контекст()

        let исход = SharedDiaryInbox.accept(Self.запись(UUID()), dog: nil, context: ctx)

        #expect(исход == .отказ, """
            до 04.11.2026 здесь был `false`, то же, что «принято», \
            и `FamilySync.apply` двигал время сверки — запись не приехала \
            бы больше никогда
            """)
        // Выборкой «записи не осталось» здесь НЕ проверяется, и это замер,
        // а не забывчивость: прогон 04.11.2026 на iOS 18.6 — после отказа
        // `save()` и `context.delete(event)` вставленная запись ВСЁ ЕЩЁ
        // в `ctx.fetch`. Что это значит для следующего удачного `save`,
        // не установлено — открытая находка в
        // `docs/аудит-рефакторинга-2026-11-04.md`, не предмет этого теста.
    }

    // MARK: Страница приёма `SharedDiaryInbox.партией`

    /// **Ось сменилась 05.11.2026, слиянием 286.** Прежде здесь стояли
    /// `ядроОткладываетОтказ` и `ядроНеОткладываетУдачу` — они звали
    /// `FamilySync.принять`, ядро стороны рефакторинга, которое
    /// откладывало ПОЗАПИСИ. Решение слияния взяло атомарность ночной
    /// стороны: единица приёма теперь страница, и `принять` удалена,
    /// чтобы не остаться мёртвым вторым путём.
    ///
    /// **Чего эти два теста НЕ проверяют, и это названо, а не обойдено:**
    /// самого` отложенного` (`FamilySync.отложенныйПриём`) они не видят —
    /// `apply` приватна и требует `CKSyncEngine`, которого в тест
    /// не поставить (та же причина, по которой в своё время и вынесли
    /// `принять`). Здесь держится КОНТРАКТ СТРАНИЦЫ, на который `apply`
    /// опирается: «не записалась — в главном контексте её нет вовсе»
    /// и «записалась — легла целиком». Откладывание по этому ответу
    /// стоит в `apply` и шва под себя не имеет.

    @Test("Незаписавшаяся страница не ложится в главный контекст ни одной записью")
    func страницаНаОтказеНеЛожится() throws {
        let ctx = try НеЗаписывающееХранилище.контекст()
        let зона = SharedDiaryRecords.zoneID()
        let пришло = [SharedDiaryRecords.record(Self.запись(UUID()), in: зона),
                      SharedDiaryRecords.record(Self.запись(UUID()), in: зона)]

        let страница = SharedDiaryInbox.партией(контейнер: ctx.container) { приём in
            for запись in пришло {
                guard let payload = SharedDiaryRecords.eventPayload(запись) else { continue }
                SharedDiaryInbox.accept(payload, dog: nil, context: приём)
            }
        }

        #expect(страница.записано == false, """
            страница на ЗАПЕРТОМ хранилище отчиталась «записано». \
            По этому ответу `FamilySync.apply` не отложил бы её, \
            не поставил бы `.failed` и сдвинул бы время сверки — \
            обе записи пропали бы молча, и повтора у них нет.
            """)
        #expect(try ctx.fetch(FetchDescriptor<LogEvent>()).isEmpty, """
            страница не записалась, а в главном контексте её записи ЕСТЬ. \
            Это «ложится частями» — ровно то, против чего страница и стоит: \
            половина чужого дня в базе и ни одного следа, что вторая \
            половина не доехала.
            """)
    }

    @Test("Записавшаяся страница ложится целиком")
    func страницаНаУдачеЛожится() throws {
        let ctx = try НеЗаписывающееХранилище.рабочийКонтекст()
        let зона = SharedDiaryRecords.zoneID()
        let пришло = [SharedDiaryRecords.record(Self.запись(UUID()), in: зона),
                      SharedDiaryRecords.record(Self.запись(UUID()), in: зона)]

        let страница = SharedDiaryInbox.партией(контейнер: ctx.container) { приём in
            for запись in пришло {
                guard let payload = SharedDiaryRecords.eventPayload(запись) else { continue }
                SharedDiaryInbox.accept(payload, dog: nil, context: приём)
            }
        }

        #expect(страница.записано, "страница на живом хранилище не записалась")
        #expect(try ctx.fetch(FetchDescriptor<LogEvent>()).count == 2, """
            страница отчиталась «записано», а записей в базе не две: \
            «записано» обязано значить «легло ВСЁ, что было на странице»
            """)
    }

    @Test("Приём на живом хранилище — «принято», и запись одна")
    func приёмНаУдаче() throws {
        let ctx = try НеЗаписывающееХранилище.рабочийКонтекст()
        let id = UUID()

        #expect(SharedDiaryInbox.accept(Self.запись(id), dog: nil, context: ctx) == .принято)
        #expect(SharedDiaryInbox.accept(Self.запись(id), dog: nil, context: ctx) != .отказ)
        #expect(try ctx.fetch(FetchDescriptor<LogEvent>()).count == 1,
                "повторный приём той же записи завёл дубликат")
    }
}
