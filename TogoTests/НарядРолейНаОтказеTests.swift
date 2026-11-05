import CloudKit
import Foundation
import Testing
@testable import Togo

/// Подделка облака для `FamilyShare` — через шов `ОблакоОбмена`
/// (`TogoShared/Sync/ОблакоОбмена.swift`).
///
/// **Держит столько же сущностей, сколько система:** словарь записей
/// по id и журнал всех сохранений, а не флаг «сохраняли». Подделка
/// с одним флагом не отличила бы «записали поверх» от «записали своё».
@MainActor
final class ПоддельнаяБаза: БазаОбмена {
    var записи: [CKRecord.ID: CKRecord] = [:]
    /// Отказ чтения — для пути «не прочитали»; `nil` — читается честно.
    var отказЧтения: CKError?
    private(set) var сохранено: [[CKRecord]] = []

    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        if let отказЧтения { throw отказЧтения }
        // По имени записи, а не по полному id: зона зависит от глобального
        // признака владельца, который параллельные наборы ставят временно.
        // Имя у общей записи зоны одно — `CKRecordNameZoneWideShare`.
        guard let запись = записи.values.first(where: {
            $0.recordID.recordName == recordID.recordName
        }) else { throw CKError(.unknownItem) }
        return запись
    }

    func recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        CKRecordZone(zoneID: zoneID)
    }

    func save(_ zone: CKRecordZone) async throws -> CKRecordZone { zone }

    func изменить(
        saving: [CKRecord], deleting: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        сохранено.append(saving)
        for запись in saving { записи[запись.recordID] = запись }
        for id in deleting { записи[id] = nil }
        return Dictionary(uniqueKeysWithValues: saving.map { ($0.recordID, .success($0)) })
    }
}

@MainActor
final class ПоддельноеОблако: ОблакоОбмена {
    let база = ПоддельнаяБаза()
    func accountStatus() async throws -> CKAccountStatus { .available }
    func userRecordID() async throws -> CKRecord.ID { CKRecord.ID(recordName: "_владелец") }
    var личнаяБаза: any БазаОбмена { база }
    var общаяБаза: any БазаОбмена { база }
    func принятьПриглашение(_ metadata: CKShare.Metadata) async throws {}
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        throw CKError(.unknownItem)
    }
}

/// Пачка 1 `docs/аудит-рефакторинга-2026-11-04.md`: правка наряда ролей
/// различает «наряда нет» и «наряд не прочитали». До 04.11.2026 оба
/// давали пустой наряд, и запись затирала роли всех остальных одной новой.
@Suite("Наряд ролей: «не прочитали» не равно «пусто»")
@MainActor
struct НарядРолейНаОтказеTests {

    /// Share с уже записанным нарядом — адрес берётся тот же, что ищет
    /// `FamilyShare` (подделка отвечает по id, поэтому важен адрес).
    private static func облакоС(полем: String?) -> (ПоддельноеОблако, CKShare) {
        let облако = ПоддельноеОблако()
        let зона = SharedZoneRouting.zone(owner: nil)
        let share = CKShare(recordZoneID: зона)
        if let полем { share[РолиВОбмене.полеНаряда] = полем }
        облако.база.записи[share.recordID] = share
        return (облако, share)
    }

    private static let мама = НазначеннаяРоль(роль: .caregiver)

    @Test("Записанный наряд дополняется, а не заменяется")
    func дополняет() async throws {
        let прежний = НарядРолей(поУчастникам: ["_мама": Self.мама])
        let (облако, share) = Self.облакоС(полем: РолиВОбмене.закодировать(прежний))

        try await FamilyShare.изменитьНаряд(container: облако, гость: false) {
            $0.новичкам = НазначеннаяРоль(роль: .observer)
        }

        let стало = РолиВОбмене.разобрать(share[РолиВОбмене.полеНаряда] as? String)
        #expect(стало?.поУчастникам["_мама"] == Self.мама,
                "роль мамы стёрта новой правкой — ровно дефект до 04.11.2026")
        #expect(стало?.новичкам == НазначеннаяРоль(роль: .observer))
        #expect(облако.база.сохранено.count == 1)
    }

    @Test("Нечитаемый наряд не переписывается своим")
    func нечитаемыйНеТрогаем() async throws {
        let (облако, share) = Self.облакоС(полем: "{не json")

        await #expect(throws: (any Error).self) {
            try await FamilyShare.изменитьНаряд(container: облако, гость: false) {
                $0.новичкам = НазначеннаяРоль(роль: .observer)
            }
        }
        #expect(облако.база.сохранено.isEmpty, "нечитаемое поле перезаписано пустым нарядом")
        #expect(share[РолиВОбмене.полеНаряда] as? String == "{не json")
    }

    @Test("Сетевой отказ чтения — отказ, а не пустой наряд")
    func сетевойОтказ() async throws {
        let (облако, _) = Self.облакоС(полем: РолиВОбмене.закодировать(
            НарядРолей(поУчастникам: ["_мама": Self.мама])))
        облако.база.отказЧтения = CKError(.networkFailure)

        await #expect(throws: (any Error).self) {
            try await FamilyShare.изменитьНаряд(container: облако, гость: false) {
                $0.новичкам = НазначеннаяРоль(роль: .observer)
            }
        }
        #expect(облако.база.сохранено.isEmpty, """
            при сетевом отказе ушла запись — до 04.11.2026 это был пустой \
            наряд поверх живого
            """)
    }

    @Test("Пустое поле — законно пустой наряд, правка ложится")
    func пустоеПоле() async throws {
        let (облако, share) = Self.облакоС(полем: nil)

        try await FamilyShare.изменитьНаряд(container: облако, гость: false) {
            $0.поУчастникам["_мама"] = Self.мама
        }

        let стало = РолиВОбмене.разобрать(share[РолиВОбмене.полеНаряда] as? String)
        #expect(стало?.поУчастникам == ["_мама": Self.мама])
    }

    @Test("Гость наряд не правит — и в облако не ходит")
    func гость() async throws {
        let (облако, _) = Self.облакоС(полем: nil)
        облако.база.отказЧтения = CKError(.networkFailure)

        await #expect(throws: FamilyShare.ShareError.self) {
            try await FamilyShare.изменитьНаряд(container: облако, гость: true) { _ in }
        }
        #expect(облако.база.сохранено.isEmpty)
    }
}
