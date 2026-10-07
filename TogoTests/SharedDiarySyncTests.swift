import Testing
import Foundation
import CloudKit
import SwiftData
@testable import Togo

/// Обмен: куда уходит своё и что происходит со второй отправкой.
///
/// Слой, который до сих пор не был покрыт ничем, — и именно в нём
/// лежали все четыре звена неработающего общего дневника. Проверяется
/// **поведение**: доезжает ли отметка, находит ли доза препарат,
/// в чью зону ложится запись гостя. Про сам CloudKit эти тесты
/// не знают ничего и знать не могут — два телефона они не заменяют.
@Suite("Общий дневник · адресация зоны")
struct SharedZoneRoutingTests {

    @Test("Свой дневник живёт в личной базе")
    func ownerWritesToPrivate() {
        #expect(SharedZoneRouting.scope(owner: nil) == .private)
        #expect(SharedZoneRouting.zone(owner: nil).ownerName == CKCurrentUserDefaultName)
        #expect(SharedZoneRouting.zone(owner: nil).zoneName == SharedDiary.zoneName)
    }

    @Test("Отметка гостя уходит в зону владельца, а не в свою")
    func guestWritesToOwnersZone() {
        let zone = SharedZoneRouting.zone(owner: "_owner")

        #expect(zone.ownerName == "_owner",
                "с CKCurrentUserDefaultName запись легла бы в личную базу гостя — там её никто не читает")
        #expect(zone.zoneName == SharedDiary.zoneName)
        #expect(SharedZoneRouting.scope(owner: "_owner") == .shared,
                "своей копии этой зоны у гостя нет вовсе")
    }

    @Test("Запись гостя адресуется в чужую зону целиком")
    func guestRecordIDCarriesOwner() {
        let id = UUID()
        let recordID = SharedDiaryRecords.recordID(id, in: SharedZoneRouting.zone(owner: "_owner"))

        #expect(recordID.zoneID.ownerName == "_owner")
        #expect(recordID.recordName == id.uuidString)
    }

    @Test("Себя чужим владельцем не записываем")
    func ownSelfIsNotAGuest() {
        let stored = SharedZoneOwner.name
        defer { SharedZoneOwner.name = stored }

        SharedZoneOwner.name = CKCurrentUserDefaultName
        #expect(SharedZoneOwner.isGuest == false,
                "иначе свой же дневник уехал бы искать себя в общей базе")

        SharedZoneOwner.name = ""
        #expect(SharedZoneOwner.isGuest == false)

        SharedZoneOwner.name = "_mama"
        #expect(SharedZoneOwner.name == "_mama")
        #expect(SharedZoneOwner.isGuest)
    }
}

/// Приглашение принято — что после этого знает приложение.
@Suite("Общий дневник · приглашение")
@MainActor
struct ShareAcceptanceTests {

    @Test("Принятое приглашение запоминает владельца и поднимает обмен")
    func acceptanceRemembersOwner() async {
        let storedOwner = SharedZoneOwner.name
        let storedOn = SharedDiarySettings.isOn
        defer {
            SharedDiarySettings.isOn = storedOn
            SharedZoneOwner.name = storedOwner
        }

        SharedZoneOwner.reset()
        SharedDiarySettings.isOn = false

        var told = false
        let token = NotificationCenter.default.addObserver(
            forName: .familyShareAccepted, object: nil, queue: .main
        ) { _ in told = true }
        defer { NotificationCenter.default.removeObserver(token) }

        ShareAcceptance.accepted(ownerName: "_mama")

        #expect(SharedZoneOwner.name == "_mama",
                "без имени владельца гость пишет отметки в свою личную базу")
        #expect(SharedDiarySettings.isOn, "иначе обмен ждал бы, пока его включат руками")
        #expect(told, "движок обмена поднимается по этому сообщению, а не по перезапуску")
    }
}

/// Вторая отправка записи.
@Suite("Общий дневник · спор версий")
@MainActor
struct SharedDiaryOutboxTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func serverRecord(_ id: UUID, type: SharedDiary.RecordType = .event) -> CKRecord {
        CKRecord(recordType: type.rawValue,
                 recordID: SharedDiaryRecords.recordID(id, in: zone))
    }

    private func conflict(with server: CKRecord) -> Error {
        NSError(domain: CKErrorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [CKRecordChangedErrorServerRecordKey: server])
    }

    private func failure(_ code: CKError.Code) -> Error {
        NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [:])
    }

    @Test("Спор версий отправляется заново, а не теряется")
    func conflictIsRetried() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())

        let again = outbox.retries(after: [(id: server.recordID, error: conflict(with: server))])

        #expect(again == [server.recordID],
                "прежде здесь была строка в журнале и потерянная навсегда отметка")
        #expect(outbox.base(for: server.recordID) === server,
                "во второй раз идём с серверной версией — на ней стоит recordChangeTag")
    }

    @Test("Исчезнувшая на сервере запись уходит заново с чистого листа")
    func unknownItemIsResentFresh() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        outbox.remember(server)

        let again = outbox.retries(after: [(id: server.recordID, error: failure(.unknownItem))])

        #expect(again == [server.recordID])
        #expect(outbox.base(for: server.recordID) == nil, "старый тег указывает в пустоту")
    }

    @Test("Чего повторить не умеем — то и не повторяем")
    func otherFailuresAreNotRetried() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())

        #expect(outbox.retries(after: [(id: server.recordID, error: failure(.quotaExceeded))]).isEmpty)
        #expect(outbox.retries(after: [(id: server.recordID, error: failure(.networkFailure))]).isEmpty)
    }

    @Test("Пропавшая зона обнуляет все теги")
    func lostZoneForgetsEverything() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        outbox.remember(server)

        _ = outbox.retries(after: [(id: server.recordID, error: failure(.zoneNotFound))])

        #expect(outbox.base(for: server.recordID) == nil)
    }

    @Test("Подтверждённая сервером запись запоминается")
    func savedRecordsAreRemembered() {
        let outbox = SharedDiaryOutbox()
        let one = serverRecord(UUID())
        let two = serverRecord(UUID())

        outbox.remember([one, two])

        #expect(outbox.base(for: one.recordID) === one)
        #expect(outbox.base(for: two.recordID) === two)
    }
}

/// Сборка записи для отправки.
@Suite("Общий дневник · запись для отправки")
struct SharedDiaryRecordBuildTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func event(_ id: UUID, grams: Int?, deletedAt: Date? = nil,
                       deletedBy: String? = nil, changedAt: Date) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(), authorName: "Вика",
                     note: nil, outcome: nil, durationSeconds: nil, stoolForm: nil,
                     stoolFlags: [], grams: grams, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil, deletedAt: deletedAt,
                     deletedBy: deletedBy, changedAt: changedAt)
    }

    private func dose(_ id: UUID, givenAt: Date?, givenBy: String?,
                      medicationName: String? = nil, changedAt: Date) -> DosePayload {
        DosePayload(id: id, medicationID: nil, medicationName: medicationName,
                    scheduledAt: Date(), givenAt: givenAt, givenBy: givenBy,
                    skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
                    cancelledAt: nil, cancelReason: nil, changedAt: changedAt)
    }

    @Test("Без серверной версии собирается новая запись")
    func firstSendBuildsFreshRecord() {
        let id = UUID()
        let record = SharedDiaryRecords.record(event(id, grams: 65, changedAt: Date()),
                                               base: nil, in: zone)

        #expect(record.recordID.recordName == id.uuidString)
        #expect(record.recordID.zoneID == zone)
        #expect(record["grams"] as? Int == 65)
    }

    @Test("Вторая отправка идёт поверх серверной записи")
    func secondSendReusesServerRecord() {
        let id = UUID()
        let now = Date()

        // То, что уже лежит на сервере, — с его recordChangeTag.
        let server = SharedDiaryRecords.record(event(id, grams: 65, changedAt: now.addingTimeInterval(-60)),
                                               in: zone)
        // Наша правка: те же 20 граммов сверху.
        let resent = SharedDiaryRecords.record(event(id, grams: 85, changedAt: now),
                                               base: server, in: zone)

        #expect(resent === server,
                "новый CKRecord поехал бы без recordChangeTag и получил бы serverRecordChanged второй раз")
        #expect(resent["grams"] as? Int == 85, "наша правка свежее — она и едет")
    }

    @Test("Чужая отметка «дано» не затирается нашей отправкой")
    func resendKeepsForeignGiven() {
        let id = UUID()
        let now = Date()
        let given = now.addingTimeInterval(-600)

        // Сервер уже знает, что дозу дали, — это и был спор.
        let server = SharedDiaryRecords.record(
            dose(id, givenAt: given, givenBy: "Аня", changedAt: given), in: zone
        )
        // Мы шлём свою версию, в которой про «дано» ничего нет.
        let resent = SharedDiaryRecords.record(
            dose(id, givenAt: nil, givenBy: nil, changedAt: now), base: server, in: zone
        )

        #expect(resent["givenAt"] as? Date == given,
                "затереть чужое «дано» своей правкой — это вторая таблетка")
        #expect(resent["givenBy"] as? String == "Аня")
    }

    @Test("Серверная запись не от этой записи игнорируется")
    func foreignBaseIsIgnored() {
        let mine = UUID()
        let stranger = SharedDiaryRecords.record(event(UUID(), grams: 10, changedAt: Date()), in: zone)

        let record = SharedDiaryRecords.record(event(mine, grams: 65, changedAt: Date()),
                                               base: stranger, in: zone)

        #expect(record.recordID.recordName == mine.uuidString)
        #expect(record !== stranger)
    }

    @Test("Удаление переживает дорогу в CloudKit и обратно")
    func deletionSurvivesRoundTrip() {
        let id = UUID()
        let now = Date()
        let record = SharedDiaryRecords.record(
            event(id, grams: 65, deletedAt: now, deletedBy: "Вика", changedAt: now), in: zone
        )

        let back = SharedDiaryRecords.eventPayload(record)

        #expect(back?.deletedAt != nil, "без этого «Отменить» не доезжает до второго телефона")
        #expect(back?.deletedBy == "Вика")
    }

    @Test("Имя препарата переживает дорогу в CloudKit и обратно")
    func medicationNameSurvivesRoundTrip() {
        let record = SharedDiaryRecords.record(
            dose(UUID(), givenAt: Date(), givenBy: "Аня", medicationName: "Ветмедин", changedAt: Date()),
            in: zone
        )

        #expect(SharedDiaryRecords.dosePayload(record)?.medicationName == "Ветмедин")
    }
}

/// Чужая отметка дозы находит препарат.
/// Справочник клиник и поля прививки доезжают до второго человека.
///
/// **Зачем суита появилась.** Шагом 0 медицинского слоя (07.10.2026)
/// завелись `Clinic`, `CareTask.vaccineBatch`, `vaccineValidUntil`
/// и `Medication.prescriptionNumber`. Все они числились «про семью»
/// и **не ехали никуда**: в нагрузке обмена их не было, и сторож
/// паритета смотрел тогда одну модель из семнадцати.
///
/// > **Я записал «про семью» и этим ничего не отправил.**
///
/// Проверка идёт **значениями через запись CloudKit**, а не наличием
/// поля в структуре: поле может лежать в нагрузке и не попасть
/// в `CKRecord` — это следующий слой, и сторож имён его не видит.
@Suite("Общий дневник · справочник клиник и прививка")
@MainActor
struct SharedClinicSyncTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func телефон() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    @Test("Клиника доезжает целиком: имя, телефон, адрес и признак лаборатории")
    func клиникаДоезжает() throws {
        let (мой, _) = try телефон()
        let клиника = Clinic(name: "Vet Riviera", detail: "Ницца, Либерасьон",
                             isLab: false, phone: "+33 4 93 00 00 00")
        мой.insert(клиника)
        try мой.save()

        let запись = SharedDiaryRecords.record(клиника.payload, base: nil, in: zone)
        #expect(запись.recordType == SharedDiary.RecordType.clinic.rawValue)
        let приехало = try #require(SharedDiaryRecords.clinicPayload(запись), """
            запись клиники не разобралась обратно — значит поле лежит \
            в нагрузке и не попало в `CKRecord`. Ровно тот слой, \
            которого сторож имён не видит.
            """)

        let (её, _) = try телефон()
        SharedDiaryInbox.accept(приехало, context: её)

        let клиники = try её.fetch(FetchDescriptor<Clinic>())
        #expect(клиники.count == 1)
        let у_мамы = try #require(клиники.first)
        #expect(у_мамы.name == "Vet Riviera")
        #expect(у_мамы.phone == "+33 4 93 00 00 00", """
            название клиники без номера не помогает в тот час, когда \
            с собакой что-то не так, — телефон ездит вместе с именем \
            нарочно.
            """)
        #expect(у_мамы.detail == "Ницца, Либерасьон")
        #expect(у_мамы.isLab == false)
        #expect(у_мамы.id == клиника.id, "id сохраняется — иначе справочник раздвоится")
    }

    @Test("Безымянная клиника наружу не уезжает и внутрь не принимается")
    func безымяннаяНеЕдет() throws {
        let (мой, _) = try телефон()
        let пустая = Clinic(name: "   ")
        мой.insert(пустая)
        try мой.save()

        let запись = SharedDiaryRecords.record(пустая.payload, base: nil, in: zone)
        #expect(SharedDiaryRecords.clinicPayload(запись) == nil, """
            безымянная клиника разобралась как годная. Имя клиники — \
            ключ группировки «где делали»: запись без имени собрала бы \
            в одну группу всё, что имени не заполнило, и человек \
            увидел бы прививки неизвестно откуда, сложенные вместе.

            В показе пустота видна человеку. В ключе — не видна никому.
            """)

        let (её, _) = try телефон()
        let подделка = ClinicPayload(id: UUID(), name: "", detail: nil, isLab: false,
                                     phone: nil, createdAt: Date(), changedAt: Date())
        SharedDiaryInbox.accept(подделка, context: её)
        #expect(try её.fetch(FetchDescriptor<Clinic>()).isEmpty,
                "приём завёл безымянную клинику — второй вход того же дефекта")
    }

    @Test("Партия вакцины, срок и клиника доезжают вместе с прививкой")
    func прививкаДоезжаетЦеликом() throws {
        let (мой, собака) = try телефон()
        let клиника = Clinic(name: "Vet Riviera", phone: "+33 4 93 00 00 00")
        мой.insert(клиника)
        let прививка = CareTask(title: "Бешенство", detail: "ежегодно",
                                intervalDays: 365, category: .medical)
        прививка.vaccineBatch = "L3421-07"
        прививка.vaccineValidUntil = Date(timeIntervalSince1970: 1_790_000_000)
        прививка.clinic = клиника
        прививка.dog = собака
        мой.insert(прививка)
        try мой.save()

        let запись = SharedDiaryRecords.record(прививка.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.carePayload(запись))
        #expect(приехало.vaccineBatch == "L3421-07", """
            номер партии не доехал. Его спрашивают, когда у собаки \
            реакция или когда партию отзывают, — и спрашивают у того, \
            кто привёл собаку сегодня.
            """)
        #expect(приехало.vaccineValidUntil == прививка.vaccineValidUntil, """
            срок прививки не доехал — то самое поле, из-за которого \
            шаг 0 и начался.
            """)
        #expect(приехало.clinicName == "Vet Riviera", "имя клиники не доехало")
        #expect(приехало.clinicID == клиника.id, "id клиники не доехал")

        // У мамы справочник уже приехал — значит связь сошьётся по id.
        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(
            try #require(SharedDiaryRecords.clinicPayload(
                SharedDiaryRecords.record(клиника.payload, base: nil, in: zone))),
            context: её)
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let дела = try её.fetch(FetchDescriptor<CareTask>())
        let у_мамы = try #require(дела.first)
        #expect(у_мамы.vaccineBatch == "L3421-07")
        #expect(у_мамы.clinic?.name == "Vet Riviera", """
            прививка приехала без места, где её сделали. Это факт \
            без места — и у мамы не будет ответа на вопрос, куда \
            вести собаку в следующий раз.
            """)
    }

    /// **Главный тест суиты.** Промах по id — норма, а не сбой.
    ///
    /// Справочник второй человек мог завести своей рукой до включения
    /// обмена, и тогда та же «Vet Riviera» лежит у него с другим UUID.
    /// Тот же урок, что у висящих доз, оплаченный 23.09.
    @Test("Промах по id ловится именем: своя «Vet Riviera» с другим UUID")
    func промахПоIdЛовитсяИменем() throws {
        let (её, её_собака) = try телефон()
        let её_клиника = Clinic(name: "Vet Riviera", phone: "её номер")
        её.insert(её_клиника)
        try её.save()

        // Приехало дело ухода с ЧУЖИМ id клиники и тем же именем.
        var приехало = CarePayload(
            id: UUID(), dogID: её_собака.id, title: "Бешенство", detail: "",
            kind: CareKind.dated.rawValue, category: CareCategory.medical.rawValue,
            intervalDays: 365, scheduledDate: nil, remindDaysBefore: 14,
            lastDone: nil, streak: 0, seasonStartMonth: nil, seasonEndMonth: nil,
            snoozeCount: 0, clinicID: UUID(), clinicName: "Vet Riviera",
            vaccineBatch: "L3421-07", vaccineValidUntil: nil, changedAt: Date())
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let дело = try #require(try её.fetch(FetchDescriptor<CareTask>()).first)
        #expect(дело.clinic?.id == её_клиника.id, """
            промах по id оставил прививку без клиники, хотя та же \
            клиника лежит рядом под тем же именем. Промах по id здесь \
            норма: справочник могли завести до включения обмена.
            """)

        // А промах по ОБОИМ не заводит клинику: запись, рождённая
        // промахом, была бы дублем справочника.
        приехало.id = UUID()
        приехало.clinicID = UUID()
        приехало.clinicName = "Клиника, которой тут нет"
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        #expect(try её.fetch(FetchDescriptor<Clinic>()).count == 1, """
            промах по имени завёл новую клинику. Справочник без дублей — \
            правило дизайна, а запись, рождённая промахом, отличалась бы \
            от настоящей опечаткой.
            """)
    }

    @Test("Номер рецепта доезжает до того, кто пойдёт в аптеку")
    func номерРецептаДоезжает() throws {
        let (мой, собака) = try телефон()
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг", times: [420])
        схема.prescriptionNumber = "2026/0417"
        схема.dog = собака
        мой.insert(схема)
        try мой.save()

        let запись = SharedDiaryRecords.record(схема.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.medicationPayload(запись))
        #expect(приехало.prescriptionNumber == "2026/0417")

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        #expect(try её.fetch(FetchDescriptor<Medication>()).first?.prescriptionNumber == "2026/0417", """
            номер назначения не доехал. Его называют в аптеке, чтобы \
            продлить, и делает это тот, кто сегодня свободен, \
            а не владелец телефона.
            """)
    }

    /// Спор двух телефонов о записи справочника.
    @Test("При ничьей по времени выигрывает версия с телефоном, а не без")
    func спорПриНичьей() {
        let id = UUID()
        let когда = Date()
        let сТелефоном = ClinicPayload(id: id, name: "Vet Riviera", detail: nil,
                                       isLab: false, phone: "+33 4 93 00 00 00",
                                       createdAt: когда, changedAt: когда)
        let безТелефона = ClinicPayload(id: id, name: "Vet Riviera", detail: nil,
                                        isLab: false, phone: nil,
                                        createdAt: когда, changedAt: когда)

        #expect(SharedDiaryMerge.resolve(local: безТелефона, remote: сТелефоном) == сТелефоном, """
            ничья решилась в пользу версии без телефона. Часы двух \
            телефонов расходятся на секунды, и разумнее взять ту, \
            где данных больше, чем ту, где их стёрли.
            """)
        #expect(SharedDiaryMerge.resolve(local: сТелефоном, remote: безТелефона) == сТелефоном,
                "исход зависит от того, с какой стороны спросили")

        let позже = сТелефоном.changedAt.addingTimeInterval(60)
        var правкаПозже = безТелефона
        правкаПозже.phone = nil
        правкаПозже.changedAt = позже
        #expect(SharedDiaryMerge.resolve(local: сТелефоном, remote: правкаПозже) == правкаПозже, """
            правка, что позже, проиграла. Стирание номера — это тоже \
            правка: человек мог убрать номер, который сменился.
            """)
    }
}

@Suite("Общий дневник · доза находит препарат")
@MainActor
struct SharedDoseMedicationTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    @discardableResult
    private func medication(_ name: String, dog: Dog, context: ModelContext,
                            cancelled: Bool = false) -> Medication {
        let medication = Medication(name: name, doseText: "1 таб", times: [480])
        medication.dog = dog
        if cancelled { medication.cancelledAt = Date() }
        context.insert(medication)
        try? context.save()
        return medication
    }

    private func dose(medicationID: UUID?, medicationName: String?,
                      givenAt: Date? = nil, givenBy: String? = nil) -> DosePayload {
        DosePayload(id: UUID(), medicationID: medicationID, medicationName: medicationName,
                    scheduledAt: Date(), givenAt: givenAt, givenBy: givenBy,
                    skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
                    cancelledAt: nil, cancelReason: nil, changedAt: Date())
    }

    @Test("Незнакомый UUID со знакомым именем находит препарат")
    func unknownIDKnownNameFinds() throws {
        let (context, dog) = try setup()
        let mine = medication("Ветмедин", dog: dog, context: context)

        // У второго человека та же схема заведена своей рукой:
        // UUID другой, имя то же.
        let found = SharedDiaryInbox.medication(
            for: dose(medicationID: UUID(), medicationName: "Ветмедин"), context: context
        )

        #expect(found?.id == mine.id,
                "иначе доза висит ни на чём, второй видит её открытой — и даёт вторую таблетку")
    }

    @Test("Имя сверяется без регистра и лишних пробелов")
    func nameMatchIsForgiving() throws {
        let (context, dog) = try setup()
        let mine = medication("Ветмедин", dog: dog, context: context)

        for written in ["ветмедин", "  ВЕТМЕДИН ", "Ветмедин"] {
            let found = SharedDiaryInbox.medication(
                for: dose(medicationID: nil, medicationName: written), context: context
            )
            #expect(found?.id == mine.id, "«\(written)» — та же схема, набранная другой рукой")
        }
    }

    @Test("Своя схема сильнее имени")
    func idWinsOverName() throws {
        let (context, dog) = try setup()
        let vetmedin = medication("Ветмедин", dog: dog, context: context)
        medication("Фуросемид", dog: dog, context: context)

        let found = SharedDiaryInbox.medication(
            for: dose(medicationID: vetmedin.id, medicationName: "Фуросемид"), context: context
        )

        #expect(found?.id == vetmedin.id, "id точнее имени, когда он подошёл")
    }

    @Test("Из двух схем с одним именем берётся живая")
    func activeMedicationPreferred() throws {
        let (context, dog) = try setup()
        medication("Ветмедин", dog: dog, context: context, cancelled: true)
        let active = medication("Ветмедин", dog: dog, context: context)

        let found = SharedDiaryInbox.medication(
            for: dose(medicationID: nil, medicationName: "Ветмедин"), context: context
        )

        #expect(found?.id == active.id, "отметка приходит о той схеме, которую дают")
    }

    @Test("Незнакомое имя не притягивает чужую схему")
    func unknownNameFindsNothing() throws {
        let (context, dog) = try setup()
        medication("Ветмедин", dog: dog, context: context)

        #expect(SharedDiaryInbox.medication(
            for: dose(medicationID: nil, medicationName: "Фуросемид"), context: context) == nil)
        #expect(SharedDiaryInbox.medication(
            for: dose(medicationID: nil, medicationName: nil), context: context) == nil)
    }

    @Test("Чужое «дано» доезжает до препарата второго человека")
    func foreignGivenReachesTheDose() throws {
        let (context, dog) = try setup()
        let mine = medication("Ветмедин", dog: dog, context: context)
        let now = Date()

        // Мама отметила приём. У неё свой UUID схемы.
        let payload = dose(medicationID: UUID(), medicationName: "Ветмедин",
                           givenAt: now, givenBy: "Наталья")
        SharedDiaryInbox.accept(payload,
                                medication: SharedDiaryInbox.medication(for: payload, context: context),
                                context: context)

        let doses = (try? context.fetch(FetchDescriptor<DoseRecord>())) ?? []
        #expect(doses.count == 1)
        #expect(doses.first?.medication?.id == mine.id)
        #expect(doses.first?.isGiven == true, "муж обязан увидеть замок, а не открытую дозу")
        #expect(doses.first?.givenBy == "Наталья")
    }

    @Test("Доза, приехавшая раньше схемы, связывается со второй попытки")
    func lateMedicationIsLinked() throws {
        let (context, dog) = try setup()
        let now = Date()
        let id = UUID()

        // Схемы ещё нет — доза ложится ни на что.
        var payload = dose(medicationID: nil, medicationName: "Ветмедин")
        payload.id = id
        SharedDiaryInbox.accept(payload, medication: nil, context: context)
        #expect((try? context.fetch(FetchDescriptor<DoseRecord>()))?.first?.medication == nil)

        // Схему завели — следующая же правка связывает дозу с ней.
        let mine = medication("Ветмедин", dog: dog, context: context)
        var given = payload
        given.givenAt = now
        given.givenBy = "Наталья"
        given.changedAt = now.addingTimeInterval(60)
        SharedDiaryInbox.accept(given,
                                medication: SharedDiaryInbox.medication(for: given, context: context),
                                context: context)

        let doses = (try? context.fetch(FetchDescriptor<DoseRecord>())) ?? []
        #expect(doses.count == 1)
        #expect(doses.first?.medication?.id == mine.id)
    }
}

/// «Отменить» доезжает до второго телефона.
@Suite("Общий дневник · отмена записи")
@MainActor
struct SharedDiaryUndoTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    @Test("Отменённая запись исчезает у второго человека")
    func undoReachesTheOtherPhone() throws {
        let (mine, myDog) = try setup()
        let (theirs, theirDog) = try setup()
        let zone = SharedZoneRouting.zone(owner: nil)
        let now = Date()

        // Первый телефон: отметили еду, запись уехала.
        let event = LogEvent(kind: .meal, date: now, authorName: "Вика")
        event.dog = myDog
        event.grams = 65
        event.changedAt = now
        mine.insert(event)
        try mine.save()

        let sent = SharedDiaryRecords.record(event.payload, base: nil, in: zone)
        let arrived = try #require(SharedDiaryRecords.eventPayload(sent))
        SharedDiaryInbox.accept(arrived, dog: theirDog, context: theirs)
        #expect(Diary.active(theirDog.events).count == 1, "запись должна доехать до того, как её отменят")

        // «Отменить»: удаление мягкое, тем же способом, что и везде.
        event.deletedAt = now.addingTimeInterval(3)
        event.deletedBy = "Вика"
        event.changedAt = now.addingTimeInterval(3)
        try mine.save()

        // Уезжает поверх серверной версии — второй отправкой.
        let undone = SharedDiaryRecords.record(event.payload, base: sent, in: zone)
        let undoArrived = try #require(SharedDiaryRecords.eventPayload(undone))
        SharedDiaryInbox.accept(undoArrived, dog: theirDog, context: theirs)

        #expect(Diary.active(theirDog.events).isEmpty,
                "жёсткое удаление сюда не доезжало вовсе: обмен слушает только вставку и правку")
        #expect(theirDog.events.count == 1, "удаление оставляет след, а не стирает запись")
        #expect(theirDog.events.first?.deletedBy == "Вика")
    }
}
