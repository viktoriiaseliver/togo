import Foundation
import CloudKit

/// Приглашение в общий дневник.
///
/// Делится не отдельная собака, а зона целиком: у семьи один дневник,
/// и выбирать, какие записи показать мужу, а какие нет, — задача, которой
/// в жизни не существует. Права внутри всё равно решает роль.
///
/// Приглашение — это `CKShare`, а не голая ссылка. У общего дневника
/// `publicPermission = .none`: по адресу входит только тот, кого владелец
/// назвал участником. Назвать его умеет системный лист «Поделиться» в
/// режиме совместной работы (`CKShareTransferRepresentation`): там
/// выбирают маму из контактов, отправляют через Сообщения — и CloudKit
/// сам записывает её в участники. Голая ссылка из `share.url`, разосланная
/// как текст, при `.none` не открывается ни у кого: именно так «ссылку
/// нельзя было получить» превращалось в «ссылку нельзя открыть».
///
/// Владелец в любой момент видит участников и может убрать любого.
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
    /// Осталось для тех, кому нужен адрес как текст (тесты, отладка);
    /// экран отдаёт в лист «Поделиться» сам `CKShare` через `invite`.
    static func inviteURL(
        dogName: String,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws -> URL {
        let share = try await invite(dogName: dogName, container: container)
        guard let url = share.url else { throw ShareError.notOwner }
        return url
    }

    /// Создать (или достать уже созданное) приглашение и вернуть сам `CKShare`.
    static func invite(
        dogName: String,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws -> CKShare {
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
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Дневник · \(dogName)"
        // Только названным людям: смысл приглашения в том, чтобы второй
        // человек отмечал, а не чтобы дневник открывался у любого, кому
        // переслали адрес. Кого назвать — решается в листе «Поделиться».
        share.publicPermission = .none

        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        guard case .success(let record) = saved.saveResults[shareID],
              let created = record as? CKShare
        else { throw ShareError.notOwner }
        return created
    }

    /// Уже созданное приглашение, если оно есть, — ничего не создавая.
    ///
    /// Зачем отдельно от `invite`. Экраны держат приглашение в `@State`,
    /// а `@State` живёт ровно столько, сколько открыт экран. Человек
    /// создавал ссылку, уходил, возвращался — и видел прежнюю кнопку
    /// «Создать приглашение», будто ничего не произошло. Замер 23.09.2026:
    /// сорок четыре захода на «Семью» за девять сессий и ни одного
    /// отправленного приглашения. Путь существовал и не доводился
    /// до конца: каждый заход начинался с нуля.
    ///
    /// Создавать здесь нельзя: экран открывают и те, кто приглашать
    /// не собирался, а `invite` пишет в облако.
    static func existing(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async -> CKShare? {
        guard Persistence.hasCloudEntitlement,
              (try? await container.accountStatus()) == .available else { return nil }
        let zoneID = SharedDiaryRecords.zoneID()
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try? await container.privateCloudDatabase.record(for: shareID) as? CKShare
    }

    /// Короткое имя отказа для журнала действий.
    ///
    /// В журнал не уходит `localizedDescription`: там бывают имя
    /// контейнера, адрес почты участника и кличка собаки — та же красная
    /// линия, что у крошек запуска. Уходит только вид отказа.
    static func причина(_ error: Error) -> String {
        switch error {
        case ShareError.noAccount: "noAccount"
        case ShareError.noEntitlement: "noEntitlement"
        case ShareError.notOwner: "notOwner"
        default: (error as? CKError).map { "ck\($0.errorCode)" } ?? "unknown"
        }
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

extension Notification.Name {
    static let familyShareAccepted = Notification.Name("familyShareAccepted")
}

/// Что происходит после того, как приглашение принято.
///
/// Отдельно от делегата сцены намеренно: делегат — только дверь, его
/// в тест не поставить, а решения проверять надо. Решений здесь два,
/// и оба нельзя забыть. Первое — **запомнить владельца зоны**: без его
/// имени гость пишет отметки в свою личную базу, где их никто
/// не увидит. Второе — поднять обмен, не дожидаясь перезапуска.
@MainActor
enum ShareAcceptance {

    /// Приглашения, которые уже приняли в этом запуске.
    ///
    /// Система стучится дважды — методом сцены и через
    /// `ConnectionOptions` при холодном старте. Второй приём безвреден,
    /// но писать в журнал ошибку о нём незачем.
    private static var handled: Set<String> = []

    static func accept(_ metadata: CKShare.Metadata) {
        let owner = metadata.share.recordID.zoneID.ownerName
        let key = metadata.share.recordID.recordName + "@" + owner
        guard !handled.contains(key) else { return }
        handled.insert(key)

        Task { @MainActor in
            do {
                try await FamilyShare.accept(metadata)
                accepted(ownerName: owner)
            } catch {
                handled.remove(key)
                log.notice("Приглашение не принялось: \(error.localizedDescription)")
            }
        }
    }

    /// Приглашение принято: чей это дневник, включён ли обмен, и кому
    /// об этом сказать.
    ///
    /// Отдельной функцией от `accept` — у неё на входе обычная строка,
    /// а не `CKShare.Metadata`, которую в тесте не собрать.
    static func accepted(ownerName: String) {
        SharedZoneOwner.name = ownerName
        SharedDiarySettings.isOn = true
        NotificationCenter.default.post(name: .familyShareAccepted, object: nil)
    }
}
