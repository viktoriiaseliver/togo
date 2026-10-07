import Testing
import Foundation
import SwiftData
@testable import Togo

/// Уход и схемы лечения ездят в общем дневнике.
///
/// Без расписания «план дня» у гостя пуст: он видит ленту чужих отметок
/// и ни одного дела, которое надо сделать. Без схем у него приходят
/// приёмы без названия — человек знает, что дать таблетку надо,
/// и не знает какую.
@Suite("Уход и лечение в общем дневнике")
@MainActor
struct SharedCareAndMedicationTests {

    private func уход(_ название: String = "Когти",
                      изменено: Date = Date(), сделано: Date? = nil) -> CarePayload {
        CarePayload(
            id: UUID(), dogID: nil, title: название, detail: "",
            kind: CareKind.periodic.rawValue, category: CareCategory.grooming.rawValue,
            intervalDays: 30, scheduledDate: nil, remindDaysBefore: 14,
            lastDone: сделано, streak: 0, seasonStartMonth: nil,
            seasonEndMonth: nil, snoozeCount: 0, changedAt: изменено
        )
    }

    private func схема(_ название: String = "Эутирокс",
                       изменено: Date = Date()) -> MedicationPayload {
        MedicationPayload(
            id: UUID(), dogID: nil, name: название, doseText: "50 мкг",
            times: [9 * 60], fastingMinutes: 60, fastingBeforeMinutes: 60,
            minutesAfterMeal: 0, isPaused: false, prescriber: nil,
            cancelledAt: nil, cancelledNote: nil, changedAt: изменено
        )
    }

    // MARK: Уход

    @Test("Приехавшее дело ухода заводится и цепляется к собаке")
    func уходЗаводится() throws {
        let context = ModelContext(Persistence.container())
        let собака = Dog(name: "Стич", weightKg: 4.1)
        context.insert(собака)
        try context.save()

        var дело = уход("Капли от клещей")
        дело.dogID = собака.id
        SharedDiaryInbox.accept(дело, dog: SharedDiaryInbox.dog(forDogID: дело.dogID, context: context),
                                context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        #expect(дела.count == 1)
        #expect(дела.first?.title == "Капли от клещей")
        #expect(дела.first?.dog?.id == собака.id, "дело ухода досталось не той собаке")
    }

    @Test("Побеждает правка, что позже: дело ухода")
    func уходПозднийПобеждает() {
        let раньше = уход("Когти", изменено: Date())
        var позже = раньше
        позже.title = "Когти и уши"
        позже.changedAt = раньше.changedAt.addingTimeInterval(20)
        #expect(SharedDiaryMerge.resolve(local: раньше, remote: позже).title == "Когти и уши")
        #expect(SharedDiaryMerge.resolve(local: позже, remote: раньше).title == "Когти и уши")
    }

    /// При ничьей выигрывает тот, кто делал позже: `lastDone` это факт,
    /// а не мнение, и потерять его хуже, чем потерять правку названия.
    @Test("При ничьей по времени выигрывает более свежее «сделано»")
    func ничьяЗаСделанным() {
        let момент = Date()
        let давно = уход(изменено: момент, сделано: момент.addingTimeInterval(-86400))
        var недавно = давно
        недавно.lastDone = момент
        #expect(SharedDiaryMerge.resolve(local: давно, remote: недавно).lastDone == момент)
        #expect(SharedDiaryMerge.resolve(local: недавно, remote: давно).lastDone == момент)
    }

    @Test("Дело ухода переживает дорогу без потерь")
    func уходНеТеряетПолей() throws {
        var исходное = уход("Мытьё")
        исходное.detail = "шампунь без отдушки"
        исходное.scheduledDate = Date(timeIntervalSince1970: 1_700_000_000)
        исходное.lastDone = Date(timeIntervalSince1970: 1_690_000_000)
        исходное.streak = 5
        исходное.seasonStartMonth = 4
        исходное.seasonEndMonth = 10
        исходное.snoozeCount = 2
        исходное.dogID = UUID()

        let запись = SharedDiaryRecords.record(исходное, base: nil, in: SharedDiaryRecords.zoneID())
        #expect(try #require(SharedDiaryRecords.carePayload(запись)) == исходное)
    }

    // MARK: Лечение

    @Test("Приехавшая схема заводится")
    func схемаЗаводится() throws {
        let context = ModelContext(Persistence.container())
        SharedDiaryInbox.accept(схема(), dog: nil, context: context)

        let схемы = try context.fetch(FetchDescriptor<Medication>())
        #expect(схемы.count == 1)
        #expect(схемы.first?.name == "Эутирокс")
        #expect(схемы.first?.fastingBeforeMinutes == 60,
                "окно натощак ДО дозы не доехало — гость покормит перед таблеткой")
    }

    /// Единственное место, где у схемы правило не «позже». Цена ошибки
    /// здесь та же, что у дозы: не дать отменённую таблетку безопаснее,
    /// чем дать.
    @Test("Пауза и отмена при ничьей побеждают")
    func пеПаузаПобеждает() {
        let момент = Date()
        let идёт = схема(изменено: момент)
        var остановлена = идёт
        остановлена.isPaused = true
        остановлена.cancelledAt = момент

        let слева = SharedDiaryMerge.resolve(local: идёт, remote: остановлена)
        let справа = SharedDiaryMerge.resolve(local: остановлена, remote: идёт)
        #expect(слева.isPaused && справа.isPaused)
        #expect(слева.cancelledAt != nil && справа.cancelledAt != nil)
    }

    @Test("Схема переживает дорогу без потерь")
    func схемаНеТеряетПолей() throws {
        var исходная = схема("Ветмедин")
        исходная.dogID = UUID()
        исходная.minutesAfterMeal = 30
        исходная.isPaused = true
        исходная.prescriber = "Мари"
        исходная.cancelledAt = Date(timeIntervalSince1970: 1_700_000_000)
        исходная.cancelledNote = "курс окончен"

        let запись = SharedDiaryRecords.record(исходная, base: nil, in: SharedDiaryRecords.zoneID())
        #expect(try #require(SharedDiaryRecords.medicationPayload(запись)) == исходная)
    }

    @Test("Схема без имени не принимается")
    func безИмениНеПринимается() {
        let запись = SharedDiaryRecords.record(схема(), base: nil, in: SharedDiaryRecords.zoneID())
        запись["name"] = nil
        #expect(SharedDiaryRecords.medicationPayload(запись) == nil, """
            схема без названия — это приём, о котором человек не знает,
            что даёт.
            """)
    }

    // MARK: Доза, приехавшая раньше схемы

    @Test("Доза, приехавшая до схемы, дожидается её и связывается")
    func дозаДожидаетсяСхемы() throws {
        let context = ModelContext(Persistence.container())
        let будущая = схема("Эутирокс")

        // Сначала доза — схемы ещё нет ни у кого на этом телефоне.
        let отметка = DosePayload(
            id: UUID(), medicationID: будущая.id, medicationName: "Эутирокс",
            scheduledAt: Date(), givenAt: Date(), givenBy: "Мама",
            skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
            cancelledAt: nil, cancelReason: nil, changedAt: Date()
        )
        SharedDiaryInbox.accept(отметка, medication: nil, context: context)

        let ничья = try #require(try context.fetch(FetchDescriptor<DoseRecord>()).first)
        #expect(ничья.medication == nil)
        #expect(ничья.awaitedMedicationID == будущая.id, """
            доза не запомнила, чего ждёт. Связь `medication` — ссылка
            на объект, памяти у неё нет, и подобрать дозу потом нечем.
            """)

        // Теперь приезжает схема.
        SharedDiaryInbox.accept(будущая, dog: nil, context: context)

        let связанная = try #require(try context.fetch(FetchDescriptor<DoseRecord>()).first)
        #expect(связанная.medication?.id == будущая.id, """
            висящая ни на чём доза на экране не показывается вовсе:
            второй человек видит приём открытым и даёт вторую таблетку.
            """)
    }

    /// Первая редакция подбора цепляла к приехавшей схеме ВСЕ ничьи
    /// дозы подряд — условие в ней сравнивало схему саму с собой
    /// и было истинным всегда. При двух курсах это сложило бы приёмы
    /// разных препаратов в один.
    @Test("Чужая ничья доза к приехавшей схеме не цепляется")
    func чужаяДозаНеЦепляется() throws {
        let context = ModelContext(Persistence.container())
        let эутирокс = схема("Эутирокс")

        let чужая = DosePayload(
            id: UUID(), medicationID: UUID(), medicationName: "Ветмедин",
            scheduledAt: Date(), givenAt: nil, givenBy: nil,
            skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
            cancelledAt: nil, cancelReason: nil, changedAt: Date()
        )
        SharedDiaryInbox.accept(чужая, medication: nil, context: context)
        SharedDiaryInbox.accept(эутирокс, dog: nil, context: context)

        let доза = try #require(try context.fetch(FetchDescriptor<DoseRecord>()).first)
        #expect(доза.medication == nil, """
            доза от «Ветмедина» досталась «Эутироксу». Приёмы двух
            курсов сложились в один — ровно та ошибка, ради которой
            у дозы заведены свои правила.
            """)
    }

    @Test("Связь по имени работает, когда id разошлись")
    func связьПоИмени() throws {
        let context = ModelContext(Persistence.container())
        let схемаТут = схема("Эутирокс")

        // Доза уехала до 23.09: её `medicationID` указывает на схему,
        // заведённую второй рукой, и такого id здесь нет.
        let отметка = DosePayload(
            id: UUID(), medicationID: UUID(), medicationName: "эутирокс ",
            scheduledAt: Date(), givenAt: Date(), givenBy: "Мама",
            skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
            cancelledAt: nil, cancelReason: nil, changedAt: Date()
        )
        SharedDiaryInbox.accept(отметка, medication: nil, context: context)
        SharedDiaryInbox.accept(схемаТут, dog: nil, context: context)

        let доза = try #require(try context.fetch(FetchDescriptor<DoseRecord>()).first)
        #expect(доза.medication?.name == "Эутирокс",
                "имя сравнивается без регистра и лишних пробелов — как и при приёме дозы")
    }
}
