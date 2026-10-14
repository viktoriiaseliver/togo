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

    /// Доза приехала отмеченной — снять по ней местные напоминания.
    ///
    /// **Параметр обязательный, и умолчания у него нет нарочно.**
    /// Снимает напоминания `ReminderScheduler`, который лежит
    /// в `Togo/Store/`, то есть только в цели приложения; `TogoShared`
    /// входит синхронизированной группой **в оба** таргета, и прямой
    /// вызов отсюда не собрался бы в расширении виджета. Значит нужен
    /// обратный вызов — а обратный вызов, который можно не поставить,
    /// это механизм без входа: всё компилируется, тесты зелёные,
    /// и от рабочего он не отличается ничем.
    ///
    /// Умолчание `= { _ in }` вернуло бы ровно эту беду и выглядело бы
    /// вежливостью. Без умолчания забыть нельзя: решение принимает
    /// компилятор на каждой точке создания, а их одна.
    private let дозаБольшеНеЖдёт: @MainActor (DoseRecord) -> Void

    init(modelContainer: ModelContainer,
         дозаБольшеНеЖдёт: @escaping @MainActor (DoseRecord) -> Void,
         container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)) {
        self.modelContainer = modelContainer
        self.дозаБольшеНеЖдёт = дозаБольшеНеЖдёт
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
        await засеять()
    }

    /// Отправить второму человеку то, что уже лежало в хранилище.
    ///
    /// Сбор — в `SharedDiarySeed.изменения`, там же и почему он отдельно:
    /// движок в тест не поставить, а решение «что считается накопленным»
    /// проверяемо. Здесь только отправка и флаг.
    ///
    /// **`hasPendingUntrackedChanges` я сознательно НЕ ставлю.** Ручка
    /// штатная и по названию ровно про наш случай — «учёт незасеянного
    /// веду я сам», — но она для ДРУГОЙ стратегии: когда движку
    /// не перечисляют изменения, а говорят «у меня есть что-то, спроси
    /// меня». Мы перечисляем явно через `add(pendingRecordZoneChanges:)`,
    /// а `nextRecordZoneChangeBatch` собирает батч ТОЛЬКО из очереди —
    /// сверх неё отдать нечего. Выставить флаг значило бы обещать движку
    /// то, чего он от нас не получит.
    ///
    /// Записано потому, что ручку нашла сверка документации и её легко
    /// принять за обязательную половину.
    private func засеять() async {
        guard let engine = outgoingEngine else { return }
        let owner = SharedZoneOwner.name
        guard !SyncSeedState.засеяно(владелец: owner) else { return }

        let changes = SharedDiarySeed.изменения(context: context, zone: zone)
        guard !changes.isEmpty else {
            // Пустое хранилище — засевать нечего, и это засев, а не отказ.
            SyncSeedState.отметить(владелец: owner)
            return
        }

        // Предел 250 записей на запрос держит сам движок: батч собирается
        // через `RecordZoneChangeBatch(pendingChanges:recordProvider:)`
        // в `nextRecordZoneChangeBatch` — проверено чтением, а не
        // предположено. Очередь при этом любой длины: ограничен батч,
        // а не очередь. Собранный руками батч на таком объёме упал бы
        // с `limitExceeded`.
        engine.state.add(pendingRecordZoneChanges: changes)
        pending = engine.state.pendingRecordZoneChanges.count
        SyncSeedState.отметить(владелец: owner)
        log.notice("общий дневник: засев отправил \(changes.count) записей")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: ModelContext.didSave, object: nil)
        privateEngine = nil
        sharedEngine = nil
        outbox.forgetAll()
        // Выключили обмен — засев больше не считается сделанным.
        // Иначе включённый заново обмен не отправит накопленное
        // за время, пока он был выключен, и это молча: симптом тот же,
        // что до появления засева. Чем флаг может соврать и что
        // из этого выйдет — в `SyncSeedState`.
        SyncSeedState.сбросить(владелец: SharedZoneOwner.name)
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
    ///
    /// **Отказ чтения был невидим целиком, и это хуже самого отказа.**
    /// Здесь стояло `try? await engine.fetchChanges()`: ошибка уходила
    /// в никуда, а следом состояние становилось `idle(lastSync: сейчас)`
    /// — приложение говорило «синхронизировано» ровно в ту секунду,
    /// когда синхронизация провалилась.
    ///
    /// Цена замерена 24.09: у второго человека два дня не появлялось
    /// ничего из общего дневника, его экран при этом выглядел рабочим,
    /// и различить «не пришло, потому что нечего» от «не пришло, потому
    /// что упало» было нечем — ни на телефоне, ни в журнале.
    ///
    /// Теперь: ошибка каждой базы попадает в журнал со своим именем,
    /// состояние становится `failed`, а **время последней сверки
    /// не двигается** — оно значит «последний раз, когда чужое правда
    /// доехало», и двигать его на неудаче значит врать тем же способом,
    /// только тише.
    func fetchNow() async {
        guard !engines.isEmpty else { return }
        state = .syncing

        var отказы: [Error] = []
        for engine in engines {
            do {
                try await engine.fetchChanges()
            } catch {
                отказы.append(error)
                // Имя базы латиницей — это крошка для того, кто чинит,
                // а не подпись для хозяина собаки: `private` и `shared`
                // тут те же слова, что в CloudKit, и искать по ним в логе
                // телефона проще, чем по переводу.
                let база = engine.database.databaseScope == .private ? "private" : "shared"
                log.error("""
                    Общий дневник: чтение не прошло (\(база, privacy: .public)) — \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }

        if отказы.isEmpty { SyncStateStore.lastSync = Date() }
        state = Self.состояние(послеОтказов: отказы, lastSync: SyncStateStore.lastSync)
    }

    /// Во что превращается неудачное чтение.
    ///
    /// Отдельной функцией, потому что проверять надо именно её: движок
    /// в тест не поставить, а решение «что человек увидит, когда чужое
    /// не пришло» — ровно то, на чём этот проект обжигался дважды.
    static func состояние(послеОтказов отказы: [Error], lastSync: Date?) -> State {
        guard let первый = отказы.first else { return .idle(lastSync: lastSync) }
        return .failed(String(
            localized: "Записи семьи не пришли: \(первый.localizedDescription)"))
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
                    // Ворота — ОБЩИЕ с засевом, той же функцией и по той
                    // же причине, что у собаки ниже: запрет в одной двери
                    // второй не знает.
                    //
                    // Ловят отладочную запись прогрева схемы. Замер
                    // 08.10.2026 по выгрузке с телефона Виктории: из 182
                    // записей одна с датой `2001-01-01` и автором
                    // `ПРОГРЕВ СХЕМЫ`, у видимой собаки «Стич». Весь
                    // `CloudKitSchemaWarmup` под `#if DEBUG` — в продуктовой
                    // сборке она не создастся и **не удалится**, потому что
                    // `remove()` тоже под `DEBUG`. Без ворот она уехала бы
                    // маме первой записью истории.
                    guard SharedDiaryOutgoing.sendable(event) else {
                        log.notice("общий дневник: запись раньше приложения не отправляется")
                        continue
                    }
                    event.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(event.id, in: zone)))
                } else if let dose = ctx.model(for: id) as? DoseRecord {
                    dose.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(dose.id, in: zone)))
                } else if let care = ctx.model(for: id) as? CareTask {
                    care.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(care.id, in: zone)))
                } else if let medication = ctx.model(for: id) as? Medication {
                    medication.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(medication.id, in: zone)))
                } else if let документ = ctx.model(for: id) as? DogDocument {
                    // Документы ездят с 07.10.2026 — подписью, без скана:
                    // в клинике спрашивают номер, на границе срок,
                    // и нужны они тому, кто СЕГОДНЯ один с собакой.
                    документ.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(документ.id, in: zone)))
                } else if let взвешивание = ctx.model(for: id) as? WeightEntry {
                    // Взвешивания ездят с 07.10.2026: тип записи был
                    // объявлен и не создавался ни разу. Доза считается
                    // от веса, и расхождение веса даёт расхождение дозы.
                    взвешивание.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(взвешивание.id, in: zone)))
                } else if let анализ = ctx.model(for: id) as? LabResult {
                    // Медкнижка ездит с 07.10.2026: без неё второй
                    // человек приходил к врачу с пересказом.
                    анализ.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(анализ.id, in: zone)))
                } else if let визит = ctx.model(for: id) as? VetVisit {
                    визит.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(визит.id, in: zone)))
                } else if let диагноз = ctx.model(for: id) as? Diagnosis {
                    диагноз.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(диагноз.id, in: zone)))
                } else if let рецепт = ctx.model(for: id) as? Prescription {
                    рецепт.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(рецепт.id, in: zone)))
                } else if let clinic = ctx.model(for: id) as? Clinic {
                    // Справочник ездит с 07.10.2026: без него второй
                    // человек видел прививку и не видел, где её сделали.
                    clinic.changedAt = now
                    stamped = true
                    changes.append(.saveRecord(SharedDiaryRecords.recordID(clinic.id, in: zone)))
                } else if let dog = ctx.model(for: id) as? Dog {
                    // Профиль ездит с 23.09: без него приглашение вело
                    // в пустую комнату — мама не видела ни собаки,
                    // ни веса, ни того, что идёт лечение.
                    //
                    // **Безымянная НЕ ОТПРАВЛЯЕТСЯ, и это не косметика.**
                    // Замер 08.10.2026 по выгрузке с телефона Виктории:
                    // шестнадцать собак, пятнадцать без клички, и пять
                    // из них несут ОДНО И ТО ЖЕ `changed`
                    // (2026-10-06T07:32:18Z) при трёх разных датах
                    // создания. Один пакетный проход тронул пять строк —
                    // и этот проход наш: `FeedingMigration` на каждом
                    // запуске пишет `dailyNormGrams` всем собакам без
                    // разбора, SwiftData видит изменение, а эта ветка
                    // ставит отметку и кладёт запись в отправку.
                    //
                    // ```
                    // FeedingMigration пишет фантому
                    //   → changedAt = now здесь
                    //   → saveRecord в общую зону
                    //   → пятнадцать пустых собак уезжают маме
                    // ```
                    //
                    // > **Мусор, который уходит от нас к человеку,
                    // > хуже мусора, который лежит у нас.** Свои
                    // > пустые записи мы хотя бы не показываем
                    // > (`Dog.canBeShown`); уехавшие живут в чужом
                    // > хранилище, и там наше правило показа
                    // > не действует.
                    //
                    // Это ровно тот класс, что уже назван про четвёртую
                    // поверхность (`f152078`); здесь он на пятой.
                    //
                    // **Чего эта правка НЕ делает.** Она не объясняет
                    // и не чинит появление фантомов — откуда они
                    // берутся, не установлено: девять записей созданы
                    // в одну секунду 07.10 16:53:36, в ту же секунду,
                    // в которую открылся онбординг, и совпадение времени
                    // связью не является. Решающий замер — проход
                    // онбординга на стёртом симуляторе со счётом `Dog`
                    // после — НЕ СДЕЛАН.
                    //
                    // Ворота — ОБЩИЕ с засевом, а не свои.
                    // `SharedDiaryOutgoing.sendable` зовут две двери
                    // наружу: эта («сохранили → отправили») и засев уже
                    // лежащих записей, который кладёт изменения
                    // в движок напрямую, мимо этой функции. Запрет
                    // в одной двери второй не знает.
                    guard SharedDiaryOutgoing.sendable(dog) else {
                        log.notice("общий дневник: собака без клички не отправляется")
                        continue
                    }
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
            // Отправка профиля может вернуть `nil` — безымянную собаку
            // наружу не отправляем. Решение живёт в самой
            // `SharedDiaryRecords`, а не здесь: этот метод `private`
            // и требует `context` с `outbox`, то есть проверить его
            // тестом нечем. Поверхность без шва — это не
            // «непроверенная», а «непроверяемая», и лечится она
            // переносом решения, а не внимательностью.
            return SharedDiaryRecords.record(dog.payload, base: base, in: recordID.zoneID)
        }
        if let care = try? ctx.fetch(
            FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(care.payload, base: base, in: recordID.zoneID)
        }
        if let medication = try? ctx.fetch(
            FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(medication.payload, base: base, in: recordID.zoneID)
        }
        if let clinic = try? ctx.fetch(
            FetchDescriptor<Clinic>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(clinic.payload, base: base, in: recordID.zoneID)
        }
        if let документ = try? ctx.fetch(
            FetchDescriptor<DogDocument>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(документ.payload, base: base, in: recordID.zoneID)
        }
        if let взвешивание = try? ctx.fetch(
            FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(взвешивание.payload, base: base, in: recordID.zoneID)
        }
        if let анализ = try? ctx.fetch(
            FetchDescriptor<LabResult>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(анализ.payload, base: base, in: recordID.zoneID)
        }
        if let визит = try? ctx.fetch(
            FetchDescriptor<VetVisit>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(визит.payload, base: base, in: recordID.zoneID)
        }
        if let диагноз = try? ctx.fetch(
            FetchDescriptor<Diagnosis>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(диагноз.payload, base: base, in: recordID.zoneID)
        }
        if let рецепт = try? ctx.fetch(
            FetchDescriptor<Prescription>(predicate: #Predicate { $0.id == id })
        ).first {
            return SharedDiaryRecords.record(рецепт.payload, base: base, in: recordID.zoneID)
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
            // **Порядок, а не признак «это собака».** Прежняя редакция
            // сортировала предикатом «слева собака» — он ставит профили
            // вперёд и больше ничего не упорядочивает. С приездом
            // справочника этого мало: дело ухода ссылается на клинику,
            // и приехав раньше неё, оно сошьётся с пустотой, а второй
            // попытки у него не будет до следующей правки.
            //
            // Ранг вместо предиката ещё и честнее перед `sorted`:
            // предикат «слева собака» не задаёт строгого порядка,
            // и устойчивость результата — везение, а не свойство.
            func ранг(_ тип: String) -> Int {
                switch SharedDiary.RecordType(rawValue: тип) {
                case .clinic: 0   // на него ссылаются дела ухода
                case .dog: 1      // на него ссылается всё остальное
                default: 2
                }
            }
            let modifications = changes.modifications.sorted {
                ранг($0.record.recordType) < ранг($1.record.recordType)
            }

            for modification in modifications {
                let record = modification.record
                // Пришедшее с сервера — тоже источник `recordChangeTag`:
                // свою правку этой записи мы пошлём уже поверх неё.
                outbox.remember(record)

                switch SharedDiary.RecordType(rawValue: record.recordType) {
                case .clinic:
                    guard let payload = SharedDiaryRecords.clinicPayload(record) else { continue }
                    SharedDiaryInbox.accept(payload, context: ctx)
                case .dog:
                    guard let payload = SharedDiaryRecords.dogPayload(record) else { continue }
                    SharedDiaryInbox.accept(payload, context: ctx)
                case .care:
                    guard let payload = SharedDiaryRecords.carePayload(record) else { continue }
                    // Клиника сшивается внутри `accept`: там контекст
                    // есть по устройству, и промах по id там же
                    // падает на поиск по имени.
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .medication:
                    guard let payload = SharedDiaryRecords.medicationPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
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
                case .document:
                    guard let payload = SharedDiaryRecords.documentPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .weight:
                    guard let payload = SharedDiaryRecords.weightPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .labResult:
                    guard let payload = SharedDiaryRecords.labResultPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .vetVisit:
                    guard let payload = SharedDiaryRecords.vetVisitPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .diagnosis:
                    guard let payload = SharedDiaryRecords.diagnosisPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
                case .prescription:
                    guard let payload = SharedDiaryRecords.prescriptionPayload(record) else { continue }
                    SharedDiaryInbox.accept(
                        payload, dog: SharedDiaryInbox.dog(forDogID: payload.dogID, context: ctx),
                        context: ctx)
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
                    // Напоминания снимаются ПОСЛЕ слияния, а не по тому,
                    // что приехало: спор решает `SharedDiaryMerge`, и чужая
                    // отметка могла проиграть своей. Спрашиваем ту дозу,
                    // которая теперь лежит у нас, — иначе снимем запрос
                    // по отметке, которая не победила.
                    //
                    // Зачем это здесь, когда есть `снятьНеждущие`. У той
                    // уборки вход один — `.task` главного экрана
                    // (`TodayScreen:430` → `refresh` → `scheduleDoses`),
                    // то есть она срабатывает, когда человек ОТКРОЕТ
                    // приложение. Здесь вход шире: пока приложение
                    // работает, отметка второго человека гасит запрос
                    // в момент приезда.
                    //
                    // **Чего не закрывает ни то, ни другое:** при закрытом
                    // приложении на телефоне не выполняется ничего.
                    // `UIBackgroundModes` с `remote-notification` в манифесте
                    // есть, а `CKSubscription` в коде ноль — право есть,
                    // механизма нет. Это та же причина, что у записей
                    // голосом, которые не уезжают (`:103-107`, `:244`).
                    if let доза = SharedDiaryInbox.доза(payload.id, context: ctx),
                       !доза.ждётОтметки {
                        дозаБольшеНеЖдёт(доза)
                    }
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
