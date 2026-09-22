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
    @State private var isWorking = false
    @State private var isStoppingShare = false

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var canInvite: Bool { appState.can(.manageFamily) }

    var body: some View {
        TGScreen {
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
        .navigationBarTitleDisplayMode(.large)
        .task { await refresh() }
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
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: failure,
                         systemImage: "exclamationmark.triangle")
            }
        }
    }

    /// Что происходит прямо сейчас — словами, а не галочкой.
    private var statusCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "состояние")
            TGListRow(title: "Обмен", value: stateTitle, accessory: .none)
            TGDivider()
            TGListRow(title: "Своё не уехало", value: "\(sync?.pending ?? 0)", accessory: .none)
            if !participants.isEmpty {
                TGDivider()
                TGListRow(title: "В дневнике", value: participants.joined(separator: ", "),
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

    private var stateTitle: String {
        switch sync?.state {
        case .none, .off: "выключен"
        case .starting: "поднимается"
        case .syncing: "идёт обмен"
        case .idle(let last):
            last.map { "последний раз \(Fmt.clock($0))" } ?? "готов"
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
                          preview: SharePreview("Дневник · \(dog?.name ?? "собаки")",
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
        isOn = on
        SharedDiarySettings.isOn = on
        failure = nil
        Task {
            if on { await sync?.start() } else { sync?.stop() }
            await refresh()
        }
    }

    private func makeInvite() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await FamilyShare.invite(dogName: dog?.name ?? "собаки")
            invite = DiaryInvite(share: share)
            participants = await FamilyShare.participants()
        } catch {
            failure = error.localizedDescription
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
        participants = await FamilyShare.participants()
    }
}

/// Что уходит в лист «Поделиться»: сам `CKShare` и контейнер, в котором он
/// живёт. `CKShareTransferRepresentation` включает в листе режим совместной
/// работы — выбор людей, права, отправка через Сообщения или Почту.
/// По умолчанию — только названным людям, на запись: приглашают затем,
/// чтобы второй человек отмечал.
struct DiaryInvite: Transferable {
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
