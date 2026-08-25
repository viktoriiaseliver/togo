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

    static func container(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)?
            .appending(path: "Togo.store")

        // Сначала пробуем iCloud: тогда дневник переживает переустановку
        // и переезд на новый телефон сам, без файлов и без наших серверов.
        let cloud = ModelConfiguration(
            schema: schema,
            url: storeURL ?? defaultStoreURL(),
            cloudKitDatabase: .private(AppIdentifiers.cloudContainer)
        )
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            isUsingCloud = true
            return container
        }

        // Нет прав на iCloud или он выключен — работаем локально и говорим
        // об этом на экране переноса, а не молчим.
        isUsingCloud = false
        log.notice("iCloud недоступен, использую локальное хранилище")
        let local = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            log.error("Не удалось открыть хранилище: \(error.localizedDescription)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    private static func defaultStoreURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "Togo.store")
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
