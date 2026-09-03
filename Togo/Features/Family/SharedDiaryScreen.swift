import SwiftUI
import SwiftData

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
    @State private var inviteURL: URL?
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
            if let inviteURL {
                ShareLink(item: inviteURL,
                          subject: Text("Дневник \(dog?.name ?? "собаки")"),
                          message: Text("Открой ссылку — и сможешь отмечать вместе со мной.")) {
                    TGListRow(title: "Отправить ссылку", systemImage: "square.and.arrow.up",
                              accessory: .none)
                }
                .buttonStyle(.plain)
                TGExplainer(text: "Ссылка именная: открыть её сможет только тот, кому ты её отправишь, и только со своим iCloud.")
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
            Text("Включи — и второй человек будет отмечать со своего телефона: выход, кормление, дозу. Записи сойдутся в одну ленту, у каждой виден автор. Обмениваются отметки, а не настройки: профиль собаки каждый заводит у себя.")
                .textStyle(AppFont.caption)
            TGExplainer(text: "Нужен iCloud на обоих телефонах. Аккаунт в Того по-прежнему не нужен — обмен идёт через личный iCloud, а не через чужой сервер.")
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
            inviteURL = try await FamilyShare.inviteURL(dogName: dog?.name ?? "собаки")
            participants = await FamilyShare.participants()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func stopSharing() async {
        do {
            try await FamilyShare.stopSharing()
            inviteURL = nil
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
