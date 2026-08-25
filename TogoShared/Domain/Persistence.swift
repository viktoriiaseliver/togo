import Foundation
import SwiftData
import OSLog

nonisolated enum AppIdentifiers {
    static let appGroup = "group.app.togo.diary"
    static let bundlePrefix = "app.togo.diary"
    static let morningBriefTask = "app.togo.diary.morning-brief"
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

    static func container(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        let configuration: ModelConfiguration
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) {
            configuration = ModelConfiguration(
                schema: schema,
                url: groupURL.appending(path: "Togo.store")
            )
        } else {
            // App Group недоступна (симулятор без профиля) — работаем в песочнице приложения.
            log.notice("App Group недоступна, использую локальное хранилище")
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            log.error("Не удалось открыть хранилище: \(error.localizedDescription)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }
}
