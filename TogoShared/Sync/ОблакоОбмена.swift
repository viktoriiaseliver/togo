import CloudKit

/// Граница обмена с CloudKit — то, что `FamilyShare` спрашивает у облака.
///
/// Заведено 04.11.2026, пачка 3 `docs/аудит-рефакторинга-2026-11-04.md`.
/// До этого в проекте не было ни одного `protocol`, и пути отказа
/// приглашения и ролей проверить было нечем: каждое место принимало
/// `CKContainer`, а у него нет подмены. Пачка 1 различила «не прочитали»
/// и «пусто» в трёх местах `FamilyShare` — без этого шва ни одно из трёх
/// не держится тестом.
///
/// **Одна забота на протокол.** `ОблакоОбмена` — контейнер (аккаунт,
/// личная и общая базы, приём приглашения), `БазаОбмена` — одна база.
/// Боевые реализации — сами `CKContainer` и `CKDatabase` через
/// расширения ниже; параметры `container:` в `FamilyShare` сменили
/// только тип, умолчание прежнее.
///
/// Изоляция: `@MainActor`, как и весь `TogoShared` (ключ проектный,
/// у виджета тот же — `Togo/CLAUDE.md`, «▸ Разработке»). Облачные
/// вызовы асинхронные и главного потока не держат.
protocol ОблакоОбмена {
    func accountStatus() async throws -> CKAccountStatus
    func userRecordID() async throws -> CKRecord.ID
    var личнаяБаза: any БазаОбмена { get }
    var общаяБаза: any БазаОбмена { get }
    func принятьПриглашение(_ metadata: CKShare.Metadata) async throws
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata
}

/// Одна база CloudKit — ровно те вызовы, которыми пользуется `FamilyShare`.
protocol БазаОбмена {
    func record(for recordID: CKRecord.ID) async throws -> CKRecord
    func recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone
    func save(_ zone: CKRecordZone) async throws -> CKRecordZone
    /// Без `savePolicy` и `atomically`: `FamilyShare` их не задаёт,
    /// и боевая реализация передаёт умолчания CloudKit.
    func изменить(
        saving: [CKRecord], deleting: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]
}

extension CKContainer: ОблакоОбмена {
    var личнаяБаза: any БазаОбмена { privateCloudDatabase }
    var общаяБаза: any БазаОбмена { sharedCloudDatabase }

    func принятьПриглашение(_ metadata: CKShare.Metadata) async throws {
        _ = try await accept(metadata)
    }
}

extension CKDatabase: БазаОбмена {
    func изменить(
        saving: [CKRecord], deleting: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        try await modifyRecords(saving: saving, deleting: deleting).saveResults
    }
}
