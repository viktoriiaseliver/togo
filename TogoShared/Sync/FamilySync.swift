import Foundation
import CloudKit
import SwiftData

/// Обмен записями между телефонами семьи.
///
/// **Устройство.** Своя зона `family` в личном iCloud владельца. Владелец
/// делится зоной целиком (`CKShare`), приглашённый видит её в общей базе.
/// Оба конца ведут `CKSyncEngine`: он сам держит очередь, повторяет
/// неудачные отправки и переживает офлайн.
///
/// **Почему не зеркалирование SwiftData.** Оно умеет только личную базу
/// одного Apple ID — то есть свои же устройства. Второго человека туда
/// не пустить никакими настройками: это ограничение самого SwiftData,
/// а не выбор.
///
/// **Что здесь важнее всего.** Локальная база остаётся единственным
/// источником правды. Обмен ничего не решает сам: он приносит чужие
/// снимки в `SharedDiaryInbox`, а тот применяет правила слияния. Если
/// CloudKit недоступен, сломан или выключен — приложение работает ровно
/// так же, как работало до него.
@MainActor
@Observable
final class FamilySync: NSObject {

    enum State: Equatable, Sendable {
        case off
        case starting
        case idle(lastSync: Date?)
        case syncing
        case failed(String)

        var isOn: Bool { self != .off }
    }

    private(set) var state: State = .off
    /// Сколько своих изменений ещё не уехало.
    private(set) var pending: Int = 0

    private let container: CKContainer
    private let modelContainer: ModelContainer
    /// Своя зона в личной базе — она же та, которой делятся.
    private var privateEngine: CKSyncEngine?
    /// Чужая зона в общей базе — если нас пригласили.
    private var sharedEngine: CKSyncEngine?
    private var engines: [CKSyncEngine] { [privateEngine, sharedEngine].compactMap { $0 } }
    /// Не отправлять обратно то, что только что приняли.
    private var applying = false
    /// Серверные версии отправленного: без них второе сохранение любой
    /// записи падает на `serverRecordChanged`.
    private let outbox = SharedDiaryOutbox()

    /// Зона общего дневника: своя или того, кто позвал.
    private var zone: CKRecordZone.ID { SharedZoneRouting.zone(owner: SharedZoneOwner.name) }

    /// Куда класть своё.
    ///
    /// Гость пишет в зону владельца через общую базу. Пока здесь стоял
    /// «первый движок», он писал в свою личную — и отметки гостя
    /// не уезжали никуда.
    private var outgoingEngine: CKSyncEngine? {
        SharedZoneRouting.scope(owner: SharedZoneOwner.name) == .shared ? sharedEngine : privateEngine
    }

    /// Главный контекст, а не свой новый на каждый вызов: чужая запись
    /// должна появиться на экране сразу, а не после следующего запроса.
    private var context: ModelContext { modelContainer.mainContext }

    init(modelContainer: ModelContainer,
         container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)) {
        self.modelContainer = modelContainer
        self.container = container
        super.init()
    }

    // MARK: Включение

    /// Поднять обмен. Молча ничего не делает, если права на iCloud нет:
    /// обещать синхронизацию, которой не может быть, нельзя.
    func start() async {
        guard Persistence.hasCloudEntitlement else {
            state = .failed("У этой сборки нет права на iCloud")
            return
        }
        guard await accountIsReady() else {
            state = .failed("Войди в iCloud на телефоне — общий дневник живёт там")
            return
        }

        state = .starting

        // Своя зона в личной базе — она же то, чем делятся.
        privateEngine = makeEngine(database: container.privateCloudDatabase,
                                   key: SyncStateStore.privateKey)
        // Чужая зона, если нас пригласили.
        sharedEngine = makeEngine(database: container.sharedCloudDatabase,
                                  key: SyncStateStore.sharedKey)

        state = .idle(lastSync: SyncStateStore.lastSync)
        // Обмен поднимают из трёх мест — с экрана, по приходу
        // приглашения и на запуске. Подписка ставится заново, иначе
        // на каждое сохранение набирается по слушателю.
        NotificationCenter.default.removeObserver(self, name: ModelContext.didSave, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(localSaveHappened),
            name: ModelContext.didSave, object: nil
        )
        await fetchNow()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: ModelContext.didSave, object: nil)
        privateEngine = nil
        sharedEngine = nil
        outbox.forgetAll()
        state = .off
    }

    private func makeEngine(database: CKDatabase, key: String) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: SyncStateStore.load(key),
            delegate: self
        )
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }

    private func accountIsReady() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Забрать чужое прямо сейчас — например когда экран открыли руками.
    func fetchNow() async {
        guard !engines.isEmpty else { return }
        state = .syncing
        for engine in engines {
            try? await engine.fetchChanges()
        }
        SyncStateStore.lastSync = Date()
        state = .idle(lastSync: SyncStateStore.lastSync)
    }

    // MARK: Свои изменения

    /// Что-то сохранили в базе — значит, надо отправить.
    ///
    /// Слушаем сохранение, а не зовём вручную из экранов: рука пишет
    /// в дневник из полутора десятков мест, и позвать забудут ровно там,
    /// где важнее всего.
    @objc private func localSaveHappened(_ notification: Notification) {
        guard !applying, !engines.isEmpty else { return }
        Task { @MainActor in await enqueueLocalChanges(notification) }
    }

    private func enqueueLocalChanges(_ notification: Notification) async {
        let zone = self.zone
        let ctx = context
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var stamped = false

        // Отметка времени ставится здесь, а не на экранах.
        //
        // Рука правит запись из полутора десятков мест — прямо через
        // привязки полей, без единой общей функции. Позвать «пометь
        // изменённым» забудут ровно там, где это важнее всего, и спор
        // двух телефонов начнёт сравнивать время создания вместо времени
        // правки. Сохранение же случается всегда.
        applying = true
        defer { applying = false }

        let now = Date()
        for key in ["inserted", "updated"] {
            guard let ids = notification.userInfo?[key] as? [PersistentIdentifier] else { continue }
            for id in ids {
                if let event = ctx.model(for: id) as? LogEvent {
                    event.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(event.id, in: zone)))
                } else if let dose = ctx.model(for: id) as? DoseRecord {
                    dose.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(dose.id, in: zone)))
                } else if let dog = ctx.model(for: id) as? Dog {
                    // Профиль ездит с 23.09: без него приглашение вело
                    // в пустую комнату — мама не видела ни собаки,
                    // ни веса, ни того, что идёт лечение.
                    dog.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(dog.id, in: zone)))
                }
            }
        }

        // Сохранение отметки времени не уйдёт по второму кругу:
        // на входе стоит тот же замок, что и у приёма чужого.
        // Отметка времени не записалась — отправлять нечего: иначе
        // уедет то, о чём хранилище не знает, и следующий круг увидит
        // расхождение вместо записи.
        if stamped, !ctx.persist(otherwise: {}) {
            log.error("общий дневник: отметка времени не записалась")
            return
        }

        guard !changes.isEmpty, let engine = outgoingEngine else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        pending = engine.state.pendingRecordZoneChanges.count
    }

}

// MARK: - Движок

extension FamilySync: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            await MainActor.run {
                SyncStateStore.save(update.stateSerialization,
                                    for: syncEngine.database.databaseScope == .private
                                        ? SyncStateStore.privateKey : SyncStateStore.sharedKey)
            }

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes)

        case .sentRecordZoneChanges(let sent):
            await MainActor.run {
                // Подтверждённые записи несут свежий `recordChangeTag` —
                // без него следующая правка той же записи не пройдёт.
                self.outbox.remember(sent.savedRecords)

                let failures = sent.failedRecordSaves.map {
                    (id: $0.record.recordID, error: $0.error as Error)
                }
                let again = self.outbox.retries(after: failures)
                if !again.isEmpty {
                    // Спор о версии — не отказ. Ставим в очередь заново:
                    // на второй попытке запись уйдёт поверх серверной.
                    syncEngine.state.add(
                        pendingRecordZoneChanges: again.map { .saveRecord($0) }
                    )
                }

                self.pending = syncEngine.state.pendingRecordZoneChanges.count

                // В журнал — только то, что мы повторить не умеем.
                // Прежде сюда писался и обычный спор версий, и он был
                // единственным следом навсегда потерянной отметки.
                for failure in sent.failedRecordSaves
                where !again.contains(failure.record.recordID) {
                    log.notice("Общий дневник: отправка не прошла — \(failure.error.localizedDescription)")
                }
            }

        case .accountChange:
            await MainActor.run { self.state = .failed("Аккаунт iCloud сменился — включи общий дневник заново") }

        default:
            break
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            if case .saveRecord = $0 { return true }
            return false
        }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }

    /// Собрать запись CloudKit из своей базы.
    private func record(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        let ctx = context

        // Серверная версия, если она у нас есть: на ней стоит
        // `recordChangeTag`, без которого сервер отбивает правку.
        let base = outbox.base(for: recordID)

        if let event = try? ctx.fetch(
            FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(event.payload, base: base, in: recordID.zoneID)
        }
        if let dose = try? ctx.fetch(
            FetchDescriptor<DoseRecord>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(dose.payload, base: base, in: recordID.zoneID)
        }
        if let dog = try? ctx.fetch(
            FetchDescriptor<Dog>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(dog.payload, base: base, in: recordID.zoneID)
        }
        return nil
    }

    /// Принять чужие изменения.
    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        await MainActor.run {
            applying = true
            defer { applying = false }

            let ctx = context

            // Собаки — первыми, и это не оптимизация.
            //
            // Записи приезжают пачкой в порядке сервера, и лента почти
            // всегда идёт раньше профиля: её правят каждый день, а профиль
            // раз в месяц. Пока собака не заведена, каждая запись пачки
            // цеплялась к ПЕРВОЙ местной (а у гостя это его собственная
            // собака) или повисала ничьей, если местной нет ни одной.
            // Разобрать профили до ленты стоит один проход по массиву.
            let modifications = changes.modifications.sorted { left, _ in
                left.record.recordType == SharedDiary.RecordType.dog.rawValue
            }

            for modification in modifications {
                let record = modification.record
                // Пришедшее с сервера — тоже источник `recordChangeTag`:
                // свою правку этой записи мы пошлём уже поверх неё.
                outbox.remember(record)

                switch SharedDiary.RecordType(rawValue: record.recordType) {
                case .dog:
                    guard let payload = SharedDiaryRecords.dogPayload(record) else { continue }
                    SharedDiaryInbox.accept(payload, context: ctx)
                case .event:
                    guard let payload = SharedDiaryRecords.eventPayload(record) else { continue }
                    // Собака берётся по id из самой записи. Раньше здесь
                    // стояла первая местная — и у гостя с двумя собаками
                    // чужие отметки ложились на его собственную.
                    SharedDiaryInbox.accept(
                        payload,
                        dog: SharedDiaryInbox.dog(for: payload, context: ctx),
                        context: ctx
                    )
                case .dose:
                    guard let payload = SharedDiaryRecords.dosePayload(record) else { continue }
                    // Препарат ищется по id, а при промахе — по имени:
                    // схемы лечения не обмениваются, и у второго
                    // человека тот же препарат заведён с другим UUID.
                    SharedDiaryInbox.accept(
                        payload,
                        medication: SharedDiaryInbox.medication(for: payload, context: ctx),
                        context: ctx
                    )
                default:
                    continue
                }
            }

            SyncStateStore.lastSync = Date()
            state = .idle(lastSync: SyncStateStore.lastSync)
        }
    }
}

// MARK: - Где живёт состояние движка

/// `CKSyncEngine` отдаёт свой слепок и просит сохранить его до следующего
/// запуска: без него он при каждом старте выкачивал бы всё заново.
nonisolated enum SyncStateStore {
    static let privateKey = "sync.state.private"
    static let sharedKey = "sync.state.shared"
    private static let lastSyncKey = "sync.lastSync"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    static func load(_ key: String) -> CKSyncEngine.State.Serialization? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    static func save(_ state: CKSyncEngine.State.Serialization, for key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    static var lastSync: Date? {
        get { defaults.object(forKey: lastSyncKey) as? Date }
        set { defaults.set(newValue, forKey: lastSyncKey) }
    }

    static func reset() {
        for key in [privateKey, sharedKey, lastSyncKey] { defaults.removeObject(forKey: key) }
    }
}

// MARK: - Включён ли общий дневник

/// Флаг живёт в общей группе, а не в `Settings`: его читает и делегат
/// приёма приглашения, у которого экранов нет.
nonisolated enum SharedDiarySettings {
    private static let key = "sharedDiary.on"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    static var isOn: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
