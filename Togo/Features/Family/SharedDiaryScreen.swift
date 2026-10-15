import SwiftUI
import SwiftData
import CloudKit
import CoreTransferable

/// Общий дневник: пригласить второго человека и видеть, что обмен живой.
///
/// Экран обязан честно отвечать на один вопрос — «дошло или нет». Пока
/// его не было, синхронизация в приложениях выглядит как зелёная галочка,
/// которая горит всегда и не значит ничего. Здесь вместо галочки написано,
/// когда последний раз забирали чужое и сколько своего ещё не уехало.
struct SharedDiaryScreen: View {
    @Environment(\.familySync) private var sync
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]

    @State private var isOn = SharedDiarySettings.isOn
    @State private var invite: DiaryInvite?
    @State private var participants: [String] = []
    @State private var failure: String?
    /// Непочиненный отказ приёма приглашения — тот, что показывала
    /// плашка пять секунд на холодном старте. Здесь он ждёт, пока
    /// его починят.
    @State private var отказПриёма: ShareAcceptanceOutcome?
    @State private var isWorking = false
    @State private var isStoppingShare = false

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var canInvite: Bool { appState.can(.manageFamily) }

    var body: some View {
        TGScreen {
            // Выше тумблера нарочно: это и есть ответ на вопрос «почему
            // у меня пусто». Внутри `if isOn` он бы не показался вовсе —
            // при неудавшемся приёме `accepted()` не звали, и обмен
            // остался выключенным.
            //
            // Заголовок — СУЩЕСТВУЮЩИЙ ключ «Не получилось», тот же,
            // что у соседнего баннера ниже. Свой («Приглашение
            // не открылось») был бы новым ключом и завёл бы пробелы
            // на en/fr/uk, а причину и так называет подзаголовок —
            // одной из пяти написанных строк.
            if let отказПриёма {
                TGBanner(tone: .alarm, title: "Не получилось",
                         subtitle: .готовая(отказПриёма.текст),
                         systemImage: "exclamationmark.triangle")
            }
            switchCard
            if isOn {
                statusCard
                if canInvite { inviteCard } else { guestCard }
            } else {
                explainerCard
            }
            limitsCard
        }
        .navigationTitle("Общий дневник")
        .posterHeader("Общий дневник")
        .navigationBarTitleDisplayMode(.large)
        .usageScreen(.sharedDiary)
        .task {
            // Читается ДО `refresh()` и вне его: у `refresh()` стоит
            // `guard isOn, canInvite`, а неудавшийся приём оставляет
            // обмен выключенным — то есть внутри него этот отказ
            // не прочитался бы ни разу.
            отказПриёма = НеудачаПриёма.текущая
            await refresh()
        }
    }

    // MARK: Включатель

    private var switchCard: some View {
        TGCard {
            Toggle(isOn: Binding(get: { isOn }, set: { turn(on: $0) })) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Вести дневник вдвоём").textStyle(AppFont.body)
                    Text("записи с обоих телефонов сходятся в один дневник")
                        .textStyle(AppFont.caption)
                }
            }
            if let failure {
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: .готовая(failure),
                         systemImage: "exclamationmark.triangle")
            }
        }
    }

    /// Что происходит прямо сейчас — словами, а не галочкой.
    private var statusCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "состояние")
            TGListRow(title: "Обмен", value: .готовая(stateTitle), accessory: .none)
            TGDivider()
            // ЧЕЙ ЭТО ДНЕВНИК — различитель, которого у человека не было.
            //
            // Без него «Обмен: готов» одинаково выглядит у того, кто вошёл
            // в чужой дневник, и у того, кто завёл свой, считая, что вошёл.
            // Это тот же вопрос, что экран задаёт про обмен, только про
            // адрес: не «работает ли», а «работает КУДА».
            //
            // Показывается бит, а не имя, и это вынужденно: `SharedZoneOwner.name`
            // — технический `zoneID.ownerName` вида `_a1b2…`, человеку его
            // показывать нельзя (сказано в `FamilyShare.accepted`). Имя
            // владельца для человека приходит в `CKShare.Metadata` при приёме
            // и **нигде не сохраняется** — показать его сегодня нечем.
            TGListRow(title: "Чей дневник", value: .готовая(ownerTitle), accessory: .none)
            TGDivider()
            // При `nil` здесь стоял ноль, и читался он как «всё уехало»
            // ровно тогда, когда не уехало ничего: движка нет — считать
            // нечего. Прочерк отличает «ничего не ждёт отправки»
            // от «спросить не у кого».
            TGListRow(title: "Своё не уехало",
                      value: .готовая(sync.map { "\($0.pending)" } ?? "—"),
                      accessory: .none)
            if !participants.isEmpty {
                TGDivider()
                TGListRow(title: "В дневнике", value: .готовая(participants.joined(separator: ", ")),
                          accessory: .none)
            }
            TGDivider()
            Button {
                Task { await sync?.fetchNow(); await refresh() }
            } label: {
                TGListRow(title: "Забрать сейчас", systemImage: "arrow.clockwise", accessory: .none)
            }
            .buttonStyle(.plain)
        }
    }

    /// Свой дневник или чужой — одним словом.
    ///
    /// `nil` у владельца зоны значит «дневник наш собственный»
    /// (`SharedZone.swift:26`), и это не отсутствие ответа, а ответ.
    private var ownerTitle: String {
        SharedZoneOwner.name == nil
            ? String(localized: "свой")
            : String(localized: "другого человека")
    }

    private var stateTitle: String {
        switch sync?.state {
        // ДВА РАЗНЫХ СОСТОЯНИЯ, И СЛОВО У НИХ БЫЛО ОДНО.
        //
        // `nil` — движка нет вовсе; `.off` — движок есть и выключен.
        // Пока они печатались вместе, карточка состояния отвечала
        // «выключен» в том числе на вопрос «а есть ли кому отвечать»,
        // и человек читал это как решение приложения, а не как его
        // молчание. Рядом стояло «Своё не уехало: 0» — второе показание,
        // врущее в ту же сторону, то есть выглядящее подтверждением.
        case .none: String(localized: "ещё не поднялся")
        case .off: String(localized: "выключен")
        case .starting: String(localized: "поднимается")
        case .syncing: String(localized: "идёт обмен")
        case .idle(let last):
            last.map { String(localized: "последний раз \(Fmt.clock($0))") } ?? String(localized: "готов")
        case .failed(let reason): reason
        }
    }

    // MARK: Приглашение

    private var inviteCard: some View {
        TGCard {
            TGSectionHeader(title: "пригласить")
            if let invite {
                // Лист «Поделиться» в режиме совместной работы: там выбирают
                // человека из контактов, и CloudKit записывает его в участники.
                // Голая ссылка текстом при `publicPermission = .none` не
                // открылась бы ни у кого.
                ShareLink(item: invite,
                          preview: SharePreview("Дневник · \(dog.flatMap(\.nameIfAny) ?? String(localized: "собаки"))",
                                                image: Image(systemName: "pawprint.fill"))) {
                    TGListRow(title: "Пригласить человека", systemImage: "person.badge.plus",
                              accessory: .none)
                }
                .buttonStyle(.plain)
                TGExplainer(text: "Выбери, кого пригласить, — маму, мужа, ситтера. Откроет только он, со своего iCloud, и ему нужен Togo на телефоне. Кто уже в дневнике, видно выше.")
                Button("Перестать делиться", role: .destructive) { isStoppingShare = true }
                    .textStyle(AppFont.captionEmphasis.color(Token.Status.overdueText))
            } else {
                TGButton(title: isWorking ? "Готовлю…" : "Создать приглашение",
                         systemImage: "person.badge.plus",
                         isEnabled: !isWorking) {
                    Task { await makeInvite() }
                }
            }
        }
        .confirmationDialog("Перестать делиться дневником?",
                            isPresented: $isStoppingShare, titleVisibility: .visible) {
            Button("Перестать делиться", role: .destructive) { Task { await stopSharing() } }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Новые записи к нему приходить перестанут. То, что он уже получил, останется у него на телефоне: забрать показанное iCloud не умеет.")
        }
    }

    private var guestCard: some View {
        TGCard {
            TGSectionHeader(title: "ты в чужом дневнике")
            TGExplainer(text: "Приглашает и убирает участников владелец. Твои отметки приходят к нему, его — к тебе.")
        }
    }

    private var explainerCard: some View {
        TGCard {
            Text("Пока дневник только на этом телефоне").textStyle(AppFont.cardTitle)
            Text("Включи — и второй человек будет отмечать со своего телефона. Записи сойдутся в одну ленту, у каждой виден автор. Уезжают отметки, а не настройки: профиль собаки каждый заводит у себя.")
                .textStyle(AppFont.caption)
            TGExplainer(text: "Нужен iCloud на обоих телефонах. Аккаунт в Togo по-прежнему не нужен — обмен идёт через личный iCloud, а не через чужой сервер.")
        }
    }

    /// Границы названы прямо: обещать больше, чем умеет обмен, — худшее,
    /// что можно сделать с дневником, которому доверяют дозы.
    private var limitsCard: some View {
        TGCard {
            TGSectionHeader(title: "что важно знать")
            TGIconRow(symbol: "pills",
                      title: "Доза защищена в обе стороны",
                      detail: "Если один отметил приём, второй увидит замок. При споре двух телефонов отметка «дано» побеждает всегда — лишний замок безопаснее второй таблетки.")
            TGIconRow(symbol: "trash",
                      title: "Удаление сильнее правки",
                      detail: "Если один удалил запись, а второй в это же время её правил — запись удалена. Вернуть — один тап.")
            TGIconRow(symbol: "iphone.and.arrow.forward",
                      title: "Обмениваются лента и дозы",
                      detail: "Выходы, еда, стул, прогулки, инциденты и отметки приёма — всё, что отмечают руками за день. Профиль, расписание ухода, занятия, поездки и снимки каждый заводит у себя.")
        }
    }

    // MARK: Действия

    private func turn(on: Bool) {
        // ТУМБЛЕР НЕ ПОДМЕНЯЕТ ПРИЁМ ПРИГЛАШЕНИЯ, и это главный запрет
        // на этом экране.
        //
        // Путь, который он закрывает, измерен по коду 15.10.2026 и кончался
        // полностью зелёным экраном у человека, который не вошёл никуда:
        //
        // ```
        // мама жмёт ссылку → accept падает (нет сети) → НеудачаПриёма = .нетСети
        //   SharedZoneOwner.name остаётся nil — приём не прошёл
        // мама видит баннер отказа и ВЫКЛЮЧЕННЫЙ тумблер (isOn не ставили)
        // мама включает тумблер → прежняя редакция стирала жалобу первой
        //   строкой, поднимала обмен, и SharedZoneRouting при owner == nil
        //   давала СВОЮ зону в ЛИЧНОЙ базе (SharedZone.swift:57, :62)
        // экран: «Обмен: готов», «Своё не уехало: 0»
        // ```
        //
        // > Она ведёт свой собственный дневник, считая, что вошла в чужой,
        // > и записей Виктории не увидит **никогда**. Единственный признак,
        // > по которому можно было догадаться, стирал её же тап.
        //
        // Поэтому: владелец зоны неизвестен и отказ приёма не починен —
        // не включаем, а повторяем причину отказа. Текст берётся готовый
        // (`ShareAcceptanceOutcome.текст`, пять строк, уже переведены
        // и покрыты `ShareAcceptanceTextTests`) — в каждой из пяти уже
        // сказано, что делать: открыть ссылку снова.
        //
        // **У Виктории этот запрет не срабатывает ни разу**: у владельца
        // дневника непочиненного отказа приёма не бывает — ей никто
        // не присылал приглашения. Нужны ОБА условия.
        if on, SharedZoneOwner.name == nil, let отказ = НеудачаПриёма.текущая {
            failure = отказ.текст
            отказПриёма = отказ
            // Тумблер возвращается сам: `Binding.set` не меняет `isOn`.
            // Присваиваем явно, чтобы он не зависел от того, перерисует
            // ли SwiftUI карточку.
            isOn = false
            return
        }
        isOn = on
        SharedDiarySettings.isOn = on
        failure = nil
        if on {
            // Человек завёл дневник сам — прежняя жалоба про чужое
            // приглашение устарела. Иначе баннер висел бы вечно:
            // снимает его только успешный приём, а этого человек
            // может уже и не делать.
            //
            // **Сужено до «владелец известен» 15.10.2026.** Безусловное
            // снятие стирало улику раньше, чем её объяснили: отказ приёма
            // гас от тапа по тумблеру, и после этого отличить «вошёл
            // в чужой дневник» от «завёл свой» было нечем. Снимаем жалобу
            // только там, где приём действительно состоялся.
            if SharedZoneOwner.name != nil {
                НеудачаПриёма.текущая = nil
                отказПриёма = nil
            }
        }
        Task {
            if on {
                // Движок обмена создаётся в TogoApp по .familyShareAccepted;
                // до перезапуска здесь его нет, и тумблер молча не работал.
                if let sync { await sync.start() } else {
                    NotificationCenter.default.post(name: .familyShareAccepted, object: nil)
                }
            } else {
                sync?.stop()
            }
            await refresh()
        }
    }

    private func makeInvite() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await FamilyShare.invite(dogName: dog.flatMap(\.nameIfAny) ?? String(localized: "собаки"))
            invite = DiaryInvite(share: share)
            participants = await FamilyShare.participants()
            UsageLog.note(.record, "invite", on: .sharedDiary)
        } catch {
            failure = error.localizedDescription
            UsageLog.note(.record, "invite:\(FamilyShare.причина(error))",
                          on: .sharedDiary, outcome: .failed)
        }
    }

    private func stopSharing() async {
        do {
            try await FamilyShare.stopSharing()
            invite = nil
            participants = []
        } catch {
            failure = error.localizedDescription
        }
    }

    private func refresh() async {
        guard isOn, canInvite else { return }
        // Сначала ссылка, потом участники: пока приглашение не найдено,
        // экран предлагает создать уже созданное, и путь начинается
        // с нуля при каждом заходе.
        if invite == nil { invite = await FamilyShare.existing().map(DiaryInvite.init) }
        participants = await FamilyShare.participants()
    }
}

/// Что уходит в лист «Поделиться»: сам `CKShare` и контейнер, в котором он
/// живёт. `CKShareTransferRepresentation` включает в листе режим совместной
/// работы — выбор людей, права, отправка через Сообщения или Почту.
/// По умолчанию — только названным людям, на запись: приглашают затем,
/// чтобы второй человек отмечал.
nonisolated struct DiaryInvite: Transferable {
    let share: CKShare
    var container: CKContainer { CKContainer(identifier: AppIdentifiers.cloudContainer) }

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            .existing(invite.share,
                      container: invite.container,
                      allowedSharingOptions: CKAllowedSharingOptions(
                          allowedParticipantPermissionOptions: .readWrite,
                          allowedParticipantAccessOptions: .specifiedRecipientsOnly))
        }
    }
}
