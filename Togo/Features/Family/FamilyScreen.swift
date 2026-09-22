import SwiftUI
import SwiftData
import CloudKit

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
    @State private var handingOver: FamilyMember?
    @State private var editingBriefing = false
    @State private var showPaywall = false
    @State private var invite: DiaryInvite?
    @State private var inviteFailure: String?
    @State private var isPreparingInvite = false

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var duty: FamilyMember? { members.first(where: \.isOnDuty) }
    private var canManageFamily: Bool { appState.can(.manageFamily) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if let conflict = mergeConflict {
                    MergeConflictCard(left: conflict.0, right: conflict.1)
                }
                if members.filter({ !$0.isMe }).isEmpty {
                    EmptyStateCard(
                        systemImage: "person.2",
                        title: "Пока вы вдвоём с собакой",
                        message: "Заведи тех, кто тоже за ней ходит: совладельца, ситтера, ребёнка или врача. Роль и права выбираешь ты — сам он их не поменяет.",
                        actionTitle: nil,
                        action: nil
                    )
                }
                if let duty { dutyCard(duty) }
                membersCard
                if canManageFamily { inviteCard }
                sharedDiaryLink
                sitterBriefingLink
                rolesExplainer
            } bottom: {
                TGButton(title: "Добавить человека", systemImage: "person.badge.plus") {
                    if store.isPro || members.count < 2 { showInvite = true } else { showPaywall = true }
                }
            }
            .navigationTitle("Семья")
            .usageScreen(.family)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { SettingsToolbarItem() }
            .sheet(isPresented: $showInvite) { InviteSheet() }
            .sheet(isPresented: $editingBriefing) { SitterBriefingEditor(dog: dog) }
            .sheet(item: $handingOver) { member in
                ShiftHandoverSheet(summary: summary(for: member),
                                   successor: successor(after: member)?.name) {
                    passDuty(from: member)
                }
            }
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
                Button("передать") { handingOver = member }
                    .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
            }
        }
    }

    /// Итог смены собирается из режима дня, а не из своего учёта:
    /// свой разошёлся бы с дневником на второй же день.
    private func summary(for member: FamilyMember) -> ShiftSummary {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
        let end = member.dutyUntil
            ?? calendar.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
        let shift = Shift(person: member.name, from: start, to: end)

        let plan = DayPlanBuilder.items(dog: dog, events: dog?.events ?? [], now: .now)
            .map { (id: $0.id, title: $0.title, due: $0.time, isDone: $0.isDone) }

        return ShiftReport.build(shift: shift, plan: plan, events: dog?.events ?? [])
    }

    /// Кому перейдёт открытое.
    private func successor(after current: FamilyMember) -> FamilyMember? {
        members.first { $0.can(.giveDose) && $0.id != current.id }
    }

    /// Передача дежурства — одно действие, а не форма. Но с явным
    /// «принять»: незакрытое не должно повиснуть ничьим.
    private func passDuty(from current: FamilyMember) {
        guard let next = successor(after: current) else { return }
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

    /// Отправить приглашение — здесь, а не только внутри «Общего дневника».
    ///
    /// Тестер 22.09: «Человека создала, а добавить или пригласить не могу».
    /// Настоящее приглашение (`CKShare` через лист «Поделиться») работало,
    /// но лежало за двумя экранами, а на виду стояла кнопка с тем же
    /// названием, которая заводит участника только на этом телефоне.
    /// Двух одинаково названных действий быть не должно: отправка стоит
    /// там, где её ищут — рядом со списком семьи.
    @ViewBuilder
    private var inviteCard: some View {
        TGCard {
            TGSectionHeader(title: "позвать в дневник")
            if !SharedDiarySettings.isOn {
                TGExplainer(text: "Приглашение уходит через общий дневник — пока он выключен, отправлять нечего.")
                NavigationLink { SharedDiaryScreen() } label: {
                    TGListRow(title: "Включить общий дневник",
                              systemImage: "arrow.triangle.2.circlepath", accessory: .none)
                }
                .buttonStyle(.plain)
            } else if let invite {
                ShareLink(item: invite,
                          preview: SharePreview("Дневник · \(dog?.name ?? "собаки")",
                                                image: Image(systemName: "pawprint.fill"))) {
                    TGListRow(title: "Отправить приглашение",
                              systemImage: "square.and.arrow.up", accessory: .none)
                }
                .buttonStyle(.plain)
                TGExplainer(text: "Выбери, кому: маме, мужу, ситтеру. Откроет только он, со своего iCloud, и ему нужен Togo на телефоне.")
            } else {
                TGButton(title: isPreparingInvite ? "Готовлю…" : "Создать приглашение",
                         systemImage: "person.badge.plus",
                         isEnabled: !isPreparingInvite) {
                    Task { await makeInvite() }
                }
            }
            if let inviteFailure {
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: inviteFailure,
                         systemImage: "exclamationmark.triangle")
            }
        }
    }

    /// Одна общая ссылка на зону: `FamilyShare.invite` сам вернёт уже
    /// созданную, если делились раньше, — новая отрезала бы принявших.
    private func makeInvite() async {
        isPreparingInvite = true
        inviteFailure = nil
        defer { isPreparingInvite = false }
        do {
            let share = try await FamilyShare.invite(dogName: dog?.name ?? "собаки")
            invite = DiaryInvite(share: share)
        } catch {
            inviteFailure = error.localizedDescription
        }
    }

    /// Общий дневник стоит первым делом после списка участников:
    /// участник без обмена — это имя в поле «автор», и только.
    private var sharedDiaryLink: some View {
        NavigationLink { SharedDiaryScreen() } label: {
            TGCard {
                TGListRow(title: "Общий дневник",
                          value: SharedDiarySettings.isOn ? "включён" : "выключен",
                          systemImage: "arrow.triangle.2.circlepath")
                TGExplainer(text: SharedDiarySettings.isOn
                            ? "Записи с обоих телефонов сходятся в одну ленту."
                            : "Пока выключен, участник — это только имя в поле «автор»: отмечать он может лишь с этого телефона.")
            }
        }
        .buttonStyle(.plain)
    }

    /// Инструкция: хозяйка пишет, ситтер читает. Одна и та же строка —
    /// потому что это одно и то же место, а не два разных экрана
    /// в разных концах приложения.
    @ViewBuilder
    private var sitterBriefingLink: some View {
        if appState.can(.manageFamily) {
            Button { editingBriefing = true } label: {
                TGCard {
                    TGListRow(title: "Инструкция ситтеру",
                              value: hasBriefing ? "написана" : "не написана",
                              systemImage: "list.bullet.rectangle")
                    TGExplainer(text: "Пять строк, которые он прочтёт за минуту: еда, доза, прогулки, запреты, эскалация.")
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { SitterBriefingScreen(dog: dog) } label: {
                TGCard {
                    TGListRow(title: "Инструкция", systemImage: "list.bullet.rectangle")
                    TGExplainer(text: "Что важно знать про эту собаку. Написала хозяйка.")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var hasBriefing: Bool {
        guard let dog else { return false }
        return !dog.sitterFood.isEmpty || !dog.sitterDose.isEmpty || !dog.sitterWalks.isEmpty
            || !dog.sitterForbidden.isEmpty || !dog.sitterEscalation.isEmpty
    }

    private var rolesExplainer: some View {
        TGCard {
            Text("Роли — не лестница").textStyle(AppFont.cardTitle)
            Text("Врач читает много и не пишет; ребёнок пишет бытовое и не видит медицинского. Дежурный получает напоминания — и только он.")
                .textStyle(AppFont.caption)
            NavigationLink("Как выглядит вид ситтера") { SitterPreviewScreen(dog: dog) }
                .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
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
            TGAvatar(initial: member.initial, tint: member.isMe ? Token.Action.doneQuiet : Token.Action.done)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(member.name).textStyle(AppFont.bodyEmphasis)
                Text(member.hasCustomPermissions
                     ? "\(member.role.title.lowercased()) · права изменены"
                     : "\(member.role.title.lowercased()) · \(member.role.permissionSummary)")
                    .textStyle(AppFont.caption)
                    .lineLimit(2)
            }
            Spacer(minLength: Token.Space.s8)
            // Локальный токен не знает ничего о том, принято ли
            // приглашение: принимают через CKShare, по iCloud-личности.
            // Поэтому «ждёт» было обещанием, а «истекло» через сутки —
            // неправдой дважды. Пока обмен выключен, верно одно: человек
            // живёт на этом телефоне.
            if member.isInvitePending && !SharedDiarySettings.isOn {
                Text("только здесь")
                    .textStyle(AppFont.micro.color(Token.Ink.secondary))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .foregroundStyle(Token.Ink.secondary)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

struct MemberScreen: View {
    let member: FamilyMember

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// Права выдаёт тот, у кого есть право их выдавать.
    private var canManage: Bool { appState.can(.manageFamily) }

    var body: some View {
        TGScreen {
            TGCard {
                TGSectionHeader(title: "роль", subtitle: "это пресет прав, а не потолок")
                TGChipGroup(
                    items: FamilyRole.allCases,
                    title: \.title,
                    subtitle: { $0.permissionSummary },
                    isSelected: { $0 == member.role }
                ) { role in
                    guard canManage else { return }
                    member.role = role
                    member.resetPermissions()
                    Haptics.tap()
                }
                .disabled(!canManage)
            }

            TGCard {
                HStack {
                    TGSectionHeader(
                        title: "что разрешено",
                        subtitle: member.hasCustomPermissions
                            ? "права выданы поимённо, роль их больше не задаёт"
                            : "по роли «\(member.role.title.lowercased())»"
                    )
                    if member.hasCustomPermissions, canManage {
                        Button("По роли") {
                            member.resetPermissions()
                            Haptics.tap()
                        }
                        .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
                    }
                }
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionToggle(
                        permission: permission,
                        isOn: member.can(permission),
                        isEditable: canManage && !(member.role == .owner && permission.isOwnerOnlyByDefault)
                    ) { granted in
                        var next = member.permissions
                        if granted { next.insert(permission) } else { next.remove(permission) }
                        member.permissions = next
                        if member.isMe { appState.adopt(member) }
                        Haptics.tap()
                    }
                    if permission != Permission.allCases.last { TGDivider() }
                }
                if !canManage {
                    TGExplainer(text: "Менять права может тот, у кого есть право «Приглашать и менять роли». Обычно это владелец.")
                } else if member.role == .owner {
                    TGExplainer(text: "У владельца нельзя снять управление семьёй — иначе права станет некому раздавать.")
                }
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
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Одно право — один переключатель. Выключенное право видно и объяснено,
/// а не просто отсутствует в списке.
private struct PermissionToggle: View {
    let permission: Permission
    let isOn: Bool
    let isEditable: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(permission.title)
                    .textStyle(AppFont.body)
                    .wraps()
                Text(permission.detail)
                    .textStyle(AppFont.caption)
                    .wraps()
            }
        }
        .disabled(!isEditable)
        .frame(minHeight: Token.Size.tapTarget)
    }
}

/// Приглашение живёт 24 часа, роль фиксируется до принятия.
struct InviteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var role: FamilyRole = .caregiver
    @State private var name = ""

    private let token = String(UUID().uuidString.prefix(6))

    var body: some View {
        TGSheet(title: "Новый участник", subtitle: "имя, роль и права") {
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
                TGSectionHeader(title: "что это даёт")
                TGExplainer(text: "Здесь заводится участник: имя станет автором записей, права решат, что ему можно. Работает и с одним телефоном на семью, если передавать его из рук в руки.")
                TGExplainer(text: "Чтобы он отмечал со своего телефона, включи общий дневник и отправь приглашение — «позвать в дневник» в списке семьи.")
            }
        } footer: {
            TGButton(title: "Добавить", isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                create()
                dismiss()
            }
        }
        .presentationDetents([.large])
    }

    /// Участник заводится сразу и целиком: приглашения по ссылке нет,
    /// потому что нечему приходить — обмена между устройствами ещё нет.
    /// Токен всё равно записываем: он понадобится, когда обмен появится,
    /// и заводить его задним числом будет неоткуда.
    private func create() {
        let member = FamilyMember(name: name.trimmingCharacters(in: .whitespaces),
                                  role: role)
        member.inviteToken = token
        member.inviteExpiresAt = Date().addingTimeInterval(24 * 3600)
        context.insert(member)
        try? context.save()
        Haptics.success()
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
                        Text(time)
                            .textStyle(AppFont.numeric(13, weight: .medium))
                            .fixedSize()
                            .frame(minWidth: 44, alignment: .leading)
                        Text(title).textStyle(AppFont.body)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: Token.Size.iconSm, weight: .semibold))
                            .foregroundStyle(Token.Ink.secondary)
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
        .navigationBarTitleDisplayMode(.large)
    }

    private var plan: [(String, String)] {
        [("08:00", "Утренний выход"),
         ("08:30", "Еда · \(dog?.servingGrams ?? 60) г"),
         ("13:00", "Прогулка 30 мин"),
         ("18:30", "Еда · \(dog?.servingGrams ?? 60) г")]
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
                TGExplainer(text: "Что ни выбери, обе записи останутся в истории. Приложение не удаляет чужое молча.")
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
