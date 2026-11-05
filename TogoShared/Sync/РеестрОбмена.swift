import Foundation
import CloudKit
import SwiftData

// MARK: - Реестр типов обмена

/// Один список синхронизируемых типов вместо пяти копий.
///
/// # Что было до 05.11.2026
///
/// Двенадцать типов обмена жили пятью списками (пачка 4
/// `docs/аудит-рефакторинга-2026-11-04.md`):
///
/// ```
/// FamilySync.enqueueLocalChanges   цепочка `ctx.model(for:) as? X`
/// FamilySync.record(for:)          двенадцать выборок по id
/// FamilySync.принять               switch по типу записи
/// SharedDiarySeed.изменения        двенадцать `собрать(X.self…)`
/// SharedDiary.RecordType           имена на проводе
/// ```
///
/// И они **уже расходились**: ворота годности наружу стояли
/// в постановке и засеве, а в сборке записи — нет (закрыто 04.11).
/// Новый тип, добавленный в четыре списка из пяти, ехал бы «вперёд»
/// и не засевался, или засевался и не собирался — молча.
///
/// # Как теперь
///
/// ```
/// SharedDiary.RecordType            имена на проводе — ЕДИНСТВЕННЫЙ
///                                   перечень, как и был
/// RecordType.модель (ниже)          исчерпывающий switch: новый случай
///                                   без модели компилятор не пропустит
/// extension X: Обменный (ниже)      всё, что тип умеет в обмене, —
///                                   в одном месте
/// постановка · засев · сборка ·     выводятся из `РеестрОбмена.типы`
/// приём                             и протокола, своих списков нет
/// ```
///
/// # Почему соответствия — расширениями здесь, а не в телах классов
///
/// Заморозка схемы (`SchemaVersions.swift`) снимает тела `@Model`
/// в версионные копии. Требование протокола в теле класса уехало бы
/// в снимок, и снимок стал бы зависеть от слоя обмена. Протокол
/// не добавляет хранимых полей — он называет уже существующие
/// (`id`, `changedAt`) и перекладывает в уже существующий формат
/// (`SharedDiaryRecords`). Формат на проводе этим файлом не меняется:
/// ни имена типов записей, ни ключи полей, ни кодирование.
///
/// # Что оставлено явным, и почему
///
/// - **Порядок приёма** (клиника → собака → остальные) остаётся
///   в `FamilySync.принять`: это решение про ссылки между записями,
///   а не свойство одного типа.
/// - **Снятие напоминаний** при приёме схемы и дозы остаётся
///   в `FamilySync.принять` веткой по типу: у них разные предикаты
///   (`ждётОтметкиСУчётомСхемы` против `ждётОтметки`), и их держит
///   `СнятиеНапоминанийПодключеноTests` — ровно два входа в одном файле.
/// - **Разбор и `accept`** — по одному на тип, в соответствии ниже:
///   у них разные аргументы (собака по id, собака по записи, препарат
///   по id или имени, без собаки вовсе). Общая сигнатура
///   «запись CKRecord → исход приёма» прячет эту разницу за одной
///   строкой на тип, а не за обобщённым каркасом, который пришлось бы
///   читать, чтобы понять, какую собаку возьмёт доза.
@MainActor
protocol Обменный: PersistentModel {

    /// Устойчивый id — он же имя записи CloudKit
    /// (`SharedDiaryRecords.recordID`).
    ///
    /// Своё имя, а не `id`: у `PersistentModel` уже есть `id`
    /// из `Identifiable`, и требование с тем же именем другого типа
    /// читалось бы двусмысленно в обобщённом коде.
    var idОбмена: UUID { get }

    /// Время правки — его ставит постановка, и по нему спорят два
    /// телефона (`SharedDiaryMerge`).
    var changedAt: Date { get set }

    /// Годится ли запись в чужое хранилище.
    ///
    /// **Без умолчания нарочно.** Умолчание `true` в расширении
    /// протокола молча досталось бы новому типу, которому ворота нужны;
    /// здесь каждый тип называет свои ворота сам.
    var годитсяНаружу: Bool { get }

    /// Запись CloudKit из своего снимка, поверх серверной версии,
    /// если она есть. `nil` — собирать нечего (`SharedDiaryRecords`
    /// у собаки решает это сама).
    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord?

    /// Выборка по устойчивому id — конкретная у каждого типа.
    ///
    /// Не обобщённый `#Predicate { $0.idОбмена == id }`: предикат
    /// SwiftData строится по ключевому пути ХРАНИМОГО свойства,
    /// а путь к требованию протокола хранилище не переводит в запрос.
    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Self>

    /// Разобрать пришедшую запись и принять её в базу.
    /// `nil` — запись не разобралась (обязательного поля нет):
    /// отложить её нечего, повтор дал бы то же.
    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма?
}

extension SharedDiary.RecordType {

    /// Модель, которая ездит под этим именем.
    ///
    /// **Исчерпывающий `switch`, а не словарь** — в этом и смысл:
    /// новый случай `RecordType` без модели не соберётся. Словарь
    /// сказал бы `nil` во время работы, и тип молча не ездил бы.
    @MainActor
    var модель: any Обменный.Type {
        switch self {
        case .dog: Dog.self
        case .event: LogEvent.self
        case .care: CareTask.self
        case .medication: Medication.self
        case .dose: DoseRecord.self
        case .weight: WeightEntry.self
        case .clinic: Clinic.self
        case .document: DogDocument.self
        case .labResult: LabResult.self
        case .vetVisit: VetVisit.self
        case .diagnosis: Diagnosis.self
        case .prescription: Prescription.self
        }
    }
}

/// Двери наружу, выведенные из реестра.
///
/// Здесь, а не в `FamilySync`: движок обмена в тест не поставить
/// (нужны живой контейнер CloudKit и вошедший аккаунт), а решение
/// «что уедет» — обычная функция над хранилищем. Двери в `FamilySync`
/// и `SharedDiarySeed` зовут эти функции и своих списков не держат.
@MainActor
enum РеестрОбмена {

    /// Все типы, которые умеют ездить, — в порядке `RecordType.allCases`.
    static var типы: [any Обменный.Type] {
        SharedDiary.RecordType.allCases.map(\.модель)
    }

    /// Что поставить в отправку после сохранения.
    struct Отправка {
        var изменения: [CKSyncEngine.PendingRecordZoneChange] = []
        /// Сколько записей обмена задержали ворота годности.
        var задержано = 0
        /// Поставлена ли хоть одна отметка времени — тогда её надо
        /// сохранить прежде отправки.
        var отмечено = false
    }

    /// Дверь «сохранили → отправили»: из id сохранённых записей —
    /// правки к отправке, с отметкой времени на каждой.
    ///
    /// Отметка ставится здесь, а не на экранах: рука правит запись
    /// из полутора десятков мест, и «пометь изменённым» забыли бы
    /// ровно там, где это важнее всего.
    ///
    /// **Ворота — те же, что у засева и сборки записи**, одним
    /// свойством `годитсяНаружу`: запрет в одной двери вторая не знает.
    /// Задержанной записи отметку НЕ ставим — её не отправляют, и спор
    /// двух телефонов не должен видеть правки, которой не было.
    static func кОтправке(
        _ ids: [PersistentIdentifier],
        context: ModelContext,
        zone: CKRecordZone.ID,
        now: Date
    ) -> Отправка {
        var итог = Отправка()
        for id in ids {
            guard let модель = context.model(for: id) as? any Обменный else { continue }
            guard модель.годитсяНаружу else {
                итог.задержано += 1
                continue
            }
            модель.changedAt = now
            итог.отмечено = true
            итог.изменения.append(.saveRecord(
                SharedDiaryRecords.recordID(модель.idОбмена, in: zone)))
        }
        return итог
    }

    /// Дверь «засев»: всё, что уже лежит и годится наружу.
    ///
    /// `throws`, а не `try? … ?? []`: отказ выборки дал бы пустой
    /// список, засев считался бы сделанным, флаг ставился навсегда —
    /// и накопленное по этому типу не уехало бы никогда.
    static func всеГодные(
        context: ModelContext, zone: CKRecordZone.ID
    ) throws -> [CKSyncEngine.PendingRecordZoneChange] {
        func собрать<T: Обменный>(_ тип: T.Type) throws -> [CKSyncEngine.PendingRecordZoneChange] {
            try context.fetch(FetchDescriptor<T>())
                .filter(\.годитсяНаружу)
                .map { .saveRecord(SharedDiaryRecords.recordID($0.idОбмена, in: zone)) }
        }
        var собрано: [CKSyncEngine.PendingRecordZoneChange] = []
        for тип in типы {
            собрано += try собрать(тип)
        }
        return собрано
    }

    /// Найти запись обмена по устойчивому id — любого типа.
    ///
    /// Три исхода, а не `nil`: «не нашлось» здесь ожидаемо для
    /// одиннадцати типов из двенадцати, а отказ выборки — нет. Отказ
    /// одного типа не обрывает поиск: запись может найтись у другого.
    static func найти(_ id: UUID, context: ModelContext) -> Опознание<any Обменный> {
        func опознать<T: Обменный>(_ тип: T.Type) -> Опознание<any Обменный> {
            switch context.опознать(T.выборкаПоID(id)) {
            case .нашлась(let запись): .нашлась(запись)
            case .нет: .нет
            case .нечемОтвечать: .нечемОтвечать
            }
        }
        var отказала = false
        for тип in типы {
            switch опознать(тип) {
            case .нашлась(let запись): return .нашлась(запись)
            case .нет: continue
            case .нечемОтвечать: отказала = true
            }
        }
        return отказала ? .нечемОтвечать : .нет
    }

    /// Дверь «сборка записи»: последняя перед сервером.
    ///
    /// Ворота годности — здесь тоже: правка могла встать в очередь
    /// до того, как запись стала негодной (или в состоянии движка
    /// прошлой версии). Негодная отвечает `.нет` — движок снимет
    /// правку, и это верно: отправлять её нельзя и потом.
    static func запись(
        _ id: UUID, поверх base: CKRecord?, в zone: CKRecordZone.ID, context: ModelContext
    ) -> Опознание<CKRecord> {
        switch найти(id, context: context) {
        case .нашлась(let модель):
            guard модель.годитсяНаружу,
                  let запись = модель.записьОбмена(поверх: base, в: zone) else { return .нет }
            return .нашлась(запись)
        case .нет:
            return .нет
        case .нечемОтвечать:
            return .нечемОтвечать
        }
    }
}

// MARK: - Соответствия
//
// По одному на тип. Каждое называет: id, ворота наружу, сборку записи,
// выборку по id и приём. Даты в комментариях — когда тип начал ездить.

/// Профиль ездит с 23.09: без него приглашение вело в пустую комнату.
extension Dog: Обменный {
    var idОбмена: UUID { id }

    /// **Безымянная НЕ ОТПРАВЛЯЕТСЯ, и это не косметика.** Замер
    /// 08.10.2026 по выгрузке с телефона Виктории: шестнадцать собак,
    /// пятнадцать без клички, и пять из них несут одно и то же
    /// `changed` при трёх разных датах создания — их тронул пакетный
    /// проход `FeedingMigration`, а постановка поставила отметку
    /// и положила в отправку. Уехавшие живут в чужом хранилище,
    /// и там наше правило показа (`Dog.canBeShown`) не действует.
    ///
    /// Откуда берутся фантомы, не установлено: решающий замер — проход
    /// онбординга на стёртом симуляторе со счётом `Dog` после — не сделан.
    var годитсяНаружу: Bool { SharedDiaryOutgoing.sendable(self) }

    /// `SharedDiaryRecords.record` у собаки сам возвращает `nil`
    /// на безымянной — второй замок за воротами выше, и он не лишний:
    /// решение живёт в проверяемом слое, а не в двери.
    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Dog> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.dogPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(payload, context: context)
    }
}

extension LogEvent: Обменный {
    var idОбмена: UUID { id }

    /// Ловят отладочную запись прогрева схемы. Замер 08.10.2026
    /// по выгрузке с телефона Виктории: из 182 записей одна с датой
    /// `2001-01-01` и автором `ПРОГРЕВ СХЕМЫ`. Весь
    /// `CloudKitSchemaWarmup` под `#if DEBUG` — в продуктовой сборке
    /// она не создастся и **не удалится**. Без ворот она уехала бы
    /// маме первой записью истории.
    var годитсяНаружу: Bool { SharedDiaryOutgoing.sendable(self) }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<LogEvent> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    /// Собака берётся по id из самой записи. Раньше стояла первая
    /// местная — и у гостя с двумя собаками чужие отметки ложились
    /// на его собственную.
    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.eventPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(for: payload, context: context), context: context)
    }
}

extension CareTask: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<CareTask> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    /// Клиника сшивается внутри `accept`: там контекст есть
    /// по устройству, и промах по id там же падает на поиск по имени.
    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.carePayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

/// Снятие напоминаний по отменённой схеме — в `FamilySync.принять`,
/// не здесь (см. голову файла).
extension Medication: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Medication> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.medicationPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

/// Снятие напоминания по чужой отметке — в `FamilySync.принять`,
/// не здесь (см. голову файла).
extension DoseRecord: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<DoseRecord> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    /// Препарат ищется по id, а при промахе — по имени: у второго
    /// человека тот же препарат мог быть заведён с другим UUID.
    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.dosePayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, medication: SharedDiaryInbox.medication(for: payload, context: context),
            context: context)
    }
}

/// Взвешивания ездят с 07.10.2026: доза считается от веса, и расхождение
/// веса между двумя людьми даёт расхождение дозы.
extension WeightEntry: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<WeightEntry> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.weightPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

/// Справочник ездит с 07.10.2026: без него второй человек видел
/// прививку и не видел, где её сделали.
extension Clinic: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Clinic> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.clinicPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(payload, context: context)
    }
}

/// Документы ездят с 07.10.2026 — подписью, без скана: в клинике
/// спрашивают номер, на границе срок.
extension DogDocument: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<DogDocument> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.documentPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

/// Медкнижка ездит с 07.10.2026: без неё второй человек приходил
/// к врачу с пересказом.
extension LabResult: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<LabResult> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.labResultPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

extension VetVisit: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<VetVisit> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.vetVisitPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

extension Diagnosis: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Diagnosis> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.diagnosisPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}

extension Prescription: Обменный {
    var idОбмена: UUID { id }
    var годитсяНаружу: Bool { true }

    func записьОбмена(поверх base: CKRecord?, в zone: CKRecordZone.ID) -> CKRecord? {
        SharedDiaryRecords.record(payload, base: base, in: zone)
    }

    static func выборкаПоID(_ id: UUID) -> FetchDescriptor<Prescription> {
        FetchDescriptor(predicate: #Predicate { $0.id == id })
    }

    static func принятьЗапись(_ запись: CKRecord, context: ModelContext) -> ИсходПриёма? {
        guard let payload = SharedDiaryRecords.prescriptionPayload(запись) else { return nil }
        return SharedDiaryInbox.accept(
            payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: context),
            context: context)
    }
}
