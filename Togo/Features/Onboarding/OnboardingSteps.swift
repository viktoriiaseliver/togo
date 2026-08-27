import SwiftUI
import SwiftData

// Экраны шагов онбординга. Сам порядок шагов и черновик собаки живут
// в `OnboardingFlow` — здесь только то, что человек видит на каждом шаге.
// Разделено при рефакторинг-чеке: в одном файле было больше пятисот строк,
// и правка одного шага заставляла листать все остальные.

struct WelcomeStep: View {
    var isReplay: Bool = false
    var onNext: () -> Void

    private let promises = [
        ("figure.walk.departure", "Выход и прогулка — разные вещи"),
        ("person.2", "Все в семье считают одно и то же"),
        ("cross.case", "Медкнижка включается, если понадобится"),
    ]

    var body: some View {
        TGScreen {
            VStack(alignment: .leading, spacing: Token.Space.s6) {
                Text("Дневник").textStyle(AppFont.display)
                Text("твоей собаки").textStyle(AppFont.display.color(Token.Action.primary))
            }
            .padding(.top, Token.Space.s32)

            Text("Когда выводили, когда кормили, каким был стул. Два тапа — и вечером никто ничего не выясняет.")
                .textStyle(AppFont.body.color(Token.Ink.secondary))

            VStack(spacing: Token.Space.s8) {
                ForEach(promises, id: \.1) { symbol, text in
                    TGCard(padding: Token.Space.s14) {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: symbol)
                                .font(.system(size: Token.Size.iconMd, weight: .medium))
                                .foregroundStyle(Token.Action.done)
                                .frame(width: Token.Space.s24)
                            Text(text).textStyle(AppFont.body)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.top, Token.Space.s8)
        } bottom: {
            TGButton(title: isReplay ? "Перечитать" : "Добавить собаку",
                     systemImage: isReplay ? "book" : "plus",
                     action: onNext)
            Text("Всё считается на телефоне. Аккаунт не нужен.")
                .textStyle(AppFont.micro)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Шаг 2 · кто у тебя живёт

struct DogStep: View {
    @Binding var draft: DogDraft
    var onNext: () -> Void

    var body: some View {
        TGScreen(title: "Кто у тебя живёт") {
            TGExplainer(text: "Обязательны только кличка и вес. Остальное можно пропустить и заполнить когда угодно.")

            TGCard(spacing: 0) {
                LabeledField(label: "Кличка") {
                    TextField("Стич", text: $draft.name)
                        .textInputAutocapitalization(.words)
                }
                TGDivider()
                LabeledField(label: "Вес") {
                    HStack(spacing: Token.Space.s4) {
                        TextField("4,1", text: $draft.weight).keyboardType(.decimalPad)
                        Text("кг").textStyle(AppFont.caption)
                    }
                }
                TGDivider()
                LabeledField(label: "Порода") {
                    TextField("можно пропустить", text: $draft.breed)
                }
                TGDivider()
                // Спрашиваем здесь: без пола не появится календарь цикла,
                // а искать его потом в профиле никто не будет.
                HStack {
                    Text("Кто это").textStyle(AppFont.body)
                    Spacer(minLength: Token.Space.s8)
                    Picker("Кто это", selection: $draft.sex) {
                        ForEach(DogSex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Token.Ink.secondary)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if draft.sex != .unknown {
                    TGDivider()
                    Toggle(isOn: $draft.isNeutered) {
                        Text(draft.sex == .male ? "Кастрирован" : "Стерилизована")
                            .textStyle(AppFont.body)
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGDivider()
                Toggle(isOn: $draft.hasBirthDate) {
                    Text("Дата рождения").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if draft.hasBirthDate {
                    DatePicker("Когда родился",
                               selection: Binding(get: { draft.birthDate ?? Date() },
                                                  set: { draft.birthDate = $0 }),
                               displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }

            TGCard {
                Toggle(isOn: $draft.isOnTreatment) {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Собака на лечении").textStyle(AppFont.body)
                        Text("включит медкнижку, схемы и окно натощак").textStyle(AppFont.caption)
                    }
                }
                TGExplainer(text: "Можно включить потом — вкладка «Здоровье» появится в тот же момент.")
            }
        } bottom: {
            TGButton(title: "Дальше", isEnabled: draft.isValid, action: onNext)
        }
    }
}

// MARK: - Шаг 3 · режим дня и питания

/// Сколько раз ест, во сколько встаёт, сколько граммов за раз.
/// Спрашиваем сразу: без этого приложение не сможет ни подсказать время
/// кормления, ни заметить, что собака переедает.
struct ScheduleStep: View {
    @Binding var draft: ScheduleDraft
    var onNext: () -> Void

    var body: some View {
        TGScreen(title: "Режим дня") {
            TGExplainer(text: "Приблизительно — приложение потом сверит это с тем, как вы кормите на самом деле, и поправит.")
            ScheduleEditor(draft: $draft, isVerbose: true)
        } bottom: {
            TGButton(title: "Дальше", action: onNext)
        }
    }
}

// MARK: - Шаг 4 · уход

/// Уход приложение не заводит за человека: у каждой собаки он свой.
/// Здесь только предложения, из которых отмечают нужное — и шаг можно
/// пропустить целиком.
struct CareStep: View {
    var onNext: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var dogs: [Dog]
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    var body: some View {
        TGScreen(title: "Что делаешь для ухода") {
            TGExplainer(text: "Отмечено то, что нужно почти всем. Зубы — потому что налёт твердеет за сутки, их чистят каждый день. Остальное у каждой собаки своё, и это можно поменять когда угодно.")

            ForEach(CareKind.allCases, id: \.self) { kind in
                let group = SeedData.careSuggestions.filter { $0.kind == kind }
                TGCard(spacing: 0) {
                    TGSectionHeader(title: kind.sectionTitle)
                    ForEach(group) { suggestion in
                        Button { toggle(suggestion) } label: {
                            HStack(spacing: Token.Space.s12) {
                                Image(systemName: chosen.contains(suggestion.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(chosen.contains(suggestion.id)
                                                     ? Token.Action.done : Token.Ink.faint)
                                VStack(alignment: .leading, spacing: Token.Space.s2) {
                                    Text(suggestion.title).textStyle(AppFont.body)
                                    Text(suggestion.detail)
                                        .textStyle(AppFont.caption)
                                        .wraps()
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if suggestion.id != group.last?.id { TGDivider() }
                    }
                }
            }
        } bottom: {
            TGButton(title: chosen.isEmpty ? "Пропустить" : "Дальше · \(chosen.count)") {
                save()
                onNext()
            }
        }
        .task {
            guard !loaded else { return }
            chosen = Set(SeedData.careSuggestions.filter(\.isDefault).map(\.id))
            loaded = true
        }
    }

    private func toggle(_ suggestion: SeedData.CareSuggestion) {
        if chosen.contains(suggestion.id) { chosen.remove(suggestion.id) } else { chosen.insert(suggestion.id) }
        Haptics.tap()
    }

    private func save() {
        guard let dog = dogs.first else { return }
        SeedData.addCare(chosen, to: dog, context: context)
    }
}

/// Строка «подпись — поле». Вынесена, потому что повторяется на трёх экранах.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).textStyle(AppFont.body).fixedSize()
                Spacer(minLength: Token.Space.s12)
                content
                    .multilineTextAlignment(.trailing)
                    .textStyle(AppFont.body)
            }
            // При крупном шрифте подпись и поле перестают помещаться рядом —
            // тогда поле уезжает под подпись, а не сжимается в щель.
            VStack(alignment: .leading, spacing: Token.Space.s4) {
                Text(label).textStyle(AppFont.caption)
                content
                    .multilineTextAlignment(.leading)
                    .textStyle(AppFont.body)
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }
}

// MARK: - Шаг 3 · кто ещё за ним ходит

struct FamilyStep: View {
    var onSkip: () -> Void
    var onInvite: () -> Void

    @Environment(\.modelContext) private var context
    @State private var role: FamilyRole = .coOwner

    /// Ссылки-приглашения пока нет: показывать её на онбординге —
    /// значит обещать обмен между телефонами, которого ещё не существует.
    private var inviteLink: String { "участник заводится в «Семье»" }

    var body: some View {
        TGScreen(title: "Кто ещё за ним ходит") {
            TGExplainer(text: "Можно пропустить и позвать позже.")

            TGCard {
                TGSectionHeader(title: "ссылка-приглашение")
                Text(inviteLink).textStyle(AppFont.numeric(17))
                TGDivider()
                TGSectionHeader(title: "роль")
                TGChipGroup(
                    items: [FamilyRole.coOwner, .caregiver, .helper],
                    title: \.title,
                    subtitle: { $0.permissionSummary },
                    isSelected: { $0 == role }
                ) { role = $0 }
                TGExplainer(text: "Ссылка живёт 24 часа. Роль выбираешь заранее — принявший не сможет её поменять.")
            }

            TGCard {
                Text("Бесплатно — одна собака и два человека").textStyle(AppFont.cardTitle)
                Text("Этого хватает паре: и лечение, и окно натощак, и защита от двойной дозы. За безопасность собаки денег не берём.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Отправить ссылку", systemImage: "square.and.arrow.up") {
                invite()
                onInvite()
            }
            TGButton(title: "Пока сама", variant: .quiet, size: .medium, action: onSkip)
        }
    }

    private func invite() {
        let member = FamilyMember(name: "Приглашение", role: role)
        member.inviteToken = UUID().uuidString
        member.inviteExpiresAt = Date().addingTimeInterval(24 * 3600)
        context.insert(member)
    }
}

// MARK: - Шаг 4 · разрешение на уведомления

/// Разрешение спрашиваем не на старте, а когда уже понятно, за что оно.
/// Отказ ничего не ломает: дневник работает целиком без уведомлений.
struct NotificationsPrimingStep: View {
    var onDone: () -> Void

    @Environment(Settings.self) private var settings
    @State private var isRequesting = false

    var body: some View {
        TGScreen(title: "Что будет прерывать") {
            TGExplainer(text: "Прерывают ровно три вещи. Всё остальное ждёт утреннего брифа — это единственный способ не превратить дневник в источник тревоги.")

            VStack(spacing: Token.Space.s8) {
                InterruptRow(symbol: "pills", title: "Доза по часам",
                             detail: "и то только если собака на лечении")
                InterruptRow(symbol: "clock.badge.exclamationmark", title: "Окно натощак",
                             detail: "еда внутри окна мешает всасыванию")
                InterruptRow(symbol: "bell.badge", title: "Лестница эскалации",
                             detail: "если дозу не отметили — сначала дежурному, потом остальным")
            }

            TGCard {
                Text("Один пуш в \(Fmt.clock(minuteOfDay: settings.briefHour * 60))").textStyle(AppFont.cardTitle)
                Text("Груминг, антипаразитарка, прививки, взвешивание — не восемь пушей, а один бриф в выбранный час. Час можно сдвинуть в настройках.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Разрешить уведомления", systemImage: "bell", isEnabled: !isRequesting) {
                Task { await request() }
            }
            TGButton(title: "Не сейчас", variant: .quiet, size: .medium) {
                settings.notificationsAsked = true
                onDone()
            }
        }
    }

    private func request() async {
        isRequesting = true
        _ = await NotificationCenterService.requestAuthorization()
        settings.notificationsAsked = true
        isRequesting = false
        onDone()
    }
}

struct InterruptRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        TGCard(padding: Token.Space.s14) {
            TGIconRow(symbol: symbol, title: title, detail: detail,
                      tint: Token.Status.waitingText)
        }
    }
}


/// Конец повторного прохождения: ничего не создаём, просто выпускаем обратно.
struct HowItWorksReplayEnd: View {
    var onDone: () -> Void

    var body: some View {
        TGScreen(title: "Это всё") {
            TGCard {
                Text("Инструкция всегда под рукой").textStyle(AppFont.cardTitle)
                Text("«Настройки → Как это работает» открывает тот же текст в любой момент. Отдельной справки в приложении нет: объяснения стоят там, где возникает вопрос.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Вернуться к дневнику", action: onDone)
        }
    }
}
