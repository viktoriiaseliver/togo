import Foundation
import SwiftData
import CloudKit
import OSLog

nonisolated enum AppIdentifiers {
    static let appGroup = "group.app.togo.diary"
    static let bundlePrefix = "app.togo.diary"
    static let morningBriefTask = "app.togo.diary.morning-brief"
    static let cloudContainer = "iCloud.app.togo.diary"
    static let urlScheme = "togo"
}

nonisolated let log = Logger(subsystem: AppIdentifiers.bundlePrefix, category: "app")

/// Всё считается на телефоне. Аккаунт не нужен — это обещание с первого экрана
/// онбординга, и хранилище устроено так же: локальный файл в общей группе,
/// чтобы виджеты и Live Activity читали те же записи.
nonisolated enum Persistence {
    static let schema = Schema([
        Dog.self,
        DogDocument.self,
        HeatRecord.self,
        FoodStock.self,
        LogEvent.self,
        CareTask.self,
        Medication.self,
        DoseRecord.self,
        WeightEntry.self,
        TrainingStep.self,
        TrainingSession.self,
        ProcedureSkill.self,
        FamilyMember.self,
        Episode.self,
        Trip.self,
    ])

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
        guard let entitlements = provisioningEntitlements() else { return false }
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

        guard FileManager.default.fileExists(atPath: legacy[0].path()) else { return }
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

    /// Хранилище для приложения. Никогда не падает: если открыть не вышло,
    /// возвращает nil, и приложение показывает человеку экран с объяснением,
    /// а не исчезает с экрана без единого слова.
    static func appContainer() -> ModelContainer? {
        StartupLog.note("открываю хранилище")

        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
        let storeURL = groupURL?.appending(path: "Togo.store")
        StartupLog.note(groupURL == nil ? "общей группы нет — локально" : "общая группа есть")

        // iCloud пробуем, только если право на него действительно выдано.
        if hasCloudEntitlement, let storeURL {
            StartupLog.note("право на iCloud есть, пробую")
            let cloud = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .private(AppIdentifiers.cloudContainer)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
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
            let container = try ModelContainer(for: schema, configurations: local)
            isEphemeral = false
            StartupLog.note("хранилище: локальное")
            return container
        } catch {
            StartupLog.note("локальное не открылось: \(error)")
        }

        // Последняя попытка — в памяти. Дневник не сохранится, но человек
        // хотя бы увидит приложение и сможет выгрузить то, что запишет.
        do {
            let container = try ModelContainer(
                for: schema,
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
    static func container(inMemory: Bool = true) -> ModelContainer {
        try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
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
            case .syncing: "iCloud синхронизирует"
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
                "Приложение готово синхронизировать, но на устройстве не выполнен вход в Apple ID. Пока дневник только здесь — сохрани файл."
            case .restricted:
                "iCloud выключен ограничениями устройства. Дневник хранится только здесь — переносить придётся файлом."
            case .unavailable:
                "Пока дневник хранится только на этом устройстве. Включи iCloud Drive в системных настройках — или пользуйся файлом ниже."
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
