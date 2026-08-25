import SwiftUI
import SwiftData

/// Семья · роли, дежурство, вид ситтера.
/// Роли — не лестница: врач читает много и не пишет, ребёнок пишет бытовое
/// и не видит медицинского.
struct FamilyScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var members: [FamilyMember]
    @Query private var dogs: [Dog]

    @State private var showInvite = false
    @State private var showPaywall = false

    private var dog: Dog? { dogs.first }
    private var duty: FamilyMember? { members.first(where: \.isOnDuty) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if let conflict = mergeConflict {
                    MergeConflictCard(left: conflict.0, right: conflict.1)
                }
                if let duty { dutyCard(duty) }
                membersCard
                rolesExplainer
            } bottom: {
                TGButton(title: "Пригласить человека", systemImage: "person.badge.plus") {
                    if store.isPro || members.count < 2 { showInvite = true } else { showPaywall = true }
                }
            }
            .navigationTitle("Семья")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showInvite) { InviteSheet() }
            .sheet(isPresented: $showPaywall) { NavigationStack { PaywallScreen() } }
        }
    }

    // MARK: Дежурство

    private func dutyCard(_ member: FamilyMember) -> some View {
        TGCard {
            HStack(spacing: Token.Space.s12) {
                TGAvatar(initial: member.initial, size: Token.Size.avatarMd)
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Сегодня дежурит \(member.name)").textStyle(AppFont.cardTitle)
                    Text(member.dutyUntil.map { "до \(Fmt.clock($0)) · напоминания идут ему" } ?? "напоминания идут ему")
                        .textStyle(AppFont.caption)
                }
                Spacer(minLength: Token.Space.s8)
                Button("передать") { passDuty(from: member) }
                    .textStyle(AppFont.captionEmphasis.color(Token.Action.done))
            }
        }
    }

    /// Передача дежурства — одно действие, а не форма.
    private func passDuty(from current: FamilyMember) {
        let candidates = members.filter { $0.role.canGiveDose && $0.id != current.id }
        guard let next = candidates.first else { return }
        current.isOnDuty = false
        next.isOnDuty = true
        next.dutyUntil = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: .now)
        Haptics.success()
    }

    // MARK: Участники

    private var membersCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "участники · \(members.count)")
            ForEach(members) { member in
                NavigationLink { MemberScreen(member: member) } label: {
                    MemberRow(member: member)
                }
                .buttonStyle(.plain)
                if member.id != members.last?.id { TGDivider(inset: 38) }
            }
        }
    }

    private var rolesExplainer: some View {
        TGCard {
            Text("Роли — не лестница").textStyle(AppFont.cardTitle)
            Text("Врач читает много и не пишет; ребёнок пишет бытовое и не видит медицинского. Дежурный получает напоминания — и только он.")
                .textStyle(AppFont.caption)
            NavigationLink("Как выглядит вид ситтера") { SitterPreviewScreen(dog: dog) }
                .textStyle(AppFont.captionEmphasis.color(Token.Action.done))
        }
    }

    // MARK: Конфликт офлайн-записей

    private var mergeConflict: (LogEvent, LogEvent)? {
        Diary.mergeCandidates(dog?.events ?? []).last
    }
}

private struct MemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            TGAvatar(initial: member.initial, tint: member.isMe ? Token.Action.primaryQuiet : Token.Action.done)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(member.name).textStyle(AppFont.bodyEmphasis)
                Text("\(member.role.title.lowercased()) · \(member.role.permissionSummary)")
                    .textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            if member.isInvitePending {
                Text(member.inviteIsValid() ? "ждёт" : "истекло")
                    .textStyle(AppFont.micro.color(member.inviteIsValid() ? Token.Status.waitingText : Token.Ink.faint))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .foregroundStyle(Token.Ink.faint)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

struct MemberScreen: View {
    let member: FamilyMember

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGScreen(title: member.name) {
            TGCard {
                TGSectionHeader(title: "роль")
                TGChipGroup(
                    items: FamilyRole.allCases,
                    title: \.title,
                    subtitle: { $0.permissionSummary },
                    isSelected: { $0 == member.role }
                ) { role in
                    member.role = role
                    Haptics.tap()
                }
            }

            TGCard {
                TGSectionHeader(title: "что доступно")
                PermissionRow(title: "Записывать бытовое", granted: member.role.canWrite)
                PermissionRow(title: "Видеть медицинское", granted: member.role.canSeeMedical)
                PermissionRow(title: "Отмечать дозу", granted: member.role.canGiveDose)
                PermissionRow(title: "Менять схему лечения", granted: member.role.canEditTreatment)
                PermissionRow(title: "Приглашать людей", granted: member.role.canInvite)
            }

            if let expires = member.accessExpiresAt {
                TGBanner(tone: .waiting, title: "Доступ до \(Fmt.shortDay(expires))",
                         subtitle: "Ссылка ситтера гаснет по дате сама — отзывать её руками не нужно.",
                         systemImage: "clock")
            }

            if !member.isMe {
                TGButton(title: "Убрать из семьи", variant: .destructive, size: .medium, systemImage: "person.badge.minus") {
                    context.delete(member)
                    dismiss()
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(granted ? Token.Action.done : Token.Ink.faint)
            Text(title).textStyle(AppFont.body)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }
}

/// Приглашение живёт 24 часа, роль фиксируется до принятия.
struct InviteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var role: FamilyRole = .caregiver
    @State private var name = ""

    private let token = String(UUID().uuidString.prefix(6))

    private var link: String { "https://togo.app/j/\(token)" }

    var body: some View {
        TGSheet(title: "Пригласить", subtitle: "ссылка живёт 24 часа") {
            TGCard {
                LabeledField(label: "Как зовут") {
                    TextField("Мама", text: $name).textInputAutocapitalization(.words)
                }
            }
            TGCard {
                TGSectionHeader(title: "роль", subtitle: "принявший не сможет её поменять")
                TGChipGroup(
                    items: [FamilyRole.coOwner, .caregiver, .helper, .observer],
                    title: \.title,
                    subtitle: { $0.permissionSummary },
                    isSelected: { $0 == role }
                ) { role = $0 }
            }
            TGCard {
                Text(link).textStyle(AppFont.numeric(15))
                TGExplainer(text: "В ссылке только случайный токен. Ни имени собаки, ни записей в ней нет.")
            }
        } footer: {
            ShareLink(item: URL(string: link)!) {
                Text("Отправить ссылку")
                    .textStyle(AppFont.cardTitle.color(Token.Ink.onAccent))
                    .frame(maxWidth: .infinity, minHeight: Token.Component.Button.Primary.height)
                    .background(Token.Action.primary,
                                in: RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
            }
            .simultaneousGesture(TapGesture().onEnded { create() })
        }
        .presentationDetents([.large])
    }

    private func create() {
        let member = FamilyMember(name: name.isEmpty ? "Приглашение" : name, role: role)
        member.inviteToken = token
        member.inviteExpiresAt = Date().addingTimeInterval(24 * 3600)
        context.insert(member)
    }
}

/// Что видит помощник или ситтер. Роль сама перечисляет, чего он не видит.
struct SitterPreviewScreen: View {
    let dog: Dog?

    var body: some View {
        TGScreen(title: "\(dog?.name ?? "Собака") · ты помощник") {
            TGExplainer(text: "Так экран выглядит у человека с ролью «помощник».")

            TGCard(spacing: 0) {
                TGSectionHeader(title: "что нужно сделать")
                ForEach(plan, id: \.0) { time, title in
                    HStack(spacing: Token.Space.s12) {
                        Text(time).textStyle(AppFont.numeric(13, weight: .medium)).frame(width: 44, alignment: .leading)
                        Text(title).textStyle(AppFont.body)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: Token.Size.iconSm, weight: .semibold))
                            .foregroundStyle(Token.Ink.faint)
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }

            TGCard {
                Text("Чего ты не видишь").textStyle(AppFont.cardTitle)
                Text("Медицинскую часть, историю за прошлые месяцы и контакты семьи. Записывать выходы, еду и прогулки можешь.")
                    .textStyle(AppFont.caption)
            }

            TGCard {
                Text("Если что-то не так").textStyle(AppFont.cardTitle)
                Text("Кнопка «Написать владельцу» ведёт сразу в мессенджер — переписки внутри приложения нет и не будет.")
                    .textStyle(AppFont.caption)
            }
        }
        .navigationTitle("Вид ситтера")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var plan: [(String, String)] {
        [("08:00", "Утренний выход"),
         ("08:30", "Еда · \(dog?.portionGrams ?? 60) г"),
         ("13:00", "Прогулка 30 мин"),
         ("18:30", "Еда · \(dog?.portionGrams ?? 60) г")]
    }
}

/// Две записи об одном событии в пределах 20 минут дают карточку слияния
/// обоим авторам. Приложение не удаляет чужое молча.
struct MergeConflictCard: View {
    let left: LogEvent
    let right: LogEvent

    @Environment(\.modelContext) private var context
    @State private var resolved = false

    var body: some View {
        if !resolved {
            TGCard {
                Text("Две записи об одном").textStyle(AppFont.cardTitle)
                Text("Похоже, вы оба отметили одно и то же. Одна из записей пришла позже — вероятно, автор был без сети.")
                    .textStyle(AppFont.caption)
                TGDivider()
                ConflictRow(event: left)
                ConflictRow(event: right)
                HStack(spacing: Token.Space.s8) {
                    TGButton(title: "Это одно и то же", variant: .secondary, size: .medium) { merge() }
                    TGButton(title: "Нет, было дважды", variant: .secondary, size: .medium) { resolved = true }
                }
                TGExplainer(text: "Что бы вы ни выбрали, обе записи останутся в истории. Приложение не удаляет чужое молча.")
            }
        }
    }

    /// Слияние сохраняет следы обеих: вторая помечается удалённой, а не стирается.
    private func merge() {
        right.deletedAt = Date()
        right.deletedBy = "слияние"
        left.note = [left.note, "объединено с записью \(right.authorName)"].compactMap { $0 }.joined(separator: " · ")
        resolved = true
        Haptics.success()
    }
}

private struct ConflictRow: View {
    let event: LogEvent

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            TGAvatar(initial: String(event.authorName.prefix(1)))
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("\(event.kind.title) · \(Fmt.clock(event.date))").textStyle(AppFont.bodyEmphasis)
                Text(event.authorName).textStyle(AppFont.caption)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Token.Size.tapTarget)
    }
}
