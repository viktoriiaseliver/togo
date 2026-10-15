import SwiftUI
import SwiftData

// Экраны шагов онбординга. Сам порядок шагов и черновик собаки живут
// в `OnboardingFlow` — здесь только то, что человек видит на каждом шаге.
// Разделено при рефакторинг-чеке: в одном файле было больше пятисот строк,
// и правка одного шага заставляла листать все остальные.

struct WelcomeStep: View {
    var isReplay: Bool = false
    var onNext: () -> Void
    /// Вход ветки «меня позвали» — второй путь с первого же экрана.
    ///
    /// До 14.10.2026 его не было вовсе: приглашённый шёл онбордингом
    /// владельца и заводил **свою** собаку. Решение Виктории, принятое
    /// рисунком в макете: «своей собаки не создаём».
    ///
    /// Необязательное замыкание, а не обязательное, нарочно: при
    /// перечитывании (`isReplay`) ветка не показывается — человек
    /// с дневником уже не «позванный», и предлагать ему чужой
    /// дневник значит звать его туда, откуда он не вернётся
    /// без потери своего.
    var onJoin: (() -> Void)?

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
                                .foregroundStyle(Token.Action.doneText)
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
            // Вторая дорога, а не вторая кнопка того же действия:
            // «Добавить собаку» заводит СВОЙ дневник, «Меня позвали» —
            // присоединяет к чужому. Форма у них разная нарочно
            // (главная кнопка против текстовой), потому что два
            // одинаково выглядящих действия на одном экране мы уже
            // проходили: 22.09 человек нажал видимое «Пригласить
            // человека» и завёл участника вместо приглашения.
            if !isReplay, let onJoin {
                Button("Меня позвали в семью", action: onJoin)
                    .textStyle(AppFont.bodyEmphasis.color(Token.Action.primary))
                    .frame(maxWidth: .infinity)
                    .padding(.top, Token.Space.s4)
            }
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
    /// Пропустить собаку. Есть не всегда: при повторном прохождении
    /// пропускать нечего — собака уже заведена.
    var onSkip: (() -> Void)?

    /// Фокус поля веса — единственного `.decimalPad` на этом шаге.
    /// `Bool`, а не перечисление: на экране одно числовое поле, и форма
    /// условия названа по тому, что есть, а не по тому, что может быть.
    @FocusState private var весВФокусе: Bool

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
                            .focused($весВФокусе)
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
        }
        // **Низ отдан системе, а не слоту `TGScreen`, и только здесь.**
        //
        // Слот каркаса считает запас от высоты САМОЙ панели
        // (`TGScaffolds.swift:177` `запасПодНизом = высотаНиза + s24`),
        // а панель в нём — сосед по `ZStack`, не inset. Клавиатура
        // поднимает панель и высоту её не меняет: запас остаётся
        // прежним, и содержимое уходит под панель. Замер с кадра:
        // `minY` панели 446 против 772 у экрана без клавиатуры,
        // Δ 326 pt содержимого недостижимо даже полной прокруткой.
        // Здесь это «Дата рождения» и «Собака на лечении» — два
        // последних блока формы.
        //
        // `safeAreaInset` складывается с клавиатурной безопасной
        // областью, поэтому запас растёт вместе с ней сам.
        //
        // # Почему один экран, а не каркас
        //
        // `safeAreaInset` рядом с полем ввода в этом проекте
        // не измерен ни разу: все четыре живых места
        // (`TodayScreen:149`, `VetSummaryScreen:283`,
        // `SitterBriefingScreen:58`, `OnboardingFlow:119`) — экраны
        // БЕЗ полей ввода. Что сложение документировано Apple, здесь
        // не равно «измерено». Правка стоит на одном экране нарочно:
        // не сойдётся — вариант мёртв ценой одного адреса, а не
        // четырнадцати слотов.
        //
        // # Вид не меняется ни на точку
        //
        // `VStack(spacing: s8)` и оба отступа — те же, что у слота
        // (`TGScaffolds.swift:196-198`). Подложки нет и здесь: она
        // у низа `TGScreen` — решение дизайна, и принимать его
        // попутно нельзя.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Token.Space.s8) {
                TGButton(title: "Дальше", isEnabled: draft.isValid, action: onNext)
                if let onSkip {
                    Button("Пока без собаки", action: onSkip)
                        .textStyle(AppFont.caption)
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
                }
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.bottom, Token.Space.s8)
        }
        // Выход с цифровой клавиатуры. У `.decimalPad` нет клавиши
        // возврата, и до 15.10 убрать её на этом шаге было нечем:
        // человек, набравший вес, упирался в экран, у которого две
        // последние строки формы под панелью.
        //
        // Стоит ПОСЛЕ `safeAreaInset` нарочно: это две разные правки
        // одного шага, и проверяются они одним кадром — выход без
        // вёрстки оставляет человека без «Даты рождения», вёрстка без
        // выхода оставляет его с клавиатурой навсегда.
        .готовоНадКлавиатурой { весВФокусе = false }
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
            TGExplainer(text: "Приблизительно — приложение сверит это с тем, как ты кормишь на самом деле, и поправит.")
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
    /// В просмотре — ложно, и тогда отмеченное никуда не уезжает.
    ///
    /// **Своя защита, а не общая с созданием собаки.** `saveDog()`
    /// в просмотре молчит потому, что собаки нет; здесь собака ЕСТЬ —
    /// настоящая, живая, та, у которой весь дневник. Без этого
    /// параметра человек, заглянувший в онбординг со своего телефона,
    /// получил бы на неё чужие дела ухода, а инструмент сверки макета
    /// испортил бы ему данные.
    var пишемВБазу: Bool = true
    var onNext: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var dogs: [Dog]
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    var body: some View {
        TGScreen(title: "Что делаешь для ухода") {
            TGExplainer(text: "Отмечено то, что нужно почти всем. Зубы — каждый день: налёт твердеет за сутки. Остальное у каждой собаки своё и меняется когда угодно.")

            ForEach(CareKind.allCases, id: \.self) { kind in
                let group = SeedData.careSuggestions.filter { $0.kind == kind }
                TGCard(spacing: 0) {
                    TGSectionHeader(title: .готовая(kind.sectionTitle))
                    ForEach(group) { suggestion in
                        Button { toggle(suggestion) } label: {
                            HStack(spacing: Token.Space.s12) {
                                Image(systemName: chosen.contains(suggestion.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(chosen.contains(suggestion.id)
                                                     ? Token.Action.doneText : Token.Ink.secondary)
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
        guard пишемВБазу, let dog = dogs.first else { return }
        SeedData.addCare(chosen, to: dog, context: context)
    }
}

/// Строка «подпись — поле». Вынесена, потому что повторяется на трёх экранах.
///
/// Подпись отдаётся полю и как accessibility-имя: без этого VoiceOver
/// называет поле плейсхолдером («Стич», «4,1», «+33…»), а два телефона
/// подряд на экране «Если что-то случилось» звучат одинаково.
/// `spokenLabel` — для случаев, когда видимая подпись коротка нарочно
/// («Телефон» под заголовком «Ветеринар»), а вслух нужна полная.
struct LabeledField<Content: View>: View {
    let label: String
    var spokenLabel: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).textStyle(AppFont.body).fixedSize()
                Spacer(minLength: Token.Space.s12)
                content
                    .multilineTextAlignment(.trailing)
                    .textStyle(AppFont.body)
                    .accessibilityLabel(spokenLabel ?? label)
            }
            // При крупном шрифте подпись и поле перестают помещаться рядом —
            // тогда поле уезжает под подпись, а не сжимается в щель.
            VStack(alignment: .leading, spacing: Token.Space.s4) {
                Text(label).textStyle(AppFont.caption)
                content
                    .multilineTextAlignment(.leading)
                    .textStyle(AppFont.body)
                    .accessibilityLabel(spokenLabel ?? label)
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }
}

// MARK: - Шаг 3 · кто ещё за ним ходит

struct FamilyStep: View {
    /// В просмотре — ложно: `invite()` ниже вставляет участника
    /// в хранилище, и в чужом дневнике он остался бы навсегда.
    var пишемВБазу: Bool = true
    var onSkip: () -> Void
    var onInvite: () -> Void

    @Environment(\.modelContext) private var context
    @State private var role: FamilyRole = .coOwner

    /// Ссылки-приглашения пока нет: показывать её на онбординге —
    /// значит обещать обмен между телефонами, которого ещё не существует.
    private var inviteLink: String { String(localized: "участник заводится в «Семье»") }

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
                // Строка снята целиком 08.10.2026: она несла ДВА обещания,
                // и ни одно не исполнено.
                //
                // «принявший не сможет её поменять» — обещание про ЧУЖОЙ
                // телефон. Слой обмена о правах не спрашивает вовсе
                // (`Permission`/`FamilyRole`/`can(` — ноль вхождений во всех
                // девяти файлах `TogoShared/Sync/`), а на своём телефоне
                // гость заводит себе карточку со-владельца и жмёт «Это я»:
                // ворот на права нет ни у «Добавить человека»
                // (`FamilyScreen:55`, только `ProGate`), ни у «Это я» (`:420`).
                //
                // «Ссылка живёт 24 часа» — тоже не исполнено: `CKShare` сам
                // не истекает, срок пришлось бы хранить у себя, и
                // `accessExpiresAt` человеком не пишется нигде.
                //
                // Снято, а не переписано, нарочно: правка литерала завела бы
                // новый ключ и пробелы на en/fr/uk, а у француза русская
                // строка читается как решение, а не как пропуск. Снятие
                // возвращает в каталог уже оплаченный перевод (ключ был
                // переведён на все четыре языка) и уменьшает долг.
                //
                // Вернуть эту строку можно после того, как срок начнут
                // хранить у себя, а роль — опознавать из `CKShare`.
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
        guard пишемВБазу else { return }
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
    /// В просмотре — ложно, и тогда шаг ничего не меняет.
    ///
    /// Здесь не хранилище, а две вещи вне его, и обе необратимы
    /// по-своему: `notificationsAsked` в `UserDefaults` и **системный
    /// запрос разрешения**. Второй хуже: у человека он спросит
    /// по-настоящему, а в прогоне поднимет модальный алерт, который
    /// никто не ждёт и который останавливает весь дальнейший заход.
    var пишемВБазу: Bool = true
    var onDone: () -> Void

    @Environment(Settings.self) private var settings
    @State private var isRequesting = false

    var body: some View {
        TGScreen(title: "Что будет прерывать") {
            TGExplainer(text: "Прерывают ровно три вещи. Всё остальное ждёт утра — это единственный способ не превратить дневник в источник тревоги.")

            VStack(spacing: Token.Space.s8) {
                InterruptRow(symbol: "pills", title: "Доза по часам",
                             detail: "и то только если собака на лечении")
                InterruptRow(symbol: "clock.badge.exclamationmark", title: "Окно натощак",
                             detail: "еда внутри окна мешает всасыванию")
                InterruptRow(symbol: "bell.badge", title: "Лестница эскалации",
                             detail: "если дозу не отметили — сначала дежурному, потом остальным")
            }

            TGCard {
                Text("Одно напоминание в \(Fmt.clock(minuteOfDay: settings.briefHour * 60))").textStyle(AppFont.cardTitle)
                Text("Груминг, антипаразитарка, прививки, взвешивание — не восемь напоминаний, а одно в выбранный час. Час можно сдвинуть в настройках.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Разрешить уведомления", systemImage: "bell", isEnabled: !isRequesting) {
                Task { await request() }
            }
            TGButton(title: "Не сейчас", variant: .quiet, size: .medium) {
                if пишемВБазу { settings.notificationsAsked = true }
                onDone()
            }
        }
    }

    private func request() async {
        // В просмотре кнопка доводит до конца шага и ничего не просит:
        // спрашивать разрешение у человека, который зашёл посмотреть,
        // значит задать ему вопрос от его же имени.
        guard пишемВБазу else { return onDone() }
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
            TGIconRow(symbol: symbol, title: .готовая(title), detail: .готовая(detail),
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
                Text("Тот же текст всегда есть в «Настройки → Как это работает». Отдельной справки нет: объяснения стоят там, где возникает вопрос.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Вернуться к дневнику", action: onDone)
        }
    }
}
