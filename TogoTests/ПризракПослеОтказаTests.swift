import Darwin
import Foundation
import SwiftData
import Testing
@testable import Togo

/// Судьба записи, вставленной до отказа `save()`, когда хранилище
/// СНОВА пишет. Закрывает открытую находку прогона 04.11
/// (`docs/аудит-рефакторинга-2026-11-04.md`).
///
/// **Замер 05.11.2026, iOS 18.6.** Вставка → отказ `save()` → откат →
/// удачный `save` ДРУГОЙ правки → сколько записей в файле:
///
/// ```
/// откат            без выборки между   с любой выборкой между
/// нет                    2                     1
/// delete                 1                     0
/// связь + delete         1                     0
/// rollback()             2                     1
/// ```
///
/// То есть снятая `delete` вставка **уезжает** в следующее сохранение,
/// если между ними никто ничего не выбрал, а не снятая — уезжает
/// ДВАЖДЫ (две строки из одной вставки). Находка 04.11 видела призрака
/// в `ctx.fetch` — и не видела, что эта самая выборка его и убивает:
/// первая выборка после отката ещё возвращает его, следующая — уже нет.
/// Лечит любая выборка, даже чужого типа; `processPendingChanges()`
/// не лечит. Починка — `ModelContext.осестьПослеОтказа`, одна точка
/// в `persist(otherwise:)`.
///
/// **Отсюда главное правило этого файла: между отказом и следующим
/// `save` тест НЕ ДЕЛАЕТ НИ ОДНОЙ ВЫБОРКИ.** Даже ради печати. Выборка
/// здесь — не наблюдение, а лечение, и тест с ней зеленеет на старом коде.
///
/// **Чем ломается запись, и почему не `НеЗаписывающееХранилище`.**
/// Тому нужен отказ НАВСЕГДА (`allowsSave: false`), здесь — отказ,
/// после которого ТОТ ЖЕ контекст снова пишет. Опробовано и отброшено
/// 05.11: чужой `BEGIN EXCLUSIVE` на файле (Core Data ждёт замка минутами,
/// дело висело дольше восьми), переименование файла базы из-под
/// соединения (`save` «проходит», данные теряются — стенд портит предмет).
/// Годным оказался запрет роста файлов процесса, `RLIMIT_FSIZE = 0`,
/// снимаемый обработчиком `SIGXFSZ` на втором отказе записи: `save()`
/// бросает `NSSQLiteErrorDomain 778` мгновенно, а чтение после него
/// уже работает (подбор — у `безЗаписи`).
///
/// **Граница стенда, названная заранее.** Лимит — на весь процесс:
/// тест из соседнего набора, пишущий файл в те же миллисекунды, получит
/// отказ записи не по своей вине. Окно — одно действие. Такой отказ
/// приходит I/O-ошибкой в чужом тесте — искать здесь.
///
/// **Граница предмета.** Этим путём отказ случается на выдаче постоянных
/// идентификаторов (`NSSQLGenerateObjectIDRequestContext` в логе), то есть
/// ДО записи строк. Отказ позже, посреди записи строк, не воспроизведён
/// и не померен.
@Suite("Призрак после отказа сохранения", .serialized)
@MainActor
struct ПризракПослеОтказаTests {

    /// Лимит, который вернёт обработчик сигнала, и счёт сигналов.
    /// Пишутся до установки обработчика и им; набор `.serialized`.
    nonisolated(unsafe) private static var прежнийЛимит = rlimit()
    nonisolated(unsafe) private static var сигналов = 0

    /// Отказ записи, после которого ЧТЕНИЕ уже работает.
    ///
    /// Лимит `RLIMIT_FSIZE = 0` роняет запись в файл с `EFBIG` и шлёт
    /// `SIGXFSZ`; обработчик возвращает прежний лимит на ВТОРОМ сигнале.
    /// Подобрано замером 05.11 (iOS 18.6), отказ приёма в каждом случае:
    ///
    /// ```
    /// снять на 1-м сигнале    save НЕ отказывает: SQLite повторяет запись
    /// снять на 2-м…4-м        save отказал, чтение после него живо
    /// держать всё действие    6 сигналов; ЧТЕНИЕ тоже падает — отказавший
    ///                         save сбрасывает соединение, а открыть его
    ///                         снова под лимитом нельзя («не удалось
    ///                         открыть файл»)
    /// ```
    ///
    /// Нужна средняя строка: при настоящем отказе записи чтение живо
    /// (`allowsSave: false` — `приёмНаОтказе` в `ИсходЗаписиНаОтказеTests`
    /// читает). На нижней строке починка через выборку краснела бы всегда:
    /// стенд мерил бы себя, а не предмет. Покраснеет `стенд()` — число
    /// повторов записи у SQLite сменилось, перемерить порог.
    private static func безЗаписи<T>(_ действие: () throws -> T) rethrows -> T {
        getrlimit(RLIMIT_FSIZE, &прежнийЛимит)
        сигналов = 0
        signal(SIGXFSZ) { _ in
            ПризракПослеОтказаTests.сигналов += 1
            if ПризракПослеОтказаTests.сигналов >= 2 {
                setrlimit(RLIMIT_FSIZE, &ПризракПослеОтказаTests.прежнийЛимит)
            }
        }
        var ноль = прежнийЛимит
        ноль.rlim_cur = 0
        setrlimit(RLIMIT_FSIZE, &ноль)
        defer {
            setrlimit(RLIMIT_FSIZE, &прежнийЛимит)
            signal(SIGXFSZ, SIG_IGN)
        }
        return try действие()
    }

    /// Файловое хранилище с одной записанной собакой.
    private static func хранилище() throws -> (URL, ModelContext, Dog) {
        let каталог = URL.temporaryDirectory.appending(path: "призрак-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
        let файл = каталог.appending(path: "призрак.store")
        let ctx = ModelContext(try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(url: файл, cloudKitDatabase: .none)))
        ctx.autosaveEnabled = false
        let dog = Dog(name: "Стич", weightKg: 12)
        ctx.insert(dog)
        try ctx.save()
        return (файл, ctx, dog)
    }

    /// Записи дневника в файле — свежим контейнером, а не тем контекстом,
    /// который мог что-то держать в памяти. Строки и разные `id` отдельно.
    private static func вФайле(_ файл: URL) throws -> (строк: Int, разныхId: Int) {
        let все = try ModelContext(ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(url: файл, cloudKitDatabase: .none)))
            .fetch(FetchDescriptor<LogEvent>())
        return (все.count, Set(все.map(\.id)).count)
    }

    private static func запись(_ id: UUID) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(), authorName: "Аня",
                     note: nil, outcome: nil, durationSeconds: nil, stoolForm: nil,
                     stoolFlags: [], grams: 65, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil, deletedAt: nil,
                     deletedBy: nil, changedAt: Date())
    }

    /// Удачный `save` другой правки — то, чем в жизни кончается любой
    /// следующий шаг человека. Без выборки перед ним (см. голову файла).
    private static func чужаяПравка(_ ctx: ModelContext, _ dog: Dog) throws {
        dog.name = "Стич второй"
        try ctx.save()
    }

    // MARK: Контроль стенда

    /// Без этого остальные тесты могли бы зеленеть впустую: если лимит
    /// перестанет ронять `save()`, «0 в файле» значило бы «отказа
    /// не было», а не «призрак не уехал». И вторая половина: та же
    /// вставка без отказа обязана дать 1 — иначе «0» отвечал бы про
    /// чтение файла, а не про призрака.
    @Test("Стенд: отказ настоящий, а без отказа вставка ложится в файл")
    func стенд() throws {
        let (_, ctx, dog) = try Self.хранилище()
        let event = LogEvent(kind: .note, date: Date(), authorName: "Аня")
        event.dog = dog
        ctx.insert(event)
        #expect(throws: (any Error).self, "под лимитом save() не отказал — стенд ничего не ломает") {
            try Self.безЗаписи { try ctx.save() }
        }

        let (файл, живой, собака) = try Self.хранилище()
        let другая = LogEvent(kind: .note, date: Date(), authorName: "Аня")
        другая.dog = собака
        живой.insert(другая)
        try Self.чужаяПравка(живой, собака)
        #expect(try Self.вФайле(файл).строк == 1)
    }

    // MARK: Предмет — через настоящий код

    /// Тот самый путь находки 04.11: `accept` отказал, `persist` откатил
    /// вставку `delete`. До 05.11.2026 призрак уезжал следующим `save`.
    @Test("Незаписанный приём не уезжает в следующее удачное сохранение")
    func приёмНеУезжает() throws {
        let (файл, ctx, dog) = try Self.хранилище()

        let исход = Self.безЗаписи {
            SharedDiaryInbox.accept(Self.запись(UUID()), dog: dog, context: ctx)
        }
        try #require(исход == .отказ, "отказа не было — проверять нечего")
        try Self.чужаяПравка(ctx, dog)

        #expect(try Self.вФайле(файл).строк == 0, """
            призрак уехал в следующее удачное сохранение: в дневнике \
            запись, на которую обмен получил «отказ» и привезёт её \
            ещё раз. Откат вставки без выборки после него не доходит \
            до конца — см. `ModelContext.осестьПослеОтказа`
            """)
    }

    /// Места с `persist(otherwise: {})` после вставки (засев, миграции,
    /// расписание доз) откатывать нечего — вставка законна и должна
    /// лечь следующим сохранением. Но лечь ОДИН раз.
    @Test("Вставка, оставленная после отказа, ложится одной строкой, а не двумя")
    func оставленнаяВставкаБезДубля() throws {
        let (файл, ctx, dog) = try Self.хранилище()
        let event = LogEvent(kind: .note, date: Date(), authorName: "Аня")
        event.dog = dog
        ctx.insert(event)

        let записано = Self.безЗаписи { ctx.persistNothingToUndo() }
        try #require(записано == false, "отказа не было — проверять нечего")
        try Self.чужаяПравка(ctx, dog)

        let вФайле = try Self.вФайле(файл)
        #expect(вФайле.строк == 1, """
            одна вставка легла \(вФайле.строк) строками \
            (разных id \(вФайле.разныхId)) — дубль, который уедет \
            и ко второму человеку
            """)
    }

    /// Повтор приёма: `FamilySync.принять` возвращает отказавшую запись
    /// на следующий круг. Запись обязана лечь, и ровно одна.
    @Test("Повтор приёма после отказа кладёт запись ровно один раз")
    func повторПриёма() throws {
        let (файл, ctx, dog) = try Self.хранилище()
        let payload = Self.запись(UUID())

        let первый = Self.безЗаписи { SharedDiaryInbox.accept(payload, dog: dog, context: ctx) }
        try #require(первый == .отказ, "отказа не было — проверять нечего")

        #expect(SharedDiaryInbox.accept(payload, dog: dog, context: ctx) == .принято)
        #expect(try Self.вФайле(файл).строк == 1, "повтор не записал приехавшую запись сам")
        try Self.чужаяПравка(ctx, dog)
        #expect(try Self.вФайле(файл).строк == 1, "после чужого сохранения записей не одна")
    }

    // MARK: Почему починка нужна — поведение самой SwiftData

    /// Голый `delete` без выборки после него. Это не наш код, а замер
    /// SwiftData, ради которого стоит `осестьПослеОтказа`. Покраснеет —
    /// значит на этой ОС SwiftData починили; защиту это не снимает, пока
    /// нижняя граница приложения ниже той ОС (так же, как с `rollback()`
    /// в `Persist.swift`).
    @Test("SwiftData: голый delete после отказа отправляет вставку в следующий save")
    func голыйDeleteУезжает() throws {
        let (файл, ctx, dog) = try Self.хранилище()
        let event = LogEvent(kind: .note, date: Date(), authorName: "Аня")
        event.dog = dog
        ctx.insert(event)
        try #require((try? Self.безЗаписи { try ctx.save() }) == nil, "отказа не было")

        event.dog = nil
        ctx.delete(event)
        try Self.чужаяПравка(ctx, dog)

        #expect(try Self.вФайле(файл).строк == 1)
    }

    /// И запрет на «упрощение» отката до `rollback()`: на iOS 18.6 после
    /// отказа он не снимает вставку, а удваивает её.
    /// `Backup.swift` откатывает восстановление именно им — см. аудит.
    @Test("SwiftData: rollback() после отказа отправляет вставку в следующий save")
    func rollbackУезжает() throws {
        let (файл, ctx, dog) = try Self.хранилище()
        let event = LogEvent(kind: .note, date: Date(), authorName: "Аня")
        event.dog = dog
        ctx.insert(event)
        try #require((try? Self.безЗаписи { try ctx.save() }) == nil, "отказа не было")

        ctx.rollback()
        try Self.чужаяПравка(ctx, dog)

        let вФайле = try Self.вФайле(файл)
        print("ЗАМЕР rollback: строк \(вФайле.строк), разных id \(вФайле.разныхId)")
        #expect(вФайле.строк >= 1)
    }
}
