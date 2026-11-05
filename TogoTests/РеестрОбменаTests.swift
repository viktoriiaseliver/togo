import Testing
import Foundation
import CloudKit
import SwiftData
@testable import Togo

/// Реестр обмена: один список типов, одни ворота на всех дверях.
///
/// # Зачем этот набор и что он сменил
///
/// До 05.11.2026 список двенадцати типов обмена жил пятью копиями
/// (`FamilySync`: постановка, сборка записи, приём; `SharedDiarySeed`;
/// `SharedDiary.RecordType`), и сторожа держали их ТЕКСТОМ: строки
/// `as? Dog`, `as? LogEvent`, `guard SharedDiaryOutgoing.sendable(…)`,
/// `собрать(LogEvent.self`. Сведение в `РеестрОбмена` эти строки убрало
/// — сторожа покраснели бы на здоровом и улучшенном коде («прокси
/// наоборот»). Ось переведена на наблюдаемое:
///
/// ```
/// каждый тип реестра проходит постановку, засев, сборку и приём,
/// и приезжает СВОИМ типом                     → кругПоВсемТипам
/// постановка задерживает негодное             → постановкаЗадерживает
/// сборка записи не собирает негодное          → сборкаНеСобирает
/// засев не берёт отладочную запись            → засевНеБерётОтладочную
/// ```
///
/// Текстовые проверки остались только на то, что двери в `FamilySync`
/// и `SharedDiarySeed` идут через реестр (`МусорНеУезжаетTests`,
/// `ОтладочнаяЗаписьНеУезжаетTests`).
///
/// # Чего набор НЕ доказывает
///
/// Что записи доедут: движок CloudKit в тест не поставить. Здесь
/// принимается решение «что уедет и как разберётся», а не доставка.
@Suite("Реестр обмена · один список типов, одни ворота")
@MainActor
struct РеестрОбменаTests {

    private let zone = CKRecordZone.ID(zoneName: "проба", ownerName: "_хозяин")

    private func контекст() throws -> ModelContext {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func имена(_ изменения: [CKSyncEngine.PendingRecordZoneChange]) -> Set<String> {
        Set(изменения.compactMap { change -> String? in
            guard case .saveRecord(let id) = change else { return nil }
            return id.recordName
        })
    }

    /// Отладочная запись прогрева схемы — та же дата, что у живой находки.
    private var отладочная: LogEvent {
        LogEvent(kind: .note, date: Date(timeIntervalSinceReferenceDate: 0),
                 authorName: "прогрев")
    }

    // MARK: Реестр

    @Test("Каждый тип записи отдан своей модели, и модели не повторяются")
    func моделиРазличны() {
        let модели = SharedDiary.RecordType.allCases.map { ObjectIdentifier($0.модель) }
        #expect(SharedDiary.RecordType.allCases.count == 12, """
            типов записи \(SharedDiary.RecordType.allCases.count) при 12 \
            на 05.11.2026 — тип добавлен или убран; проверь, что это решение, \
            и перепиши число вместе с `кругПоВсемТипам`.
            """)
        #expect(Set(модели).count == модели.count, """
            две записи на проводе отданы одной модели — одна из моделей \
            не ездит, а чужие записи ложатся не в свой тип.
            """)
    }

    // MARK: Круг по всем типам

    /// По одной записи каждого типа: постановка, засев, сборка, приём
    /// на втором телефоне — и приезжает каждый своим типом.
    ///
    /// Это ось, которой держатся пять бывших копий: тип, выпавший
    /// из любой двери, выпадает здесь поимённо.
    @Test("Каждый тип реестра проходит все двери и приезжает своим типом")
    func кругПоВсемТипам() throws {
        let ctx = try контекст()

        let собака = Dog(name: "Стич", weightKg: 4.1)
        ctx.insert(собака)
        let событие = LogEvent(kind: .meal, authorName: "Вика")
        событие.dog = собака
        ctx.insert(событие)
        let дело = CareTask(title: "Взвесить", detail: "раз в неделю")
        дело.dog = собака
        ctx.insert(дело)
        let схема = Medication(name: "Ветмедин", doseText: "1 таб", times: [480])
        схема.dog = собака
        ctx.insert(схема)
        let доза = DoseRecord(scheduledAt: Date())
        доза.medication = схема
        ctx.insert(доза)
        let вес = WeightEntry(kg: 4.2)
        вес.dog = собака
        ctx.insert(вес)
        let клиника = Clinic(name: "Айболит")
        ctx.insert(клиника)
        let документ = DogDocument(title: "Паспорт")
        документ.dog = собака
        ctx.insert(документ)
        let анализ = LabResult(sampledOn: Date(), indicator: "Креатинин")
        анализ.dog = собака
        ctx.insert(анализ)
        let визит = VetVisit(date: Date(), doctor: "Иванова")
        визит.dog = собака
        ctx.insert(визит)
        let диагноз = Diagnosis(wording: "Гастрит")
        диагноз.dog = собака
        ctx.insert(диагноз)
        let рецепт = Prescription(number: "R-1", date: Date(), medicationName: "Ветмедин")
        рецепт.dog = собака
        ctx.insert(рецепт)
        try ctx.save()

        // Тип записи → id того, что должно уехать под этим именем.
        // Список здесь — нарочно руками, а не из реестра: проверяемое
        // не может быть собственным эталоном.
        let ждём: [(SharedDiary.RecordType, UUID)] = [
            (.dog, собака.id), (.event, событие.id), (.care, дело.id),
            (.medication, схема.id), (.dose, доза.id), (.weight, вес.id),
            (.clinic, клиника.id), (.document, документ.id),
            (.labResult, анализ.id), (.vetVisit, визит.id),
            (.diagnosis, диагноз.id), (.prescription, рецепт.id),
        ]
        #expect(ждём.count == SharedDiary.RecordType.allCases.count, """
            в круге \(ждём.count) типов при \(SharedDiary.RecordType.allCases.count) \
            в `RecordType` — новый тип не заведён в этот тест.
            """)
        let всеID = Set(ждём.map(\.1.uuidString))

        // Дверь «сохранили → отправили».
        let ids = [собака, событие, дело, схема, доза, вес, клиника, документ,
                   анализ, визит, диагноз, рецепт].map { ($0 as any PersistentModel).persistentModelID }
        let отправка = РеестрОбмена.кОтправке(ids, context: ctx, zone: zone, now: Date())
        let неПоставлены = всеID.subtracting(имена(отправка.изменения))
        #expect(неПоставлены.isEmpty, "постановка не берёт: \(названия(неПоставлены, ждём))")
        #expect(отправка.задержано == 0)

        // Дверь «засев».
        let засеяно = имена(try SharedDiarySeed.изменения(context: ctx, zone: zone))
        let неЗасеяны = всеID.subtracting(засеяно)
        #expect(неЗасеяны.isEmpty, "засев не берёт: \(названия(неЗасеяны, ждём))")

        // Дверь «сборка записи» — и имя на проводе своё.
        var записи: [CKRecord] = []
        for (тип, id) in ждём {
            guard case .нашлась(let запись) = РеестрОбмена.запись(
                id, поверх: nil, в: zone, context: ctx) else {
                Issue.record("сборка записи не собрала \(тип.rawValue)")
                continue
            }
            #expect(запись.recordType == тип.rawValue, """
                запись \(тип.rawValue) уезжает под именем «\(запись.recordType)» — \
                формат на проводе разошёлся с типом.
                """)
            записи.append(запись)
        }

        // Приём на втором телефоне: каждый тип ложится в СВОЮ модель.
        let второй = try контекст()
        // Дозы — второй пачкой: в одной пачке схема и доза равны по рангу
        // (`FamilySync.принять` упорядочивает только клинику и собаку),
        // а этот тест про реестр, не про порядок внутри ранга.
        let доз = SharedDiary.RecordType.dose.rawValue
        let отказавшие = FamilySync.принять(записи.filter { $0.recordType != доз },
                                            context: второй, дозаБольшеНеЖдёт: { _ in })
            + FamilySync.принять(записи.filter { $0.recordType == доз },
                                 context: второй, дозаБольшеНеЖдёт: { _ in })
        #expect(отказавшие.isEmpty, "приём отказал: \(отказавшие.map(\.recordType))")

        func есть<T: PersistentModel>(_ тип: T.Type) throws -> Int {
            try второй.fetchCount(FetchDescriptor<T>())
        }
        let приехало: [(String, Int)] = [
            ("Dog", try есть(Dog.self)), ("LogEvent", try есть(LogEvent.self)),
            ("CareTask", try есть(CareTask.self)), ("Medication", try есть(Medication.self)),
            ("DoseRecord", try есть(DoseRecord.self)), ("WeightEntry", try есть(WeightEntry.self)),
            ("Clinic", try есть(Clinic.self)), ("DogDocument", try есть(DogDocument.self)),
            ("LabResult", try есть(LabResult.self)), ("VetVisit", try есть(VetVisit.self)),
            ("Diagnosis", try есть(Diagnosis.self)), ("Prescription", try есть(Prescription.self)),
        ]
        let неТак = приехало.filter { $0.1 != 1 }.map { "\($0.0)=\($0.1)" }
        #expect(неТак.isEmpty, """
            на втором телефоне не по одной записи каждого типа: \
            \(неТак.joined(separator: " · ")). Запись легла в чужой тип \
            или не разобралась — приём по реестру разошёлся с форматом.
            """)
    }

    private func названия(_ ids: Set<String>, _ ждём: [(SharedDiary.RecordType, UUID)]) -> String {
        ждём.filter { ids.contains($0.1.uuidString) }.map(\.0.rawValue).joined(separator: " · ")
    }

    // MARK: Ворота на каждой двери

    @Test("Постановка задерживает безымянную собаку и отладочную запись, не трогая их время")
    func постановкаЗадерживает() throws {
        let ctx = try контекст()
        let живая = Dog(name: "Стич", weightKg: 4.1)
        let фантом = Dog(name: "", weightKg: 0)
        let настоящая = LogEvent(kind: .meal, authorName: "Вика")
        let прогрев = отладочная
        ctx.insert(живая); ctx.insert(фантом); ctx.insert(настоящая); ctx.insert(прогрев)
        try ctx.save()
        let былоФантом = фантом.changedAt
        let былоПрогрев = прогрев.changedAt

        let ids = ([живая, фантом, настоящая, прогрев] as [any PersistentModel])
            .map(\.persistentModelID)
        let потом = Date(timeIntervalSinceNow: 3600)
        let отправка = РеестрОбмена.кОтправке(ids, context: ctx, zone: zone, now: потом)

        #expect(имена(отправка.изменения) == [живая.id.uuidString, настоящая.id.uuidString], """
            постановка отправляет не ровно годное: \(имена(отправка.изменения).count) \
            записей при двух. Безымянная собака или запись 2001 года уехала бы маме.
            """)
        #expect(отправка.задержано == 2)
        #expect(фантом.changedAt == былоФантом && прогрев.changedAt == былоПрогрев, """
            задержанным поставлена отметка времени — правка, которой не было, \
            выиграла бы спор двух телефонов.
            """)
        #expect(живая.changedAt == потом && настоящая.changedAt == потом)
    }

    @Test("Сборка записи не собирает негодного, годное собирает")
    func сборкаНеСобирает() throws {
        let ctx = try контекст()
        let живая = Dog(name: "Стич", weightKg: 4.1)
        let фантом = Dog(name: "", weightKg: 0)
        let настоящая = LogEvent(kind: .meal, authorName: "Вика")
        let прогрев = отладочная
        ctx.insert(живая); ctx.insert(фантом); ctx.insert(настоящая); ctx.insert(прогрев)
        try ctx.save()

        func собрана(_ id: UUID) -> Bool {
            if case .нашлась = РеестрОбмена.запись(id, поверх: nil, в: zone, context: ctx) { return true }
            return false
        }
        #expect(!собрана(прогрев.id), "сборка записи собрала отладочную запись прогрева")
        #expect(!собрана(фантом.id), "сборка записи собрала безымянную собаку")
        #expect(собрана(настоящая.id) && собрана(живая.id), """
            сборка записи не собрала годное — проверка выше зелена \
            и тогда, когда не собирается ничего.
            """)
    }

    @Test("Засев не берёт отладочную запись прогрева, настоящую берёт")
    func засевНеБерётОтладочную() throws {
        let ctx = try контекст()
        let настоящая = LogEvent(kind: .meal, authorName: "Вика")
        let прогрев = отладочная
        ctx.insert(настоящая)
        ctx.insert(прогрев)
        try ctx.save()

        let засеяно = имена(try SharedDiarySeed.изменения(context: ctx, zone: zone))
        #expect(засеяно == [настоящая.id.uuidString], """
            засев взял не ровно настоящую запись (\(засеяно.count) при одной): \
            отладочная запись 2001 года уехала бы маме первой записью истории.
            """)
    }
}
