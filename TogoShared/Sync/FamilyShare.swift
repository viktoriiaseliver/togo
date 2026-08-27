import Foundation
import CloudKit

/// Приглашение в общий дневник.
///
/// Делится не отдельная собака, а зона целиком: у семьи один дневник,
/// и выбирать, какие записи показать мужу, а какие нет, — задача, которой
/// в жизни не существует. Права внутри всё равно решает роль.
///
/// Ссылка одноразовая только по смыслу: CloudKit сам следит, кто
/// её принял, и владелец в любой момент видит участников и может убрать
/// любого.
@MainActor
enum FamilyShare {

    enum ShareError: LocalizedError {
        case noAccount
        case noEntitlement
        case notOwner

        var errorDescription: String? {
            switch self {
            case .noAccount: "Войди в iCloud на телефоне — приглашение живёт там."
            case .noEntitlement: "У этой сборки нет права на iCloud."
            case .notOwner: "Приглашать может только владелец дневника."
            }
        }
    }

    /// Создать (или достать уже созданное) приглашение и вернуть ссылку.
    static func inviteURL(
        dogName: String,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws -> URL {
        guard Persistence.hasCloudEntitlement else { throw ShareError.noEntitlement }
        guard try await container.accountStatus() == .available else { throw ShareError.noAccount }

        let database = container.privateCloudDatabase
        let zoneID = SharedDiaryRecords.zoneID()

        // Зона должна существовать до того, как ею делятся.
        if (try? await database.recordZone(for: zoneID)) == nil {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }

        // Уже поделились раньше — второй раз не создаём: у зоны бывает
        // ровно одна общая ссылка, и новая отрезала бы уже принявших.
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare,
           let url = existing.url {
            return url
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Дневник · \(dogName)"
        // Только по ссылке и только на запись: смысл приглашения в том,
        // чтобы второй человек отмечал, а не смотрел.
        share.publicPermission = .none

        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        guard case .success(let record) = saved.saveResults[shareID],
              let url = (record as? CKShare)?.url
        else { throw ShareError.notOwner }
        return url
    }

    /// Кто уже в дневнике.
    static func participants(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async -> [String] {
        let zoneID = SharedDiaryRecords.zoneID()
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try? await container.privateCloudDatabase.record(for: shareID) as? CKShare
        else { return [] }

        return share.participants.compactMap { participant in
            let name = participant.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter().string(from: $0) }
            let mail = participant.userIdentity.lookupInfo?.emailAddress
            let label = name?.isEmpty == false ? name : mail
            return label ?? nil
        }
    }

    /// Перестать делиться. Записи у приглашённого при этом остаются
    /// его копией — забрать уже показанное CloudKit не умеет, и врать
    /// об этом нельзя.
    static func stopSharing(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws {
        let zoneID = SharedDiaryRecords.zoneID()
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
    }

    /// Принять приглашение по ссылке.
    static func accept(
        _ metadata: CKShare.Metadata,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws {
        _ = try await container.accept(metadata)
    }
}
