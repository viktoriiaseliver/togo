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

    /// Почему приглашение не вышло — по причинам, а не одним текстом.
    ///
    /// **До 05.10 причин было три, а мест, бросавших `notOwner`, — тоже
    /// три, и две из них не про владельца.** Ссылка ещё не выдана
    /// облаком и CloudKit отказался сохранить запись одинаково
    /// превращались в «Приглашать может только владелец дневника» —
    /// совет, которому нельзя последовать, потому что человек и так
    /// владелец. Он будет искать у себя права, которых не терял.
    ///
    /// > Это та самая ступень, что уже чинилась в `Persistence`
    /// > (пять причин вместо одной): **сообщение, покрывающее несколько
    /// > причин одним текстом, даёт совет, неверный для большинства
    /// > из них.** Оно хуже молчания: молчание заставляет спросить,
    /// > неверный совет — попробовать и увериться.
    ///
    /// Второй раз это место чинится потому, что правило чинили
    /// на одной поверхности из двух: `Persistence` знает пять причин
    /// с 23.09, `FamilyShare` всё это время знал три.
    enum ShareError: LocalizedError {
        case noAccount
        case noEntitlement
        /// Ты участник, а не владелец: делиться может только он.
        case notOwner
        /// Запись общего доступа создана, но адрес облако ещё не выдало.
        /// Не отказ: через миг он появится.
        case linkNotReady
        /// CloudKit отказался сохранить запись общего доступа.
        /// Код отказа несём с собой: без него «что-то пошло не так».
        case saveFailed(code: Int?)

        var errorDescription: String? {
            switch self {
            case .noAccount:
                String(localized: "Войди в iCloud на телефоне — приглашение живёт там.")
            case .noEntitlement:
                String(localized: "У этой сборки нет права на iCloud.")
            case .notOwner:
                String(localized: "Приглашать может только владелец дневника.")
            case .linkNotReady:
                // Совета «проверь настройки» здесь нарочно нет: проверять
                // нечего, всё уже верно. Единственное верное действие —
                // подождать, и мы говорим именно его.
                String(localized: "Приглашение уже создано, облако ещё не выдало адрес. Попробуй через несколько секунд.")
            case .saveFailed(let code):
                // Называем, что знаем, и не притворяемся, что знаем больше.
                if let code {
                    String(localized: "iCloud не принял приглашение (код \(code)). Проверь связь и попробуй ещё раз.")
                } else {
                    String(localized: "iCloud не принял приглашение. Проверь связь и попробуй ещё раз.")
                }
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
        // Пустой `url` — не «ты не владелец»: запись уже наша и уже
        // сохранена, облако просто не успело выдать адрес.
        guard let url = share.url else { throw ShareError.linkNotReady }
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
        switch saved.saveResults[shareID] {
        case .success(let record):
            guard let created = record as? CKShare else {
                // Сохранилось, но вернулось не то. Своего кода у этого
                // случая нет — и выдумывать его мы не станем.
                throw ShareError.saveFailed(code: nil)
            }
            return created
        case .failure(let error):
            // `notOwner` CloudKit тоже умеет назвать — и только тогда
            // мы говорим про владельца. Во всех прочих случаях несём код.
            if let ck = error as? CKError, ck.code == .notAuthenticated {
                throw ShareError.noAccount
            }
            throw ShareError.saveFailed(code: (error as? CKError)?.errorCode)
        case nil:
            // Облако не отчиталось об этой записи вовсе — не успех
            // и не отказ. Молчание называем молчанием, а не владельцем.
            throw ShareError.saveFailed(code: nil)
        }
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
        case ShareError.linkNotReady: "linkNotReady"
        case ShareError.saveFailed(let code): code.map { "saveFailed\($0)" } ?? "saveFailed"
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
