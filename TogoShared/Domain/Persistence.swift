import Foundation
import SwiftData
import CloudKit
import OSLog

nonisolated enum AppIdentifiers {
    static let appGroup = "group.app.togo.diary"
    static let bundlePrefix = "app.togo.diary"
    static let cloudContainer = "iCloud.app.togo.diary"
    static let urlScheme = "togo"
}

/// Куда человек пишет, если что-то не так.
///
/// **Заменить перед отправкой в App Store.** Ревьюер проверяет адрес
/// поддержки: письмо на несуществующий ящик отскакивает, и это отказ
/// по Guideline 1.5 — не придирка, а прямое основание.
///
/// Собрано в одном месте намеренно: раньше `togo.app` был вписан
/// в пяти файлах, и поменять его, ничего не забыв, было нельзя.
nonisolated enum Contacts {
    /// Общая поддержка. Этот же адрес указывается в App Store Connect.
    ///
    /// Живой ящик, а не домен: `togo.app` нам не принадлежит, письмо ревьюера
    /// на него отскочило бы. Заменено 02.09.2026.
    static let support = "viktoriia.seliver@gmail.com"
    /// Вопросы о данных — по закону нужен отдельный.
    ///
    /// Пока адрес тот же: отдельный ящик заводится вместе с доменом.
    static let privacy = "viktoriia.seliver@gmail.com"

    static func mail(_ address: String, subject: String) -> URL? {
        var components = URLComponents(string: "mailto:\(address)")
        components?.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components?.url
    }
}

nonisolated let log = Logger(subsystem: AppIdentifiers.bundlePrefix, category: "app")

/// Всё считается на телефоне. Аккаунт не нужен — это обещание с первого экрана
/// онбординга, и хранилище устроено так же: локальный файл в общей группе,
/// чтобы виджеты и Live Activity читали те же записи.
nonisolated enum Persistence {
    /// Нынешняя форма хранилища — она же `TogoSchemaV6`.
    ///
    /// **Переведена с V5 на V6 26.10.2026, и это починка аварии.**
    /// V5 ссылалась на живые классы, поэтому `f546719` сменил её форму
    /// под неизменным номером `5.0.0` — и хранилища пяти розданных
    /// сборок перестали опознаваться вовсе
    /// (`SwiftDataError.unknownDataStoreSchema`). V5 заморожена снимком
    /// формы 304, V6 встала на живые классы, стадия между ними
    /// облегчённая. Разбор — шапки обеих версий в `SchemaVersions.swift`.
    ///
    /// Список моделей переехал в `SchemaVersions.swift` и живёт теперь
    /// в одном месте с прежними версиями: две копии списка разошлись бы,
    /// и план миграции начал бы врать о том, из чего состоит база.
    ///
    /// Версия берётся из последней схемы плана, а не пишется здесь
    /// числом: расхождение между «чем открываем» и «что последнее
    /// в плане» — это ровно тот случай, когда форма поменялась,
    /// а версия нет, и хранилище молча не откроется. Сторожит
    /// `SchemaFrozenTests.хранилищеНаПоследней`.
    /// **Переведено на V9 29.10.2026 при сведении двух линий.**
    /// V8 стала снимком (она уехала людям в сборке 284), живые классы
    /// ушли в V9 вместе с `Medication.startedAt`. Пока здесь стояла V8,
    /// контейнер открывался ПО СНИМКУ, и SwiftData роняло приложение
    /// на первом же чтении: «Failed to cast model Togo.Dog … to Dog» —
    /// снимочный `TogoSchemaV8.Dog` и живой `Dog` для него разные типы.
    /// Девять перезапусков раннера подряд, ни одного выполненного теста.
    ///
    /// > **Заморозка версии и перевод контейнера — ОДНА правка, а не
    /// > две.** Разнести их во времени нельзя: между ними приложение
    /// > не открывает собственную базу.
    static let schema = Schema(versionedSchema: TogoSchemaV10.self)

    /// Удалось ли открыть хранилище в iCloud. Экран переноса показывает
    /// это человеку: обещать синхронизацию, которой нет, нельзя.
    nonisolated(unsafe) private(set) static var isUsingCloud = false

    /// Хранилище открылось только в памяти. Записи в нём не переживут
    /// перезапуск — и человек обязан это знать, а не думать, что дневник
    /// просто опустел.
    nonisolated(unsafe) private(set) static var isEphemeral = false

    /// Есть ли у сборки право на iCloud.
    ///
    /// Проверяем в рантайме, а не флагом сборки: бесплатная команда
    /// разработчика iCloud не выдаёт, и обращение к CloudKit без права
    /// роняет приложение на устройстве — в симуляторе то же самое лишь
    /// пишет в лог. Одна проверка избавляет от целого класса падений,
    /// которые видно только на живом телефоне.
    ///
    /// Права лежат в профиле подписи внутри бандла. `SecTask` на iOS
    /// недоступен, поэтому читаем профиль: он обёрнут в CMS, но нужный
    /// plist лежит внутри открытым текстом.
    static var hasCloudEntitlement: Bool {
        #if targetEnvironment(simulator)
        // Симулятор сборкой из App Store не бывает: профиля в нём нет
        // никогда, и без этой ветки прогон тестов уходил в бесконечное
        // восстановление CloudKit без аккаунта («Illegal attempt to
        // register a second handler») и вис.
        return cloudEntitlementGranted(profileExists: true,
                                       entitlements: provisioningEntitlements())
        #else
        return cloudEntitlementGranted(
            profileExists: Bundle.main.url(forResource: "embedded",
                                           withExtension: "mobileprovision") != nil,
            entitlements: provisioningEntitlements())
        #endif
    }

    /// Решение отдельно от чтения бандла: `Bundle.main` в тест не подставить,
    /// а проверять надо именно решение — оно выключало iCloud у всех, кто
    /// ставил приложение из TestFlight.
    ///
    /// **Профиля нет — это не «права нет».** `embedded.mobileprovision`
    /// лежит только в сборках для разработки и ad hoc. У сборок из App Store
    /// и TestFlight Apple снимает его при обработке, а права остаются
    /// в подписи кода, прочитать которую с iOS нечем. Прежняя проверка
    /// читала отсутствие профиля как отсутствие права и выключала iCloud
    /// ровно там, где он нужен: журнал запуска с телефона 22.09 на всех
    /// трёх запусках TestFlight писал «права на iCloud нет — только
    /// локально», хотя в профиле архива стоит `iCloud.app.togo.diary`,
    /// а на App ID возможность ICLOUD включена.
    ///
    /// Бесплатная команда разработчика при этом по-прежнему отсекается:
    /// у её сборок профиль **есть**, просто без контейнеров iCloud.
    ///
    /// Симулятор отсекается не здесь, а в `hasCloudEntitlement`: на устройстве
    /// отсутствие профиля значит ровно одно — сборка пришла из App Store
    /// или TestFlight.
    ///
    /// Различать их по чеку покупки (`appStoreReceiptURL`) я пробовала
    /// 22.09 — не работает: свойство устарело, файла на новых iOS нет,
    /// и сборка 80 сказала четверым «У этой сборки нет права на iCloud»
    /// ровно поэтому. Признак, который нельзя проверить на устройстве
    /// до раздачи, проверять и не стоит.
    static func cloudEntitlementGranted(profileExists: Bool,
                                        entitlements: [String: Any]?) -> Bool {
        guard profileExists else { return true }
        guard let entitlements else { return false }
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]
        return (containers ?? []).isEmpty == false
    }

    /// Убрать хранилище, оставшееся от прежней сборки.
    ///
    /// В одной из версий путь к базе был задан явно (`Togo.store`),
    /// а потом снова стал стандартным (`default.store`). На живом телефоне
    /// от этого остался мёртвый файл на полтора мегабайта.
    ///
    /// Удаляем **только** если в текущем хранилище есть собака: иначе есть
    /// риск, что данные как раз в старом файле, и его надо не стирать,
    /// а читать. Молча терять записи нельзя ни при каких обстоятельствах.
    @MainActor
    static func removeLegacyStoreIfSafe(context: ModelContext) {
        let hasData = ((try? context.fetch(FetchDescriptor<Dog>()))?.isEmpty == false)
        guard hasData else { return }

        let support = URL.applicationSupportDirectory
        let legacy = ["Togo.store", "Togo.store-shm", "Togo.store-wal"]
            .map { support.appending(path: $0) }

        // `URL.path()` возвращает путь с процентным кодированием, а в нём
        // есть пробел: «Application%20Support». Файл по такому пути
        // не находится, и уборка молча не делала ничего.
        guard FileManager.default.fileExists(atPath: legacy[0].path(percentEncoded: false)) else { return }
        for url in legacy {
            try? FileManager.default.removeItem(at: url)
        }
        StartupLog.note("убрано хранилище прежней сборки")
    }

    private static func provisioningEntitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<plist"),
              let end = text.range(of: "</plist>")
        else { return nil }

        let plist = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plist.data(using: .isoLatin1),
              let profile = try? PropertyListSerialization
                  .propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }

        return profile["Entitlements"] as? [String: Any]
    }

    /// Хранилище для тех, кто приходит не через экраны.
    ///
    /// Сценарии, Siri, кнопка «Действие» и кнопки на живой активности
    /// выполняются в процессе приложения, но без его `@Environment`.
    /// Приложение кладёт сюда тот самый контейнер, который открыло само:
    /// два контейнера на одну базу — это две правды.
    nonisolated(unsafe) static var shared: ModelContainer?

    /// Хранилище для приложения. Никогда не падает: если открыть не вышло,
    /// возвращает nil, и приложение показывает человеку экран с объяснением,
    /// а не исчезает с экрана без единого слова.
    static func appContainer() -> ModelContainer? {
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
        StartupLog.note(groupURL == nil ? "общей группы нет — локально" : "общая группа есть")
        return openContainer(storeURL: groupURL?.appending(path: "Togo.store"),
                             allowCloud: hasCloudEntitlement)
    }

    /// Та же лестница, что у `appContainer()`, но с явным хранилищем.
    ///
    /// Путь и право на iCloud вынесены в аргументы не ради красоты:
    /// `appContainer()` берёт их из общей группы и профиля подписи, а значит
    /// проверить его поведение на конкретной базе было нельзя вовсе — ни один
    /// тест не мог подсунуть ему хранилище прежней или неизвестной формы.
    /// Решение «что показать человеку, когда хранилище не открылось» жило
    /// в коде, до которого тест не дотягивался.
    static func openContainer(storeURL: URL?, allowCloud: Bool) -> ModelContainer? {
        StartupLog.note("открываю хранилище")
        // Сбрасываем на входе, а не на каждой ветке: успешная ветка iCloud
        // его не трогала вовсе, и при повторном открытии там оставалось
        // `true` от прошлого раза — плашка «записи не сохраняются» висела бы
        // поверх исправного хранилища.
        isEphemeral = false

        // iCloud пробуем, только если право на него действительно выдано.
        if allowCloud, let storeURL {
            StartupLog.note("право на iCloud есть, пробую")
            let cloud = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private(AppIdentifiers.cloudContainer)
            )
            if let container = try? ModelContainer(for: schema,
                                                   migrationPlan: TogoMigrationPlan.self,
                                                   configurations: cloud) {
                isUsingCloud = true
                // Литерала здесь нет нарочно: по этой строке экран
                // отказа решает, можно ли советовать переустановку.
                // Два места, пишущих и читающих одну мысль разными
                // литералами, расходятся на второй правке — а ценой
                // расхождения тут будет чужой дневник.
                StartupLog.note(StorageFailureAdvice.признакОблака)
                return container
            }
            StartupLog.note("iCloud не открылся, откатываюсь на локальное")
        } else {
            // Почему нет — половина ответа. 22.09 сборка 80 сказала это
            // четверым, и выяснять причину пришлось догадками. Теперь
            // ветка видна сразу: профиль есть и в нём нет контейнеров —
            // это бесплатная команда; профиля нет — сюда попадать вообще
            // не должно, и если попали, врёт разбор, а не мир.
            let профиль = Bundle.main.url(forResource: "embedded",
                                          withExtension: "mobileprovision") != nil
            StartupLog.note("права на iCloud нет — только локально (профиль: \(профиль ? "есть" : "нет"))")
        }

        isUsingCloud = false
        // `cloudKitDatabase: .none` — ЯВНО, и это не перестраховка.
        //
        // **Замерено 08.10.2026 на отказе стенда, который трижды сорвал
        // прогон на вершине.** Без этого параметра ветка называлась
        // локальной и локальной НЕ БЫЛА:
        //
        // ```
        // «права на iCloud нет — только локально»   × 8   наше решение
        // «хранилище: локальное»                    × 6   наша запись
        // NSCloudKitMirroringDelegate               × 182  что происходило
        // CKAccountStatusNoAccount                  × 21
        // «The store was removed before the mirroring
        //  delegate could recover»
        // → NSInternalInconsistencyException
        //   'No eligible connection available'      × 8   смерть
        // ```
        //
        // Стек называет подсистему прямо: `NSManagedObjectContext save:`
        // → `NSSQLCoreDispatchManager routeStoreRequest:`
        // → `NSSQLDefaultConnectionManager handleStoreRequest:`.
        // Процесс в строках — `Togo`, не раннер; `ActivityKit`
        // и `WidgetKit` в стеке не встречаются вовсе.
        //
        // > **Ветка отката называлась локальной и локальной не была.**
        // > Решение принималось верно, в исполнение приводилось не то.
        //
        // Почему так вышло: право на iCloud в бандле есть
        // (`Togo.entitlements:9`), а `ModelConfiguration(schema:url:)`
        // без `cloudKitDatabase` зеркалирование не отключает — это
        // измерено 182 вхождениями делегата при шести строках
        // «локальное», а не выведено из документации.
        //
        // `hasCloudEntitlement` заведён РОВНО против этого класса: в его
        // комментарии стоит «без ветки симулятора прогон уходил
        // в бесконечное восстановление CloudKit без аккаунта и вис».
        // Починили решение и не починили исполнение.
        let local = storeURL.map {
            ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none)
        } ?? ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema,
                                               migrationPlan: TogoMigrationPlan.self,
                                               configurations: local)
            isEphemeral = false
            StartupLog.note("хранилище: локальное")
            return container
        } catch {
            StartupLog.note("локальное не открылось: \(error)")
        }

        // Последняя попытка — в памяти, и она законна ровно в одном случае:
        // когда терять нечего.
        //
        // **Почему проверяем файл, а не разбираем ошибку.** Причин, по которым
        // хранилище не открылось, много, и различать их по тексту ошибки Apple
        // — значит зависеть от текста, который нам не принадлежит. Но решение
        // от причины и не зависит: если файл дневника на диске есть, показывать
        // поверх него пустое хранилище нельзя ни при какой причине. Человек
        // увидел бы онбординг чистой установки — `AppRoot` показывает его,
        // когда собак ноль, — и решил бы, что дневника больше нет.
        //
        // Чаще всего сюда приводит форма хранилища, которой нет в плане
        // миграции: номер сборки — это число коммитов, поэтому любая дневная
        // сборка с промежуточного коммита оставляет на телефоне такую форму,
        // а в плане снимка три. Открыть её нечем — и это нормально;
        // ненормально было молчать об этом.
        if let storeURL,
           FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) {
            StartupLog.note("файл дневника есть, но не открылся — «Дневник не открылся»")
            isEphemeral = false
            return nil
        }

        // Файла нет — значит это первый запуск или чистая установка, и терять
        // нечего. Дневник не сохранится, но человек увидит приложение
        // и сможет выгрузить то, что запишет; про это говорит плашка
        // на главном экране.
        //
        // `cloudKitDatabase: .none` — ЯВНО, по той же причине, что
        // у локальной ветки выше, и это НЕ перестраховка: см. замер
        // 25.10.2026 у `container()` ниже. Хранилище в памяти
        // зеркалирование не отключает.
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TogoMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema,
                                                   isStoredInMemoryOnly: true,
                                                   cloudKitDatabase: .none)
            )
            isEphemeral = true
            StartupLog.note("хранилище: в памяти, записи не сохранятся")
            return container
        } catch {
            StartupLog.note("не открылось ничего: \(error)")
            return nil
        }
    }

    /// Хранилище в памяти — для превью и тестов.
    ///
    /// Аргумент `inMemory` здесь был всегда, но ни на что не влиял:
    /// хранилище получалось в памяти и при `false`. Обещание, которое
    /// не выполняется, хуже отсутствующего — поэтому его больше нет.
    ///
    /// **`cloudKitDatabase: .none` — ЯВНО, и это замер 25.10.2026,
    /// а не перестраховка.** Сторож `ОткатБезОблакаTests` до этого дня
    /// пропускал любую конфигурацию со словом `isStoredInMemoryOnly`
    /// с доводом «в памяти облака нет по устройству: хранилища на диске
    /// нет, зеркалить нечего» — и сам назвал условие, при котором довод
    /// перестаёт быть верным: «если в логе прогона с ним появится
    /// `NSCloudKitMirroringDelegate`». Условие проверено грепом по логу
    /// одного `make unit` (`unit-20261025-144557-98906.log`):
    ///
    /// ```
    /// разных NSCloudKitMirroringDelegate за прогон        213
    /// из них с названным хранилищем                        24, ВСЕ file:///dev/null
    /// строк «store was removed …»                         770
    /// адрес базы приложения (App Group) в тех же строках    0  ← контроль
    /// ```
    ///
    /// `file:///dev/null` — это и есть хранилище в памяти. То есть
    /// довод был ложен, а его собственный опровергатель был записан
    /// рядом и не запускался ни разу.
    ///
    /// Чем это платится: каждый такой делегат не находит учётной записи
    /// iCloud, не восстанавливается и **убирает хранилище
    /// из координатора**. Контекст при этом жив, у `mainContext`
    /// автосохранение включено по устройству SwiftData, и его таймер
    /// падает в `-[ModelContext checkAutosaveConditions]` с `brk #1`.
    /// Разбор — в журнале за 25.10.2026.
    static func container() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TogoMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema,
                                                   isStoredInMemoryOnly: true,
                                                   cloudKitDatabase: .none)
            )
        } catch {
            // Хранилище в памяти не открывается только если сломана схема,
            // а это ошибка сборки, а не устройства: падать здесь правильно.
            fatalError("Схема не собирается: \(error)")
        }
    }

    /// Хранилище настроено на iCloud — это ещё не значит, что синхронизация
    /// идёт: без входа в Apple ID она молча не работает. Экран переноса
    /// показывает именно это состояние, а не «включено».
    enum CloudState: Sendable {
        case syncing
        case noAccount
        case restricted
        case unavailable

        /// Право на iCloud не выдано самой сборке.
        ///
        /// Отдельно от `unavailable`, и это не педантизм. `unavailable`
        /// советовал «включи iCloud Drive в системных настройках» —
        /// совет, который в этом случае не помогает ничем: настройка
        /// у человека уже включена, а дело в подписи сборки. Мы знаем,
        /// какой это случай (`hasCloudEntitlement`), и отвечать одним
        /// текстом на три разные причины значит отправлять человека
        /// чинить не то.
        ///
        /// 22.09.2026 сборка 80 сказала «iCloud недоступен» четверым,
        /// и причину выясняли догадками.
        case noEntitlement

        /// Открыть хранилище с зеркалом iCloud не вышло, хотя право
        /// есть и аккаунт на месте. Редкий случай, и до сих пор он
        /// молчал целиком: `isUsingCloud` становился `false`, дневник
        /// открывался локально, и человек считал, что записи уезжают.
        case openFailed

        var title: String {
            switch self {
            case .syncing: String(localized: "Дневник в iCloud")
            case .noAccount: String(localized: "Войди в iCloud")
            case .restricted: String(localized: "iCloud ограничен")
            case .unavailable: String(localized: "iCloud недоступен")
            case .noEntitlement: "Эта сборка без iCloud"
            case .openFailed: "iCloud не открылся"
            }
        }

        var detail: String {
            switch self {
            case .syncing:
                String(localized: "Дневник лежит в твоей приватной библиотеке iCloud и вернётся сам после переустановки или на новом телефоне.")
            case .noAccount:
                String(localized: "Приложение готово переносить записи, но на телефоне нет входа в Apple ID. Пока дневник только здесь — сохрани файл.")
            case .restricted:
                String(localized: "iCloud выключен ограничениями телефона. Дневник хранится только здесь — переносить придётся файлом.")
            case .unavailable:
                String(localized: "Пока дневник хранится только на этом телефоне. Включи iCloud Drive в системных настройках — или пользуйся файлом ниже.")
            case .noEntitlement:
                "Дело не в твоих настройках: права на iCloud нет у самой сборки. Записи целы и лежат на этом телефоне — сохрани файл, и они вернутся в следующей сборке."
            case .openFailed:
                "Право есть и вход в Apple ID есть, а библиотека не открылась — записи сейчас только на этом телефоне и в iCloud не уезжают. Перезапусти приложение; не поможет — сохрани файл и напиши в поддержку."
            }
        }

        var isGood: Bool { self == .syncing }
    }

    static func cloudState() async -> CloudState {
        // Разбор «почему не iCloud» идёт от того, что мы знаем точно,
        // к тому, о чём догадываемся. Права нет — ответ известен, и
        // спрашивать систему незачем. Право есть, аккаунт есть,
        // а зеркала нет — единственный случай, который до 23.09.2026
        // не говорил о себе ничего.
        guard isUsingCloud else {
            guard hasCloudEntitlement else { return .noEntitlement }
            switch try? await CKContainer(identifier: AppIdentifiers.cloudContainer)
                .accountStatus() {
            case .some(.available): return .openFailed
            case .some(.noAccount): return .noAccount
            case .some(.restricted): return .restricted
            default: return .unavailable
            }
        }
        do {
            switch try await CKContainer(identifier: AppIdentifiers.cloudContainer).accountStatus() {
            case .available: return .syncing
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            default: return .unavailable
            }
        } catch {
            log.notice("Статус iCloud неизвестен: \(error.localizedDescription)")
            return .unavailable
        }
    }
}
