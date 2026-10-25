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
        // **Гость сюда заходить не должен, и до 05.10 заходил молча.**
        // Экран «Семья» не спрашивал `isGuest` ни разу, а здесь стояла
        // своя адресация — личная база и СВОЯ зона. Гость, нажавший
        // «Пригласить», заводил в собственной базе ВТОРОЙ дневник, пустой,
        // и делился им. На экране это выглядело как удачное приглашение.
        //
        // `notOwner` для этого и заведён — и ни разу отсюда не бросался.
        //
        // Стоит ПЕРВОЙ, раньше права и входа, и это не вкус: быть гостем
        // не зависит ни от аккаунта, ни от профиля подписи, а проверка
        // локальна. Значит её можно проверить тестом без облака —
        // а проверку, которую нельзя проверить, мы уже называли
        // непроверяемой поверхностью и чинили переделкой входа.
        guard !SharedZoneOwner.isGuest else { throw ShareError.notOwner }

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
        // Через каталог, а не литералом: этот заголовок рисует СИСТЕМНАЯ
        // шторка приглашения на телефоне у того, кого зовут, — то есть
        // первое, что видит мама. Литерал здесь доезжает до экрана мимо
        // каталога: присвоение `String`-полю каталог не спрашивает,
        // и полнота ключей про него ничего не говорит.
        // Новых ключей правка не заводит: «Дневник · %@» лежит
        // на четырёх языках (fr переведён, en и uk на вычитке).
        share[CKShare.SystemFieldKey.title] = String(localized: "Дневник · \(dogName)")
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

    /// Где лежит запись общего доступа — у владельца и у гостя по-разному.
    ///
    /// **Заведено 05.10, и до него каждое из четырёх мест адресовало
    /// облако само.** `SharedZoneRouting` существовал, был верен и
    /// вызывался **из двух мест в `FamilySync`**; `FamilyShare` все
    /// четыре раза писал `privateCloudDatabase` и `zoneID()` руками.
    ///
    /// Для владельца это верно, для гостя — нет: его зона лежит в ОБЩЕЙ
    /// базе и под именем владельца. Гость спрашивал свою личную базу,
    /// получал «ничего нет» и видел экран, на котором ничего не произошло.
    ///
    /// > Это ровно тот класс, что `replaceInPool` у Gamut: **функция
    /// > верна, покрыта и не вызывается оттуда, где нужна.** Сторож
    /// > на вызов её не поймал бы — вызовы есть, просто не все.
    private static func адрес(
        _ container: CKContainer
    ) -> (database: CKDatabase, zoneID: CKRecord.ID) {
        let owner = SharedZoneOwner.name
        let zone = SharedZoneRouting.zone(owner: owner)
        let database = SharedZoneRouting.scope(owner: owner) == .shared
            ? container.sharedCloudDatabase
            : container.privateCloudDatabase
        return (database, CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone))
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
        let (database, shareID) = адрес(container)
        return try? await database.record(for: shareID) as? CKShare
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
        // Гость тоже спрашивает — и до 05.10 спрашивал свою личную базу,
        // получал пусто и видел «Семья» без единого человека. Экран при
        // этом обещает «Все видят одно и то же».
        let (database, shareID) = адрес(container)
        guard let share = try? await database.record(for: shareID) as? CKShare
        else { return [] }

        return share.participants.compactMap { participant in
            let name = participant.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter().string(from: $0) }
            let mail = participant.userIdentity.lookupInfo?.emailAddress
            let label = name?.isEmpty == false ? name : mail
            return label ?? nil
        }
    }

    // MARK: - Роль, выбранная владельцем

    /// Наряд ролей с записи общего доступа — или `nil`, если его там нет.
    ///
    /// # Почему именно запись общего доступа, а не свой тип и не зона
    ///
    /// ```
    /// свой тип записи     ЗАПРЕЩЁН решением 08.10.2026: участники
    ///                     приходят из `CKShare.participants`, и второй
    ///                     механизм рядом с работающим ломается молча
    ///                     (`SharedDiary.swift:78`)
    /// поле зоны           ТАКОГО НЕТ: у `CKRecordZone` своих полей
    ///                     не бывает вовсе — там только имя и владелец
    /// корневая запись     у зонного общего доступа её НЕТ: делится
    ///                     зона целиком (`CKRecordNameZoneWideShare`)
    /// поле на `CKShare`   ← взято. Запись одна, её видят обе стороны,
    ///                     адресуется она уже работающим `адрес(…)`
    /// ```
    ///
    /// # Чего этот канал НЕ умеет, и это названо здесь, а не в журнале
    ///
    /// 1. **Он ничего не запрещает.** CloudKit делит доступ по зонам,
    ///    а не по полям: участник с правом записи кладёт в зону что
    ///    угодно любым клиентом. Роль отсюда — то, что приложение
    ///    ПОКАЗЫВАЕТ и предлагает, а не стена. Ровно это уже записано
    ///    в `docs/матрица-ролей.md` разделом «Чего это решение
    ///    НЕ закрывает», и приезд роли там не меняет ни строчки.
    /// 2. **Наряд читают все участники.** Мама видит, какую роль дали
    ///    ситтеру. Нового разглашения тут нет — имена и почты и так
    ///    приходят через `participants()`, — но сведения новые.
    /// 3. **Проверить, что наряд писал владелец, нам нечем.** Поэтому
    ///    приехавшее значение проходит через `потолокГостя`, и потолок
    ///    по этой причине остаётся (`FamilyResolver.потолокГостя`).
    /// 4. **`make cloudkit-check` про это поле не скажет ничего.**
    ///    `deploy_cloudkit_schema.sh` сверяет типы записей из
    ///    `SharedDiaryRecords.swift`; поле на `cloudkit.share` в его
    ///    ось не входит. Зелёный оттуда — не замер этого канала.
    static func наряд(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async -> НарядРолей? {
        guard let share = await existing(container: container) else { return nil }
        return РолиВОбмене.разобрать(share[РолиВОбмене.полеНаряда] as? String)
    }

    /// Положить наряд на запись общего доступа. Только владелец.
    ///
    /// Гость отсекается здесь же и первой строкой — по той же причине,
    /// по которой это сделано в `invite` и `stopSharing`: проверка
    /// локальна, значит её можно проверить тестом без облака.
    static func записать(
        _ наряд: НарядРолей,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws {
        guard !SharedZoneOwner.isGuest else { throw ShareError.notOwner }
        let (database, shareID) = адрес(container)
        guard let share = try? await database.record(for: shareID) as? CKShare else {
            // Делиться ещё не начали — назначать некому. Это не отказ
            // облака, и кодом отказа называть его нельзя.
            throw ShareError.linkNotReady
        }
        guard let строка = РолиВОбмене.закодировать(наряд) else {
            throw ShareError.saveFailed(code: nil)
        }
        share[РолиВОбмене.полеНаряда] = строка  // внутреннее: JSON наряда ролей, человек его не видит
        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        if case .failure(let error) = saved.saveResults[shareID] {
            throw ShareError.saveFailed(code: (error as? CKError)?.errorCode)
        }
    }

    /// Роль для всех, кого ещё не назвали поимённо, — то самое
    /// «выбираете вы при приглашении».
    ///
    /// **Поимённое назначение этим путём не делается, и причина
    /// структурная.** Чтобы назначить роль конкретному участнику,
    /// нужен его идентификатор CloudKit; у локальной карточки
    /// `FamilyMember` его нет ни одним полем, и связи «карточка ↔
    /// участник» в проекте не существует вовсе. Завести её — отдельная
    /// работа с формой схемы, то есть решение Виктории. До тех пор
    /// `поУчастникам` остаётся в формате и **не пишется никем** —
    /// сказано здесь нарочно, потому что объявление без писателя
    /// читается как обещание.
    static func назначитьНовичкам(
        _ роль: FamilyRole,
        права: Set<Permission>? = nil,
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws {
        var наряд = await наряд(container: container) ?? НарядРолей()
        наряд.новичкам = НазначеннаяРоль(роль: роль, права: права)
        try await записать(наряд, container: container)
    }

    /// Забрать своё назначение с записи общего доступа и положить
    /// туда, откуда его читают оба входа в права.
    ///
    /// **Молчит при любом отказе, и это решение, а не недосмотр.**
    /// Не узнав назначения, человек остаётся наблюдателем — то самое
    /// состояние, которое было до этой правки. Стереть уже приехавшее
    /// из-за отсутствия сети значило бы отнять права у того, кому их
    /// выдали: признак «сети нет» и признак «роль отозвали» отсюда
    /// неотличимы, и ошибаться надо в сторону сохранения.
    ///
    /// **`уже:` передаётся обязательно, и без него правка 25.10.2026
    /// не действует.** Приколотое назначение — единственное, что
    /// отличает вошедшего от новичка: `поУчастникам` не пишет никто,
    /// поэтому без этого довода каждая синхронизация заново применяла
    /// бы к вошедшему текущий `новичкам` и молча повышала права.
    /// Разбор — у `РолиВОбмене.назначение`, там же цена.
    @discardableResult
    static func обновитьНазначение(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async -> НазначеннаяРоль? {
        guard SharedZoneOwner.isGuest else { return nil }
        guard let наряд = await наряд(container: container) else { return nil }
        let я = try? await container.userRecordID().recordName
        guard let моё = РолиВОбмене.назначение(из: наряд, участник: я,
                                               уже: НазначениеПоОбмену.текущее)
        else { return nil }
        НазначениеПоОбмену.текущее = моё
        return моё
    }

    /// Перестать делиться. Записи у приглашённого при этом остаются
    /// его копией — забрать уже показанное CloudKit не умеет, и врать
    /// об этом нельзя.
    static func stopSharing(
        container: CKContainer = CKContainer(identifier: AppIdentifiers.cloudContainer)
    ) async throws {
        // **Гость этим не пользуется, и раньше пользовался молча.**
        // Удаление записи общего доступа — право владельца. У гостя
        // её в личной базе нет, и `modifyRecords` отвечал успехом,
        // ничего не удалив: человек жал «Перестать делиться», получал
        // подтверждение и оставался в чужом дневнике.
        //
        // Выход гостя — другая операция (`CKShare.Participant` уходит
        // сам), и называть её тем же словом нельзя.
        guard !SharedZoneOwner.isGuest else { throw ShareError.notOwner }

        let (database, shareID) = адрес(container)
        _ = try await database.modifyRecords(saving: [], deleting: [shareID])
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
                accepted(ownerName: owner, чьёИмя: чьёИмя(metadata))
                // Строго ПОСЛЕ `accepted`: имя владельца пишет оно,
                // а без имени `isGuest` ещё ложно — и забирать наряд
                // было бы некому. Порядок здесь часть смысла.
                await FamilyShare.обновитьНазначение()
            } catch {
                handled.remove(key)
                log.notice("Приглашение не принялось: \(error.localizedDescription)")
                // Отказ идёт ТУДА ЖЕ, куда успех, и говорит другое.
                //
                // Пока он кончался одним `log.notice`, человек не узнавал
                // ничего: приложение открывалось обычным, и мама считала,
                // что вошла. Узнала бы обратное, не увидев ни одной
                // записи и решив, что дневник пуст.
                объявить(.причина(error))
            }
        }
    }

    /// Чем кончился последний приём — для того, кто покажет это человеку.
    ///
    /// Хранится здесь, а не передаётся в уведомлении: приём случается,
    /// когда система открывает приложение ссылкой, и показать его
    /// может быть пока некому. Исход дождётся того, кто подпишется.
    public private(set) static var исход: ShareAcceptanceOutcome?

    /// Исход прочитан и показан — больше не показывать.
    ///
    /// Без снятия тот же отказ всплыл бы на каждом следующем запуске:
    /// человек прочитал, починил, вошёл — и снова видит старую жалобу.
    ///
    /// **Снимает только мимолётный показ, не сам отказ.** Отказ живёт
    /// в `НеудачаПриёма` и ждёт, пока его починят: плашка висит пять
    /// секунд, а приём случается на холодном старте по ссылке — человек
    /// в эту секунду смотрит на незнакомый экран первый раз.
    public static func исходПрочитан() {
        исход = nil
    }

    private static func объявить(_ новый: ShareAcceptanceOutcome) {
        исход = новый
        // Успех снимает прежний отказ: человек починил и вошёл.
        НеудачаПриёма.текущая = новый.принято_ли ? nil : новый
        NotificationCenter.default.post(name: .familyShareAccepted, object: nil)
    }

    /// Приглашение принято: чей это дневник, включён ли обмен, и кому
    /// об этом сказать.
    ///
    /// Отдельной функцией от `accept` — у неё на входе обычная строка,
    /// а не `CKShare.Metadata`, которую в тесте не собрать.
    /// - Parameters:
    ///   - ownerName: имя зоны владельца — **непрозрачный
    ///     идентификатор** вроде `_a1b2…`, человеку его показывать
    ///     нельзя. Им адресуются записи, и только.
    ///   - чьёИмя: имя владельца для человека. Приходит из
    ///     `CKShare.Metadata` и **может отсутствовать**: CloudKit
    ///     отдаёт `nameComponents` не всегда. Отсутствие названо
    ///     отдельным текстом, а не заменено на «общий дневник».
    static func accepted(ownerName: String, чьёИмя: String? = nil) {
        SharedZoneOwner.name = ownerName
        SharedDiarySettings.isOn = true
        // Третье решение, появившееся 08.10.2026: сказать человеку,
        // **чей** дневник он открыл. «Вы в общем дневнике» не отвечает
        // на вопрос, в чьём именно, — а гость приходит по ссылке
        // и видит чужие записи о чужой собаке.
        объявить(.принято(чей: чьёИмя))
    }

    /// Имя владельца приглашения для человека — из метаданных.
    ///
    /// Тем же способом, что и состав семьи в `participants()`: имя
    /// из `nameComponents`, иначе почта. Если нет ни того ни другого —
    /// `nil`, и текст скажет об этом прямо.
    static func чьёИмя(_ metadata: CKShare.Metadata) -> String? {
        let identity = metadata.share.owner.userIdentity
        if let components = identity.nameComponents {
            let собрано = PersonNameComponentsFormatter().string(from: components)
            if !собрано.isEmpty { return собрано }
        }
        return identity.lookupInfo?.emailAddress
    }
}

/// Непочиненный отказ приёма приглашения — чтобы его было где прочесть
/// после того, как плашка ушла.
///
/// # Зачем хранить, а не показать и забыть
///
/// Приём случается, когда система открывает приложение по ссылке:
/// холодный старт, человек смотрит на незнакомый экран первый раз.
/// Плашка живёт пять секунд, кнопки «ещё раз» у неё нет, а
/// `исходПрочитан()` снимает исход сразу — то есть **повторить
/// сообщение было нечем**.
///
/// Цена измерена на мамином пути: она входит публичной ссылкой. Увидев
/// отказ и не успев прочесть, она остаётся уверенной, что вошла, —
/// ровно то состояние, которое `ShareAcceptanceOutcome` заводился
/// лечить.
///
/// # Почему код, а не готовая строка
///
/// Хранится **имя причины**, а текст собирается при показе. Положи
/// здесь строку — и она застынет на языке того дня; человек, сменивший
/// язык, прочтёт прошлый. Шестого текста при этом не заводится: все
/// пять живут в `ShareAcceptanceOutcome.текст` и покрыты
/// `ShareAcceptanceTextTests`.
///
/// Успех причину снимает: человек починил и вошёл. Снимает её
/// `FamilyShare.объявить`, одним местом на оба исхода.
nonisolated enum НеудачаПриёма {
    private static let key = "share.acceptance.failure"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Причина последнего неудавшегося приёма — или `nil`, если
    /// починено либо не было.
    ///
    /// `.принято` сюда не попадает: успех — не отказ, и присвоение
    /// успеха читается как снятие.
    static var текущая: ShareAcceptanceOutcome? {
        get {
            switch defaults.string(forKey: key) {
            case "нетСети": .нетСети          // внутреннее: код состояния в UserDefaults, человек его не видит
            case "нетiCloud": .нетiCloud      // внутреннее: код состояния в UserDefaults, человек его не видит
            case "сторонаПриложения": .сторонаПриложения  // внутреннее: код состояния в UserDefaults, человек его не видит
            case "неизвестно": .неизвестно    // внутреннее: код состояния в UserDefaults, человек его не видит
            default: nil
            }
        }
        set {
            // Разворачиваем ДО `switch`: образцы вида `.нетСети`
            // по `Optional` не совпадают — пришлось бы писать
            // `.некоторое(.нетСети)`, и `.принято` затерялось бы среди
            // обёрток. Здесь же видно, что успех и пустое снимают
            // запись одинаково.
            //
            // Успех отсеивает сам `switch` ниже (`case .принято: nil`),
            // а НЕ свойство `принято_ли`: это свойство изолировано
            // главным актором, а здесь `nonisolated` — сборка поймала
            // это ошибкой, и она была права. Разбор образца изоляции
            // не требует вовсе, поэтому ответ тот же и дороги в главный
            // актор отсюда не появляется.
            guard let причина = newValue else {
                defaults.removeObject(forKey: key)
                return
            }
            // Эти восемь слов — ЗАПИСЬ В ХРАНИЛИЩЕ, а не подпись.
            // Перевести их значило бы записать по-французски то, что
            // читается сравнением с русским: смена языка обнулила бы
            // причину отказа, и человек, не вошедший в iCloud, снова
            // не узнал бы об этом. Пометка строчная, не файловая:
            // в этом же файле есть живой переводимый заголовок (:130).
            let код: String? = switch причина {
            case .нетСети: "нетСети"          // внутреннее: код состояния в UserDefaults, человек его не видит
            case .нетiCloud: "нетiCloud"      // внутреннее: код состояния в UserDefaults, человек его не видит
            case .сторонаПриложения: "сторонаПриложения"  // внутреннее: код состояния в UserDefaults, человек его не видит
            case .неизвестно: "неизвестно"    // внутреннее: код состояния в UserDefaults, человек его не видит
            case .принято: nil
            }
            if let код { defaults.set(код, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}
