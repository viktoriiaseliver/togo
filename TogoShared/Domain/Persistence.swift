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
    /// Нынешняя форма хранилища — она же `TogoSchemaV3`.
    ///
    /// Список моделей переехал в `SchemaVersions.swift` и живёт теперь
    /// в одном месте с прежними версиями: две копии списка разошлись бы,
    /// и план миграции начал бы врать о том, из чего состоит база.
    static let schema = Schema(versionedSchema: TogoSchemaV3.self)

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
        // Симулятор сборкой из App Store не бывает, а чек песочницы в нём
        // создаёт конфигурация StoreKit — судить по нему нельзя. Решает
        // профиль, как и раньше. Без этой ветки прогон тестов уходил
        // в бесконечное восстановление CloudKit без аккаунта
        // («Illegal attempt to register a second handler») и вис.
        return cloudEntitlementGranted(profileExists: true,
                                       receiptExists: false,
                                       entitlements: provisioningEntitlements())
        #else
        let receipt = Bundle.main.appStoreReceiptURL
        return cloudEntitlementGranted(
            profileExists: Bundle.main.url(forResource: "embedded",
                                           withExtension: "mobileprovision") != nil,
            receiptExists: receipt.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
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
    /// Отсутствие профиля само по себе ничего не значит — его нет и
    /// у тестового бандла. Различает их чек покупки: у App Store и
    /// TestFlight он лежит рядом (`sandboxReceipt` у второго), у тестового
    /// хоста его нет. Без этого различения тесты полезли бы в CloudKit.
    static func cloudEntitlementGranted(profileExists: Bool,
                                        receiptExists: Bool,
                                        entitlements: [String: Any]?) -> Bool {
        guard profileExists else { return receiptExists }
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
                StartupLog.note("хранилище: iCloud")
                return container
            }
            StartupLog.note("iCloud не открылся, откатываюсь на локальное")
        } else {
            StartupLog.note("права на iCloud нет — только локально")
        }

        isUsingCloud = false
        let local = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
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
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TogoMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
    static func container() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TogoMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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

        var title: String {
            switch self {
            case .syncing: "Дневник в iCloud"
            case .noAccount: "Войди в iCloud"
            case .restricted: "iCloud ограничен"
            case .unavailable: "iCloud недоступен"
            }
        }

        var detail: String {
            switch self {
            case .syncing:
                "Дневник лежит в твоей приватной библиотеке iCloud и вернётся сам после переустановки или на новом телефоне."
            case .noAccount:
                "Приложение готово переносить записи, но на телефоне нет входа в Apple ID. Пока дневник только здесь — сохрани файл."
            case .restricted:
                "iCloud выключен ограничениями телефона. Дневник хранится только здесь — переносить придётся файлом."
            case .unavailable:
                "Пока дневник хранится только на этом телефоне. Включи iCloud Drive в системных настройках — или пользуйся файлом ниже."
            }
        }

        var isGood: Bool { self == .syncing }
    }

    static func cloudState() async -> CloudState {
        guard isUsingCloud else { return .unavailable }
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
