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

        let разбор = outbox.retries(after: [(id: server.recordID, error: conflict(with: server))])

        #expect(разбор.повторим == [server.recordID],
                "прежде здесь была строка в журнале и потерянная навсегда отметка")
        #expect(разбор.потеряно.isEmpty, "спор версий — не потеря: запись уходит во второй раз")
        #expect(outbox.base(for: server.recordID) === server,
                "во второй раз идём с серверной версией — на ней стоит recordChangeTag")
    }

    @Test("Исчезнувшая на сервере запись уходит заново с чистого листа")
    func unknownItemIsResentFresh() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        outbox.remember(server)

        let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.unknownItem))])

        #expect(разбор.повторим == [server.recordID])
        #expect(разбор.потеряно.isEmpty)
        #expect(outbox.base(for: server.recordID) == nil, "старый тег указывает в пустоту")
    }

    /// **Этот тест заморозил дефект, и это видно по его прежнему имени.**
    ///
    /// Звался он «Чего повторить не умеем — то и не повторяем»
    /// и проверял `.isEmpty`. Утверждение было верным и неполным:
    /// «не повторяем» — половина ответа, вторая половина — «и никто
    /// об этом не узнает». Пока тест спрашивал только про повтор,
    /// он подтверждал как правильное то, что правка человека исчезает
    /// молча.
    ///
    /// > Тест, проверяющий половину развилки, делает вторую половину
    /// > решением — не потому, что кто-то так решил, а потому, что
    /// > спросить о ней стало нечем.
    /// **Прежняя редакция этого теста замораживала ВТОРУЮ половину
    /// того же дефекта** (замер 26.10.2026).
    ///
    /// Он звался «Чего повторить не умеем — то и называем потерянным»
    /// и требовал `повторим.isEmpty` — то есть утверждал как
    /// правильное, что запись не повторяется **ни разу**. Правка 14.10
    /// сняла молчание и на этом остановилась; тест закрепил остановку.
    ///
    /// > **Тест, написанный под половину починки, делает вторую
    /// > половину нормой.** Красного здесь не было бы никогда:
    /// > он требовал ровно того поведения, которое и есть дефект.
    ///
    /// `networkFailure` в прежнем списке — лучшая улика: обрыв сети
    /// проходит сам за секунды, а тест требовал потерять запись
    /// с первой попытки и называл это верным.
    @Test("Отказ, который может пройти сам, повторяется, а не теряется с первой попытки")
    func transientFailuresAreRetried() {
        for код in [CKError.Code.quotaExceeded, .networkFailure, .invalidArguments,
                    .serviceUnavailable, .requestRateLimited, .zoneBusy] {
            // Свой ящик и своя запись на каждый код: счётчик попыток
            // живёт по `recordID`, и общая запись копила бы отказы
            // через весь цикл — к шестому коду потолок был бы исчерпан,
            // а тест рассказал бы об этом как о свойстве кода.
            let outbox = SharedDiaryOutbox()
            let server = serverRecord(UUID())

            let разбор = outbox.retries(after: [(id: server.recordID, error: failure(код))])

            #expect(разбор.повторим == [server.recordID], """
                отказ \(код.rawValue) потерян с первой попытки. \
                Обрыв сети, таймаут и «сервер занят» проходят сами — \
                запись человека обязана уйти во второй раз
                """)
            #expect(разбор.потеряно.isEmpty, "первая попытка — ещё не потеря")
        }
    }

    /// Потолок — единственное, что отличает «повтор на все коды»
    /// от вечно растущей очереди на отказе, который не пройдёт никогда.
    @Test("У повтора есть потолок, и исчерпав его, запись названа потерянной с числом попыток")
    func retriesHaveVisibleCeiling() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        let потолок = SharedDiaryOutbox.потолокПовторов

        for заход in 1...потолок {
            let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.networkFailure))])
            #expect(разбор.повторим == [server.recordID],
                    "заход \(заход) из \(потолок) — потолок ещё не исчерпан")
            #expect(разбор.потеряно.isEmpty, "заход \(заход): сдались раньше потолка")
        }

        let последний = outbox.retries(after: [(id: server.recordID, error: failure(.networkFailure))])

        #expect(последний.повторим.isEmpty, "потолок исчерпан, а запись снова в очереди — очередь не кончится")
        #expect(последний.потеряно.count == 1)
        #expect(последний.потеряно.first?.объявлено == true, """
            потеря по исчерпанному потолку ОБЪЯВЛЕНА: довод есть \
            и он записан — повторяли \(потолок) раз
            """)
        #expect(последний.потеряно.first?.попыток == потолок, """
            число попыток — то единственное, чем потеря по потолку \
            отличается от решения не повторять (зона, попыток 0). \
            Без него оба исхода читаются одной потерей
            """)
        #expect(outbox.base(for: server.recordID) == nil,
                "сдались — тег держать незачем")
    }

    /// Контроль к потолку, и он обязан быть в этом же наборе: без него
    /// «потолок работает» неотличимо от «счётчик никогда не обнуляется»,
    /// то есть от медленной смерти обмена у человека, который им
    /// пользуется долго.
    @Test("Подтверждённая сервером запись обнуляет счёт попыток")
    func confirmedSaveResetsAttempts() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        let потолок = SharedDiaryOutbox.потолокПовторов

        for _ in 1...потолок {
            _ = outbox.retries(after: [(id: server.recordID, error: failure(.networkFailure))])
        }
        // Сеть вернулась, сервер принял запись.
        outbox.подтверждены([server])

        let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.networkFailure))])

        #expect(разбор.повторим == [server.recordID], """
            счёт попыток пережил успешную отправку — значит у записи, \
            которую правят часто, потолок исчерпается на ровном месте \
            и правка пропадёт при живой сети
            """)
        #expect(разбор.потеряно.isEmpty)
    }

    /// `invalidArguments` среди кодов выше стоит не для полноты:
    /// это ответ CloudKit на запись типа или поля, которых нет в схеме.
    /// Именно он был у семи типов из двенадцати до выкладки схемы
    /// 14.10.2026, и именно он уходил в `default: continue`.
    @Test("Отказ не от CloudKit повторяется: «не знаю, что это» — довод повторить")
    func nonCloudKitFailureIsRetried() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        let чужой = NSError(domain: "мой.домен", code: 42, userInfo: [:])

        let разбор = outbox.retries(after: [(id: server.recordID, error: чужой)])

        // Пятый путь, который виден только из `guard` на входе, а не
        // из `switch`: прежде `raw.domain == CKErrorDomain` отбрасывал
        // такой отказ тем же `continue`, потом — терял с первой попытки.
        #expect(разбор.повторим == [server.recordID], """
            про отказ не от CloudKit мы не знаем ВООБЩЕ ничего — \
            это довод повторить, а не сдаться
            """)
        #expect(разбор.потеряно.isEmpty)
    }

    /// И у него тоже есть потолок — иначе «повторяем незнакомое»
    /// становится вечной очередью на отказе файловой системы.
    @Test("Отказ не от CloudKit, исчерпав потолок, теряется БЕЗ выдуманного кода")
    func nonCloudKitFailureExhaustsCeilingWithoutCode() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        let чужой = NSError(domain: "мой.домен", code: 42, userInfo: [:])

        for _ in 1...SharedDiaryOutbox.потолокПовторов {
            _ = outbox.retries(after: [(id: server.recordID, error: чужой)])
        }
        let разбор = outbox.retries(after: [(id: server.recordID, error: чужой)])

        #expect(разбор.потеряно.count == 1)
        #expect(разбор.потеряно.first?.код == nil,
                "кода CKError у него нет, и врать про него нельзя даже после потолка")
        #expect(разбор.потеряно.first?.попыток == SharedDiaryOutbox.потолокПовторов)
    }

    /// **Прежняя редакция замораживала дефект** (переписана 29.10.2026).
    ///
    /// Звалась «Пропавшая зона обнуляет все теги и считается
    /// ОБЪЯВЛЕННОЙ потерей» и требовала `повторим.isEmpty` — на доводе
    /// «зону пересоздаёт движок». Движок зон сам не заводит: их кладут
    /// ему `.saveZone`, а таких строк в коде не было. Запись владельца,
    /// писавшего до первого приглашения, терялась с первой попытки.
    @Test("Пропавшая зона: запись повторяется, зона заказана, теги только этой зоны забыты")
    func lostZoneIsRecreatedAndRecordRetried() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        outbox.remember(server)

        let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.zoneNotFound))])

        #expect(outbox.base(for: server.recordID) == nil, "тег записи из пропавшей зоны указывает в пустоту")
        #expect(разбор.повторим == [server.recordID], """
            запись в пропавшую зону не повторена — она уйдёт, только \
            если её повторить ПОСЛЕ того, как зону заведут
            """)
        #expect(разбор.потеряно.isEmpty, "первая попытка — ещё не потеря")
        #expect(разбор.зоныСоздать == [zone], "зону заказывать некому, кроме вызывающего")
    }

    /// Предмет правки 29.10.2026: `forgetAll()` на отказе зоны обнулял
    /// счёт попыток ВСЕХ записей, и потолок не срабатывал никогда.
    @Test("Отказ зоны не возвращает другим записям запас попыток")
    func lostZoneKeepsOtherAttempts() {
        let outbox = SharedDiaryOutbox()
        let упрямая = serverRecord(UUID())
        let вЗоне = serverRecord(UUID())
        let потолок = SharedDiaryOutbox.потолокПовторов

        for _ in 1...потолок {
            _ = outbox.retries(after: [(id: упрямая.recordID, error: failure(.networkFailure))])
        }
        // Посреди повторов падает зона у соседней записи.
        _ = outbox.retries(after: [(id: вЗоне.recordID, error: failure(.zoneNotFound))])

        let разбор = outbox.retries(after: [(id: упрямая.recordID, error: failure(.networkFailure))])

        #expect(разбор.потеряно.first?.попыток == потолок, """
            отказ зоны соседней записи вернул упрямой полный запас \
            попыток — потолок не срабатывает, и запись, которая не уйдёт \
            никогда, крутится в очереди вечно
            """)
        #expect(разбор.повторим.isEmpty)
    }

    /// Контроль к счёту: тот же потолок у самой записи в пропавшую
    /// зону — иначе «зону заказали» превращается в вечный круг, если
    /// зона не заведётся.
    @Test("У записи в пропавшую зону тот же потолок повторов")
    func lostZoneRetriesHaveCeiling() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())

        for _ in 1...SharedDiaryOutbox.потолокПовторов {
            _ = outbox.retries(after: [(id: server.recordID, error: failure(.zoneNotFound))])
        }
        let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.zoneNotFound))])

        #expect(разбор.повторим.isEmpty, "потолок исчерпан, а запись снова в очереди")
        #expect(разбор.потеряно.first?.попыток == SharedDiaryOutbox.потолокПовторов)
    }

    /// Человек сам стёр данные приложения в iCloud — это решение,
    /// и зону за его спиной не возвращаем.
    @Test("Удалённая человеком зона — объявленная потеря, и зону не заказываем")
    func userDeletedZoneIsDeclaredLoss() {
        let outbox = SharedDiaryOutbox()
        let server = serverRecord(UUID())
        outbox.remember(server)

        let разбор = outbox.retries(after: [(id: server.recordID, error: failure(.userDeletedZone))])

        #expect(outbox.base(for: server.recordID) == nil)
        #expect(разбор.повторим.isEmpty)
        #expect(разбор.зоныСоздать.isEmpty, "зону, которую стёр человек, мы не возвращаем")
        #expect(разбор.потеряно.first?.объявлено == true, """
            решение с доводом и дефект без довода помечены одинаково — \
            значит в журнале их не различить, а различие и есть \
            единственный способ найти второе
            """)
        #expect(разбор.потеряно.first?.попыток == 0)
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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

/// Семнадцать полей, которые числились «про семью» и не ехали.
///
/// **Найдены 07.10.2026 обобщённым сторожем, не глазом.** Пока он
/// смотрел одну модель из семнадцати, девять полей ленты и восемь
/// полей схемы лечения числились семейными и в нагрузке отсутствовали.
///
/// Два самых дорогих названы в тестах прямо:
///
/// ```
/// Medication.unitRaw     «0,5» без единицы не значит ничего
/// LogEvent.askSignalRaw  «как попросил» — заглавная строка продукта
/// ```
@Suite("Общий дневник · семнадцать полей, которые не ехали")
@MainActor
struct SharedLostFieldsTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func телефон() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    /// **Главный тест файла.** Единица дозы доезжает.
    @Test("Единица дозы доезжает: «0,5» без неё — три разные дозы")
    func единицаДозыДоезжает() throws {
        let (мой, собака) = try телефон()
        let схема = Medication(name: "Lévothyrox", doseText: "0,5", times: [420])
        схема.unitRaw = MedUnit.ml.rawValue
        схема.canGiveOutside = true
        схема.expiry = Date(timeIntervalSince1970: 1_800_000_000)
        схема.openedAt = Date(timeIntervalSince1970: 1_790_000_000)
        схема.shelfAfterOpenDays = 28
        схема.remindBeforeExpiry = true
        схема.courseEnd = Date(timeIntervalSince1970: 1_795_000_000)
        схема.doseSlotsData = [DoseSlot(minuteOfDay: 420, quantity: 0.5)]
        схема.dog = собака
        мой.insert(схема)
        try мой.save()

        let запись = SharedDiaryRecords.record(схема.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.medicationPayload(запись))

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        let у_мамы = try #require(try её.fetch(FetchDescriptor<Medication>()).first)

        #expect(у_мамы.unitRaw == MedUnit.ml.rawValue, """
            единица дозы не доехала. «0,5» не значит ничего: половина \
            таблетки, половина миллилитра и половина капли — три разные \
            дозы. Это не путаница в дневнике, а передозировка.

            Архив это поле возил правильно, а обмен нет: два пути для \
            одних данных расходятся молча.
            """)
        #expect(у_мамы.canGiveOutside == true, """
            «можно дать на улице» не доехало. Это ОТВЕТ ЧЕЛОВЕКА, \
            а не наш вывод, и второй человек, собравшийся на прогулку \
            с каплями в глаз, обязан видеть тот же ответ.
            """)
        #expect(у_мамы.expiry == схема.expiry, "срок годности не доехал")
        #expect(у_мамы.openedAt == схема.openedAt, "дата вскрытия не доехала")
        #expect(у_мамы.shelfAfterOpenDays == 28, """
            срок после вскрытия не доехал. «Годен до» и «вскрыт, дальше \
            N дней» — ДВА разных срока, и у человека с открытым флаконом \
            капель подмена одного другим измеряется дозой.
            """)
        #expect(у_мамы.remindBeforeExpiry == true)
        #expect(у_мамы.courseEnd == схема.courseEnd, "конец курса не доехал")
        #expect(у_мамы.doseSlotsData.count == 1, """
            слоты дозы не доехали — схема «дважды в день» у мамы \
            не знает, сколько именно в каждый приём.
            """)
        #expect(у_мамы.doseSlotsData.first?.quantity == 0.5)
    }

    /// Запас таблеток не едет — и это решение, а не пропуск.
    @Test("Запас таблеток не едет: у мамы своя упаковка")
    func запасНеЕдет() throws {
        let (мой, собака) = try телефон()
        let схема = Medication(name: "Ветмедин", doseText: "1 таб", times: [480])
        схема.stockLeft = 40
        схема.stockTotal = 60
        схема.dog = собака
        мой.insert(схема)
        try мой.save()

        let запись = SharedDiaryRecords.record(схема.payload, base: nil, in: zone)
        let (её, её_собака) = try телефон()
        let у_неё = Medication(name: "Ветмедин", doseText: "1 таб", times: [480])
        у_неё.stockLeft = 12
        у_неё.dog = её_собака
        её.insert(у_неё)
        try её.save()

        SharedDiaryInbox.accept(try #require(SharedDiaryRecords.medicationPayload(запись)),
                                dog: её_собака, context: её)

        #expect(try её.fetch(FetchDescriptor<Medication>()).contains { $0.stockLeft == 12 }, """
            чужой запас перезаписал местный. Запас — про КОРОБКУ, \
            которая лежит у кого-то дома: у мамы своя упаковка, \
            и сложить два запаса в одно число значило бы сказать \
            обоим неправду.
            """)
    }

    /// **Второй главный тест.** «Как попросил» доезжает.
    @Test("«Как попросил» доезжает — иначе второй видит «просится» без ответа")
    func какПопросилДоезжает() throws {
        let (мой, собака) = try телефон()
        let запись_ленты = LogEvent(kind: .outing, date: Date(), authorName: "Виктория")
        запись_ленты.askSignalRaw = AskSignal.scratchedDoor.rawValue
        запись_ленты.isDayOnly = true
        запись_ленты.enteredAt = Date(timeIntervalSince1970: 1_790_000_500)
        запись_ленты.editedBy = "Виктория"
        запись_ленты.originRaw = "виджет"
        запись_ленты.reactionTriggerRaw = "собака"
        запись_ленты.reactionDistanceRaw = "близко"
        запись_ленты.toldFamily = true
        запись_ленты.trainingSessionID = UUID()
        запись_ленты.dog = собака
        мой.insert(запись_ленты)
        try мой.save()

        let запись = SharedDiaryRecords.record(запись_ленты.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.eventPayload(запись))

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        let у_мамы = try #require(try её.fetch(FetchDescriptor<LogEvent>()).first)

        #expect(у_мамы.askSignalRaw == AskSignal.scratchedDoor.rawValue, """
            «как попросил» не доехало. Это заглавная строка продукта — \
            та самая, что стоит в описании App Store: второй человек \
            видел «просится» и НЕ видел, чем именно — скулил, тёрся, \
            стоял у двери. То есть ровно то, ради чего дневник ведут \
            вдвоём.
            """)
        #expect(у_мамы.isDayOnly == true, """
            оговорка «часа не помню» не доехала, и без неё число лжёт: \
            `WalkRhythm` отбрасывает такие записи, считая обычное время \
            выхода. Приехав без флага, запись попадёт в счёт как точная, \
            и «обычно выходите в 7:15» соберётся из догадок.
            """)
        #expect(у_мамы.enteredAt == запись_ленты.enteredAt, """
            время ВВОДА не доехало. Разница между ним и временем \
            события — это и есть ответ на «вспомнил или записал сразу».
            """)
        #expect(у_мамы.editedBy == "Виктория", "кто правил — не доехало")
        #expect(у_мамы.originRaw == "виджет", "откуда запись — не доехало")
        #expect(у_мамы.reactionTriggerRaw == "собака", "повод реакции не доехал")
        #expect(у_мамы.reactionDistanceRaw == "близко", "расстояние реакции не доехало")
        #expect(у_мамы.toldFamily == true, "«сказали семье» не доехало")
        #expect(у_мамы.trainingSessionID == запись_ленты.trainingSessionID,
                "связь с занятием не доехала")
    }

    /// Запись от прежней версии не стирает то, чего не знает.
    ///
    /// **Это главное про опциональность в нагрузке.** У телефона
    /// со старой сборкой этих полей в записи нет вовсе. Прочитай
    /// отсутствие как «нет, не только день» — и правка оттуда стёрла бы
    /// оговорку «часа не помню» у того, кто её поставил.
    ///
    /// > **Отсутствие поля и ответ «нет» — разные вещи, а `as? Bool`
    /// > сводит их в одно.**
    @Test("Правка от прежней версии не стирает «как попросил» и «часа не помню»")
    func прежняяВерсияНеСтирает() throws {
        let (её, её_собака) = try телефон()
        let id = UUID()

        // Своя запись: оговорка и сигнал заполнены.
        let своя = LogEvent(kind: .outing, date: Date(), authorName: "Мама")
        своя.id = id
        своя.askSignalRaw = AskSignal.scratchedDoor.rawValue
        своя.isDayOnly = true
        своя.dog = её_собака
        её.insert(своя)
        try её.save()

        // Приехала запись от старого телефона: полей нет вовсе.
        let старая = CKRecord(recordType: SharedDiary.RecordType.event.rawValue,
                              recordID: SharedDiaryRecords.recordID(id, in: zone))
        старая["kind"] = LogKind.outing.rawValue
        старая["date"] = своя.date
        старая["authorName"] = "Виктория"
        старая["changedAt"] = Date().addingTimeInterval(60)
        let приехало = try #require(SharedDiaryRecords.eventPayload(старая))
        #expect(приехало.askSignal == nil, "разбор выдумал сигнал, которого в записи нет")
        #expect(приехало.isDayOnly == nil, """
            отсутствие поля прочитано как ответ «нет». `as? Bool` \
            сводит «не прислали» и «нет» в одно, и правка от прежней \
            версии стёрла бы оговорку.
            """)

        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        let после = try #require(try её.fetch(FetchDescriptor<LogEvent>()).first)
        #expect(после.askSignalRaw == AskSignal.scratchedDoor.rawValue, """
            правка от старого телефона стёрла «как попросил».
            """)
        #expect(после.isDayOnly == true, "правка от старого телефона стёрла оговорку")
        #expect(после.authorName == "Виктория", "сама правка при этом обязана была приехать")
    }

    /// Ничья по времени не должна выигрываться версией без данных.
    @Test("При ничьей выигрывает запись с «как попросил», а не без него")
    func ничьяВПользуЗаполненной() {
        let id = UUID()
        let когда = Date()
        func лента(_ сигнал: String?) -> EventPayload {
            EventPayload(id: id, dogID: nil, kind: LogKind.outing.rawValue,
                         date: когда, authorName: "Виктория", note: nil,
                         outcome: nil, durationSeconds: nil, stoolForm: nil,
                         stoolFlags: [], grams: nil, milliliters: nil,
                         fromPortion: false, incidentKind: nil, incidentDetail: nil,
                         walkEventID: nil, careTaskID: nil, medicationID: nil,
                         deletedAt: nil, deletedBy: nil,
                         askSignal: сигнал, isDayOnly: nil, enteredAt: nil,
                         editedBy: nil, origin: nil, reactionTrigger: nil,
                         reactionDistance: nil, toldFamily: nil,
                         trainingSessionID: nil, changedAt: когда)
        }
        let сСигналом = лента(AskSignal.scratchedDoor.rawValue)
        let безСигнала = лента(nil)

        #expect(SharedDiaryMerge.resolve(local: безСигнала, remote: сСигналом) == сСигналом, """
            ничья решилась в пользу записи без «как попросил». Часы двух \
            телефонов расходятся на секунды, и при ничьей разумнее взять \
            ту версию, где данных больше, — иначе расхождение часов \
            стирает ответ человека.
            """)
    }
}

/// Документы доезжают — подписью, без скана.
///
/// **До 07.10.2026 четыре поля (тип, номер, кем выдан, срок) ехали
/// в архив и не ехали ко второму человеку вовсе.** Документы нужны
/// тому, кто СЕГОДНЯ один с собакой: в клинике спрашивают номер,
/// на границе — срок.
///
/// **Скан намеренно не едет**, и ущерб назван зеркалом к находке
/// `togo-1e` про архив: там было «фотография без подписи», здесь
/// наоборот — **подпись без фотографии**. Тест это проверяет прямо,
/// а не подразумевает.
@Suite("Общий дневник · документы")
@MainActor
struct SharedDocumentSyncTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func телефон() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    @Test("Четыре поля документа доезжают: тип, номер, кем выдан, срок")
    func документДоезжает() throws {
        let (мой, собака) = try телефон()
        let паспорт = DogDocument(title: "Паспорт", image: Data([0xFF, 0xD8, 0xFF]),
                                  note: "в синей папке")
        паспорт.kindRaw = DocumentKind.passport.rawValue
        паспорт.number = "FR-2024-88120"
        паспорт.issuedBy = "Vet Riviera"
        паспорт.validUntil = Date(timeIntervalSince1970: 1_900_000_000)
        паспорт.dog = собака
        мой.insert(паспорт)
        try мой.save()

        let запись = SharedDiaryRecords.record(паспорт.payload, base: nil, in: zone)
        #expect(запись.recordType == SharedDiary.RecordType.document.rawValue)
        let приехало = try #require(SharedDiaryRecords.documentPayload(запись))

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        let у_мамы = try #require(try её.fetch(FetchDescriptor<DogDocument>()).first)

        #expect(у_мамы.kindRaw == DocumentKind.passport.rawValue, "тип документа не доехал")
        #expect(у_мамы.number == "FR-2024-88120", """
            номер не доехал. Его спрашивают в клинике и в полиции — \
            у того, кто привёл собаку, а не у владельца телефона.
            """)
        #expect(у_мамы.issuedBy == "Vet Riviera", "«кем выдан» не доехало")
        #expect(у_мамы.validUntil == паспорт.validUntil, """
            срок не доехал — то самое поле, из-за которого начинался \
            шаг 0: у Стича срок бешенства истёк 03.10, и назвать это \
            приложение не могло.
            """)
        #expect(у_мамы.title == "Паспорт")
        #expect(у_мамы.note == "в синей папке")
        #expect(у_мамы.dog?.name == "Стич", "документ приехал без собаки")

        // **Скан НЕ доехал, и это проверяется прямо.** Без этой строки
        // решение «не возим снимки» держалось бы на том, что никто
        // не дописал поле, — то есть на невнимательности, а не
        // на решении.
        #expect(у_мамы.image == nil, """
            скан приехал. Снимки не ездят решением брифа 22.09: они \
            сделали бы обмен тяжёлым ровно там, где он должен быть \
            мгновенным. Если это поменяли — менять надо `CKAsset`, \
            а не поле записи.
            """)
    }

    /// Приехавшая правка не стирает скан, который лежит у человека.
    @Test("Чужая правка номера не стирает местный скан")
    func чужаяПравкаНеСтираетСкан() throws {
        let (её, её_собака) = try телефон()
        let id = UUID()
        let свой = DogDocument(title: "Паспорт", image: Data([0xFF, 0xD8, 0xFF]))
        свой.id = id
        свой.number = "старый"
        свой.dog = её_собака
        её.insert(свой)
        try её.save()

        let приехало = DocumentPayload(
            id: id, dogID: её_собака.id, title: "Паспорт",
            kind: DocumentKind.passport.rawValue, number: "FR-2024-88120",
            issuedBy: nil, validUntil: nil, addedAt: Date(),
            note: nil, changedAt: Date().addingTimeInterval(60))
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let после = try #require(try её.fetch(FetchDescriptor<DogDocument>()).first)
        #expect(после.number == "FR-2024-88120", "правка номера не приехала")
        #expect(после.image != nil, """
            чужая правка стёрла местный скан. Поля в нагрузке нет — \
            значит и трогать его нельзя: человек положил страницу \
            паспорта у себя, и правка номера не имеет права её убрать. \
            Тот же случай, что с фото собаки.
            """)
    }

    /// У записи без типа умолчание — «прочее», а не паспорт.
    @Test("Документ без типа читается как «прочее», а не как паспорт")
    func умолчаниеТипаПрочее() throws {
        let запись = CKRecord(recordType: SharedDiary.RecordType.document.rawValue,
                              recordID: SharedDiaryRecords.recordID(UUID(), in: zone))
        запись["title"] = "скан"
        запись["changedAt"] = Date()
        let приехало = try #require(SharedDiaryRecords.documentPayload(запись))
        #expect(приехало.kind == DocumentKind.other.rawValue, """
            запись без типа прочитана как конкретный вид документа. \
            Тип — КЛЮЧ ГРУППИРОВКИ списка: подставив паспорт, мы \
            собрали бы в группу «паспорта» всё, что вида не прислало.
            """)
    }

    @Test("При ничьей выигрывает версия, где полей заполнено больше")
    func ничьяВПользуЗаполненной() {
        let id = UUID()
        let когда = Date()
        func документ(номер: String?, срок: Date?) -> DocumentPayload {
            DocumentPayload(id: id, dogID: nil, title: "Паспорт",
                            kind: DocumentKind.passport.rawValue, number: номер,
                            issuedBy: nil, validUntil: срок, addedAt: когда,
                            note: nil, changedAt: когда)
        }
        let полный = документ(номер: "FR-2024-88120", срок: когда)
        let пустой = документ(номер: nil, срок: nil)

        #expect(SharedDiaryMerge.resolve(local: пустой, remote: полный) == полный, """
            ничья решилась в пользу пустой версии. Номер и срок вводят \
            руками по одному разу, и терять набранное из-за расхождения \
            часов на секунды нельзя.
            """)
        #expect(SharedDiaryMerge.resolve(local: полный, remote: пустой) == полный,
                "исход зависит от того, с какой стороны спросили")
    }
}

/// Взвешивания доезжают до второго человека.
///
/// **Тип записи `WeightEntry` был объявлен с самого начала и
/// не создавался ни разу.** Поймал это сторож `RecordTypeUsedTests`,
/// заведённый 07.10.2026 под класс «объявлено, а писателя нет» —
/// четыре случая за один день.
///
/// Снаружи дыра выглядела закрытой: вес из профиля (`Dog.weightKg`)
/// возился с самого начала, и «вес не виден» было бы неправдой.
/// Не виден был **график**, а ущерб лежал не в графике:
///
/// > **Вес — то, от чего считается доза**, и расхождение веса между
/// > двумя людьми даёт расхождение дозы.
@Suite("Общий дневник · взвешивания")
@MainActor
struct SharedWeightSyncTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func телефон() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    @Test("Взвешивание доезжает со своим днём, а не с днём правки")
    func взвешиваниеДоезжает() throws {
        let (мой, собака) = try телефон()
        let когдаВзвесили = Date(timeIntervalSince1970: 1_770_000_000)
        let запись = WeightEntry(date: когдаВзвесили, kg: 4.35)
        запись.dog = собака
        мой.insert(запись)
        try мой.save()

        let ck = SharedDiaryRecords.record(запись.payload, base: nil, in: zone)
        #expect(ck.recordType == SharedDiary.RecordType.weight.rawValue)
        let приехало = try #require(SharedDiaryRecords.weightPayload(ck))

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let у_мамы = try #require(try её.fetch(FetchDescriptor<WeightEntry>()).first)
        #expect(у_мамы.kg == 4.35, "вес не доехал")
        #expect(у_мамы.date == когдаВзвесили, """
            день взвешивания потерян. `date` — это КОГДА ВЗВЕСИЛИ, \
            и подмена его временем правки превратила бы историю \
            в список «когда кто редактировал».
            """)
        #expect(у_мамы.dog?.name == "Стич", "взвешивание приехало без собаки")
    }

    /// Нулевой вес не принимается — ни разбором, ни приёмом.
    ///
    /// **Проверка стоит в ОБОИХ входах нарочно.** `accept` зовут
    /// и из тестов, минуя `CKRecord`: проверка в одном из двух входов —
    /// это проверка, которую обойдут, не заметив.
    @Test("Нулевой вес не принимается ни разбором, ни приёмом")
    func нулевойВесНеПринимается() throws {
        let ck = CKRecord(recordType: SharedDiary.RecordType.weight.rawValue,
                          recordID: SharedDiaryRecords.recordID(UUID(), in: zone))
        ck["date"] = Date()
        ck["kg"] = 0.0
        ck["changedAt"] = Date()
        #expect(SharedDiaryRecords.weightPayload(ck) == nil, """
            запись с нулём разобралась как годная. `kg` по умолчанию \
            ноль, и ноль — это не «собака весит ноль», а запись, \
            которую не заполнили. Приняв её, мы положили бы в график \
            точку, от которой считается ДОЗА.
            """)

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(
            WeightPayload(id: UUID(), dogID: её_собака.id, date: Date(),
                          kg: 0, changedAt: Date()),
            dog: её_собака, context: её)
        #expect(try её.fetch(FetchDescriptor<WeightEntry>()).isEmpty, """
            приём завёл взвешивание с нулём — второй вход того же \
            дефекта, и он обходится мимо разбора записи.
            """)
    }

    /// При ничьей по времени выигрывает МЕНЬШИЙ вес.
    @Test("При ничьей выигрывает меньший вес: от веса считается доза")
    func ничьяВПользуМеньшегоВеса() {
        let id = UUID()
        let когда = Date()
        func вес(_ kg: Double) -> WeightPayload {
            WeightPayload(id: id, dogID: nil, date: когда, kg: kg, changedAt: когда)
        }
        #expect(SharedDiaryMerge.resolve(local: вес(4.8), remote: вес(4.3)) == вес(4.3), """
            ничья решилась в пользу большего веса. Доза считается \
            от веса: завысив вес, мы завысим дозу. Ошибиться в сторону \
            меньшей дозы безопаснее, чем в сторону большей.
            """)
        #expect(SharedDiaryMerge.resolve(local: вес(4.3), remote: вес(4.8)) == вес(4.3),
                "исход зависит от того, с какой стороны спросили")

        // А правка, что позже, побеждает независимо от веса: человек
        // мог исправить опечатку, и «меньший» не должен её отменять.
        var позже = вес(5.2)
        позже.changedAt = когда.addingTimeInterval(60)
        #expect(SharedDiaryMerge.resolve(local: вес(4.3), remote: позже) == позже, """
            правка, что позже, проиграла меньшему весу. Тогда \
            исправление опечатки «4,3 вместо 5,2» было бы невозможно \
            со второго телефона.
            """)
    }
}

/// Медкнижка доезжает до второго человека.
///
/// **Зачем она ездит, одной строкой:** в клинику собаку ведёт тот, кто
/// сегодня свободен, а бланки лежат на телефоне хозяйки. Без обмена
/// второй человек приходит к врачу с пересказом.
///
/// Проверка идёт **значениями через запись CloudKit**: поле может лежать
/// в нагрузке и не попасть в `CKRecord` — это следующий слой, и сторож
/// имён его не видит.
@Suite("Общий дневник · медкнижка")
@MainActor
struct SharedMedicalSyncTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func телефон() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    /// **Главный тест суиты.** Предел обнаружения остаётся пределом.
    @Test("Анализ доезжает: предел «<0,1» не превращается в число 0,1")
    func анализДоезжает() throws {
        let (мой, собака) = try телефон()
        let анализ = LabResult(sampledOn: Date(timeIntervalSince1970: 1_780_000_000),
                               indicator: "Т4 свободный", section: "гормоны",
                               laboratory: "IDEXX", reportNumber: "VF120682")
        анализ.sampledAt = Date(timeIntervalSince1970: 1_780_018_000)
        анализ.belowLimit = 0.1
        анализ.unit = "нг/дл"
        анализ.referenceLow = 12.9
        анализ.referenceHigh = 51.5
        анализ.method = "равновесный диализ"
        анализ.labMark = "↓"
        анализ.note = "на бланке Т+5ч, по счёту ≈3,5 ч"
        анализ.dog = собака
        мой.insert(анализ)
        try мой.save()

        let запись = SharedDiaryRecords.record(анализ.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.labResultPayload(запись))

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)
        let у_мамы = try #require(try её.fetch(FetchDescriptor<LabResult>()).first)

        #expect(у_мамы.value == nil, """
            у второго человека появилось число там, где его не было. \
            `<0,1` — это НЕ 0,1: записав пределом, мы отдали бы тихо \
            неверное значение вместо видимо неизвестного.
            """)
        #expect(у_мамы.belowLimit == 0.1, "предел обнаружения не доехал")
        #expect(у_мамы.sampledAt == анализ.sampledAt, """
            время забора не доехало, а при активном лечении оно \
            обязательно: без «левотироксин принят N часов назад» \
            результат не интерпретируется вовсе.
            """)
        #expect(у_мамы.method == "равновесный диализ", """
            метод не доехал — и тогда два значения разными методами \
            станут противоречием там, где его нет.
            """)
        #expect(у_мамы.labMark == "↓", """
            отметка лаборатории не доехала. Она не наш вердикт, а факт \
            из документа, и расхождение с нашим счётом — находка.
            """)
        #expect(у_мамы.referenceLow == 12.9 && у_мамы.referenceHigh == 51.5)
        #expect(у_мамы.unit == "нг/дл", "единица не доехала")
        #expect(у_мамы.reportNumber == "VF120682", "номер отчёта не доехал")
        #expect(у_мамы.dog?.name == "Стич", "анализ приехал без собаки")
    }

    @Test("Текстовый результат бактериологии доезжает")
    func текстовыйРезультатДоезжает() throws {
        let (мой, собака) = try телефон()
        let посев = LabResult(sampledOn: Date(), indicator: "посев",
                              section: "бактериология", laboratory: "Antech")
        посев.textValue = "выделен штамм коагулазо-отрицательного стафилококка"
        посев.dog = собака
        мой.insert(посев)
        try мой.save()

        let запись = SharedDiaryRecords.record(посев.payload, base: nil, in: zone)
        let приехало = try #require(SharedDiaryRecords.labResultPayload(запись))
        #expect(приехало.textValue?.contains("стафилококка") == true, """
            текстовый результат не доехал. Девять строк карты — \
            описание, а не число, и без этого поля они не влезают вовсе.
            """)
    }

    @Test("Визит доезжает вместе с клиникой и поводом «онлайн»")
    func визитДоезжает() throws {
        let (мой, собака) = try телефон()
        let клиника = Clinic(name: "Vet Riviera", phone: "+33 4 93 00 00 00")
        мой.insert(клиника)
        let визит = VetVisit(date: Date(timeIntervalSince1970: 1_782_000_000),
                             doctor: "Кочубина", reasonRaw: VisitReason.online.rawValue)
        визит.conclusion = "рабочая гипотеза: вторичный характер"
        визит.clinic = клиника
        визит.dog = собака
        мой.insert(визит)
        try мой.save()

        // Справочник приезжает раньше — порядок приёма это обеспечивает.
        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(
            try #require(SharedDiaryRecords.clinicPayload(
                SharedDiaryRecords.record(клиника.payload, base: nil, in: zone))),
            context: её)

        let приехало = try #require(SharedDiaryRecords.vetVisitPayload(
            SharedDiaryRecords.record(визит.payload, base: nil, in: zone)))
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let у_мамы = try #require(try её.fetch(FetchDescriptor<VetVisit>()).first)
        #expect(у_мамы.reasonRaw == VisitReason.online.rawValue, """
            повод визита не доехал. Онлайн-консультация — такой же \
            визит, и став «осмотром», она соврёт про то, чего не было: \
            у Стича их две, и одна дала рабочую гипотезу диагноза.
            """)
        #expect(у_мамы.conclusion.contains("вторичный"), "заключение врача не доехало")
        #expect(у_мамы.clinic?.name == "Vet Riviera", "связь визита с клиникой не сшилась")
        #expect(у_мамы.doctor == "Кочубина")
    }

    @Test("Диагноз доезжает со статусом: по подтверждённому лечат, по гипотезе ищут")
    func диагнозДоезжаетСоСтатусом() throws {
        let (мой, собака) = try телефон()
        let диагноз = Diagnosis(wording: "первичный гипотиреоз",
                                madeOn: Date(timeIntervalSince1970: 1_783_000_000),
                                statusRaw: DiagnosisStatus.confirmed.rawValue)
        диагноз.madeBy = "Кочубина, Vet Riviera"
        диагноз.evidence = "VF120682"
        диагноз.dog = собака
        мой.insert(диагноз)
        try мой.save()

        let приехало = try #require(SharedDiaryRecords.diagnosisPayload(
            SharedDiaryRecords.record(диагноз.payload, base: nil, in: zone)))
        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let у_мамы = try #require(try её.fetch(FetchDescriptor<Diagnosis>()).first)
        #expect(у_мамы.statusRaw == DiagnosisStatus.confirmed.rawValue, """
            статус диагноза не доехал. По подтверждённому лечат, \
            по гипотезе ищут — и человек, получивший одно вместо \
            другого, будет действовать не по тому.
            """)
        #expect(у_мамы.evidence == "VF120682", "чем подтверждён — не доехало")
    }

    /// Запись без статуса читается как ГИПОТЕЗА, а не «подтверждён».
    @Test("У записи без статуса умолчание — гипотеза, а не подтверждённый")
    func умолчаниеСтатусаГипотеза() throws {
        let запись = CKRecord(recordType: SharedDiary.RecordType.diagnosis.rawValue,
                              recordID: SharedDiaryRecords.recordID(UUID(), in: zone))
        запись["madeOn"] = Date()
        запись["changedAt"] = Date()
        запись["wording"] = "что-то"
        let приехало = try #require(SharedDiaryRecords.diagnosisPayload(запись))
        #expect(приехало.status == DiagnosisStatus.hypothesis.rawValue, """
            запись без статуса прочитана как подтверждённый диагноз. \
            Мы не знаем, что это, — и назвать подтверждённым значило бы \
            начать лечить по тому, о чём не спрашивали.
            """)
    }

    /// При ничьей выигрывает СНЯТЫЙ диагноз, и это не «больше полей».
    @Test("При ничьей выигрывает снятый диагноз: по снятому не лечат")
    func ничьяВПользуСнятого() {
        let id = UUID()
        let когда = Date()
        func диагноз(_ статус: DiagnosisStatus) -> DiagnosisPayload {
            DiagnosisPayload(id: id, dogID: nil, wording: "первичный гипотиреоз",
                             status: статус.rawValue, madeOn: когда,
                             madeBy: "врач", evidence: "VF120682", changedAt: когда)
        }
        let снят = диагноз(.withdrawn)
        let подтверждён = диагноз(.confirmed)

        #expect(SharedDiaryMerge.resolve(local: подтверждён, remote: снят) == снят, """
            ничья решилась в пользу подтверждённого диагноза. Цена \
            ошибки несимметрична: лечить по СНЯТОМУ хуже, чем не лечить \
            по подтверждённому лишний час до следующего круга обмена.
            """)
        #expect(SharedDiaryMerge.resolve(local: снят, remote: подтверждён) == снят,
                "исход зависит от того, с какой стороны спросили")
    }

    @Test("Назначение доезжает: вес на дату, форма, окно контроля, источник")
    func назначениеДоезжает() throws {
        let (мой, собака) = try телефон()
        let клиника = Clinic(name: "Vet Riviera")
        мой.insert(клиника)
        let рецепт = Prescription(number: "8935331",
                                  date: Date(timeIntervalSince1970: 1_784_000_000),
                                  medicationName: "Lévothyrox")
        рецепт.doctor = "Кочубина"
        рецепт.dogWeightKg = 4.1
        рецепт.dosage = "66 мкг"
        рецепт.schedule = "дважды в день натощак"
        рецепт.duration = "до контроля"
        рецепт.pharmacyForm = "магистральный"
        рецепт.controlFromWeeks = 4
        рецепт.controlToWeeks = 6
        рецепт.dispensed = "4 таблетки"
        рецепт.instruction = "не кормить 45 минут после"
        рецепт.source = "PDF-ордоннанс"
        рецепт.clinic = клиника
        рецепт.dog = собака
        мой.insert(рецепт)
        try мой.save()

        let (её, её_собака) = try телефон()
        SharedDiaryInbox.accept(
            try #require(SharedDiaryRecords.clinicPayload(
                SharedDiaryRecords.record(клиника.payload, base: nil, in: zone))),
            context: её)
        let приехало = try #require(SharedDiaryRecords.prescriptionPayload(
            SharedDiaryRecords.record(рецепт.payload, base: nil, in: zone)))
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let у_мамы = try #require(try её.fetch(FetchDescriptor<Prescription>()).first)
        #expect(у_мамы.number == "8935331", "номер рецепта не доехал — в аптеке по нему получают")
        #expect(у_мамы.dogWeightKg == 4.1, """
            вес на дату назначения не доехал. Доза считается от него, \
            а история взвешиваний ко второму человеку пока НЕ едет — \
            значит это единственное место, откуда он сможет проверить \
            дозу задним числом.
            """)
        #expect(у_мамы.pharmacyForm == "магистральный", """
            форма препарата не доехала. Вопрос ретроспективный — «какая \
            форма была в тот месяц, когда Т4 провалился», — и ответ \
            ждут к контролю 13.10.
            """)
        #expect(у_мамы.controlFromWeeks == 4 && у_мамы.controlToWeeks == 6, """
            окно контроля не доехало. Это единственное место, откуда \
            приложение знает, когда напоминать; три врача назвали три \
            разных интервала, и сведение к одной дате придумало бы \
            число за врача.
            """)
        #expect(у_мамы.instruction.contains("45 минут"), "инструкция не доехала")
        #expect(у_мамы.source == "PDF-ордоннанс", """
            происхождение не доехало. Оно решает споры: в карте \
            девятнадцать пробелов, где назначение известно письмом, \
            а бланка нет вовсе.
            """)
        #expect(у_мамы.clinic?.name == "Vet Riviera", "связь рецепта с клиникой не сшилась")
    }

    /// Промах по id клиники ловится именем — как у дела ухода.
    @Test("Своя «Vet Riviera» с другим UUID подхватывается по имени")
    func промахПоIdЛовитсяИменем() throws {
        let (её, её_собака) = try телефон()
        let её_клиника = Clinic(name: "Vet Riviera", phone: "её номер")
        её.insert(её_клиника)
        try её.save()

        let приехало = PrescriptionPayload(
            id: UUID(), dogID: её_собака.id, number: "8935331", date: Date(),
            clinicID: UUID(), clinicName: "Vet Riviera", doctor: "Кочубина",
            dogWeightKg: 4.1, medicationName: "Lévothyrox", dosage: "66 мкг",
            schedule: "", duration: "", pharmacyForm: nil,
            controlFromWeeks: 4, controlToWeeks: 6, dispensed: "",
            instruction: "", source: "", changedAt: Date())
        SharedDiaryInbox.accept(приехало, dog: её_собака, context: её)

        let у_мамы = try #require(try её.fetch(FetchDescriptor<Prescription>()).first)
        #expect(у_мамы.clinic?.id == её_клиника.id, """
            промах по id оставил рецепт без клиники, хотя та же клиника \
            лежит рядом под тем же именем. Промах по id здесь норма: \
            справочник могли завести до включения обмена.
            """)
        #expect(try её.fetch(FetchDescriptor<Clinic>()).count == 1,
                "приём завёл вторую клинику — справочник без дублей это правило дизайна")
    }

    /// Границы — печатаются, а не хранятся в чьей-то памяти.
    @Test("Границы: чего не проверяет набор про медкнижку в обмене")
    func границыНазваны() {
        let границы = """
            Зелёный здесь значит: запись медкнижки собирается в CKRecord, \
            разбирается обратно и ложится у второго человека теми же \
            значениями. И только это.

            НЕ проверяется:
            · настоящий CloudKit — двух телефонов эти тесты не заменяют;
            · ПОРЯДОК приезда в живом обмене. Он задан рангом
              в `FamilySync` (клиника → собака → остальное), и здесь
              справочник подаётся вручную первым. Приедь запись раньше
              клиники — связь сошьётся пустой до следующей правки;
            · ДОЗАЛИВКИ НЕТ. `start()` ставит слушателя на
              `ModelContext.didSave` и зовёт `fetchNow()` — это забор.
              Отправки уже существующих записей нет ни строкой, обхода
              по типам для неё тоже. Значит ко второму человеку уедет
              только то, что сохранят ПОСЛЕ включения обмена, а собаку
              заводят один раз: в день приглашения он увидит пустую
              комнату. Это не чинится выходом сборки.
            """
        // Утверждение, печатаемое здесь, обязано быть проверяемым
        // за минуту — иначе оно предание, а не граница. Способ:
        //   grep -c 'WeightEntry' TogoShared/Sync/FamilySync.swift
        //   sed -n '95,118p' TogoShared/Sync/FamilySync.swift   ← забор, не отправка
        //
        // **Здесь уже лежало ложное утверждение, и это стоит записать.**
        // До 08.10.2026 строкой выше стояло «взвешивания: история веса
        // ко второму человеку НЕ едет вовсе». На момент написания это
        // было правдой; `05ced4a` взвешивания завёз, и строка устарела
        // МОЛЧА — `WeightEntry` в `FamilySync` 2 вхождения, `case .weight`
        // есть, круг замкнут.
        //
        // > **Блок границ врал ровно там, где мы специально завели
        // > правду, и читался как замер.** Хуже обычного устаревания:
        // > остальной текст проверяют, когда диф удивил, а этот никто
        // > не дифает — он «просто описание».
        //
        // И механизм, из-за которого оно не могло покраснеть: проверка
        // ниже спрашивает только `isEmpty == false`. У неё нет ни одного
        // способа оказаться неверной — она печатается до работы и от её
        // исхода не зависит. Это тот же класс, что ярлык «KADRY (светлая
        // тема)» над тёмным кадром: ярлык, который печатает сам
        // инструмент, не является его замером.
        //
        // Сильной проверки текста здесь не завожу нарочно: сторож,
        // сверяющий прозу с кодом, — это второй разбор Swift регулярками,
        // а два таких за один день уже сломались об одну вложенную
        // кавычку. Поэтому у каждого утверждения стоит КОМАНДА проверки,
        // и стареет оно теперь громко.
        #expect(границы.isEmpty == false)
    }
}

@Suite("Общий дневник · доза находит препарат")
@MainActor
struct SharedDoseMedicationTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
