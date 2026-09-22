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
