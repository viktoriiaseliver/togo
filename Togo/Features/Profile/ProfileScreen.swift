import SwiftUI
import SwiftData

/// Профиль собаки: питание, вес, уход, дрессировка.
/// Груминг и вес живут здесь и всплывают на главном только когда подошёл срок.
struct ProfileScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            if !canEdit {
                TGBanner(tone: .waiting, title: "Только чтение",
                         subtitle: "Профиль, питание и уход меняет тот, кому владелец выдал это право.",
                         systemImage: "lock")
            }
            if let dog {
                nutrition(dog)
                weight(dog)
                marker(dog)
                treatment(dog)
                links(dog)
            }
        }
        .disabled(false)
        .navigationTitle(dog?.name ?? "Профиль")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Питание

    private func nutrition(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "питание")
            LabeledField(label: "Корм") {
                TextField("Acana ягнёнок", text: Binding(get: { dog.foodBrand }, set: { dog.foodBrand = $0 }))
            }
            TGDivider()
            Stepper(value: Binding(get: { dog.portionGrams }, set: { dog.portionGrams = $0 }), in: 0...600, step: 5) {
                HStack {
                    Text("Порция").textStyle(AppFont.body)
                    Spacer()
                    Text("\(dog.portionGrams) г × \(dog.mealsPerDay)").textStyle(AppFont.numeric(15))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            Stepper(value: Binding(get: { dog.mealsPerDay }, set: { dog.mealsPerDay = $0 }), in: 1...4) {
                HStack {
                    Text("Кормлений в день").textStyle(AppFont.body)
                    Spacer()
                    Text("\(dog.mealsPerDay)").textStyle(AppFont.numeric(15))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            LabeledField(label: "Нельзя") {
                TextField("курица, кукуруза", text: Binding(
                    get: { dog.forbiddenFoods.joined(separator: ", ") },
                    set: { dog.forbiddenFoods = splitList($0) }
                ))
            }
            TGExplainer(text: "Порция подставляется в кнопку «Еда» на главном: жать нужно один раз, граммы уже подписаны.")
        }
        .disabled(!canEdit)
    }

    // MARK: Вес

    private func weight(_ dog: Dog) -> some View {
        NavigationLink { WeightScreen(dog: dog) } label: {
            TGCard {
                HStack {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Вес").textStyle(AppFont.cardTitle)
                        Text(dog.isWeightInRange ? "в коридоре, который назвал врач" : "вне коридора")
                            .textStyle(AppFont.caption)
                    }
                    Spacer()
                    Text(Fmt.weight(dog.weightKg)).textStyle(AppFont.numeric(22))
                    Image(systemName: "chevron.right")
                        .font(.system(size: Token.Size.iconSm, weight: .semibold))
                        .foregroundStyle(Token.Ink.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Чем маркируешь и чем платим

    private func marker(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "занятия")
            HStack {
                Text("Маркер").textStyle(AppFont.body)
                Spacer(minLength: Token.Space.s8)
                Picker("Маркер", selection: Binding(get: { dog.markerKind }, set: { dog.markerKind = $0 })) {
                    ForEach(MarkerKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Token.Ink.secondary)
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            LabeledField(label: "Чем платим") {
                TextField("сыр, индейка, мячик", text: Binding(
                    get: { dog.rewards.joined(separator: ", ") },
                    set: { dog.rewards = splitList($0) }
                ))
            }
            TGDivider()
            Toggle(isOn: Binding(get: { dog.trainingFoodFromPortion }, set: { dog.trainingFoodFromPortion = $0 })) {
                Text("Корм на занятия — из порции").textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            Stepper(value: Binding(get: { dog.sessionLengthMinutes }, set: { dog.sessionLengthMinutes = $0 }), in: 2...5) {
                HStack {
                    Text("Длина занятия").textStyle(AppFont.body)
                    Spacer()
                    Text("\(dog.sessionLengthMinutes) мин").textStyle(AppFont.numeric(15))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGExplainer(text: "Ограничения на лакомства нет. Есть дневная норма, часть которой собака зарабатывает, — это и снимает конфликт между занятиями и весом.")
        }
        .disabled(!canEdit)
    }

    // MARK: Лечение

    private func treatment(_ dog: Dog) -> some View {
        TGCard {
            Toggle(isOn: Binding(get: { dog.isOnTreatment }, set: { dog.isOnTreatment = $0 })) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Собака на лечении").textStyle(AppFont.body)
                    Text("даёт вкладку «Здоровье», дозы, окно натощак и отчёты").textStyle(AppFont.caption)
                }
            }
            TGExplainer(text: "Выключишь — вкладка исчезнет, а записи останутся в истории.")
        }
        .disabled(!canEdit)
    }

    // MARK: Переходы

    private func links(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            NavigationLink { FeedingScreen(dog: dog) } label: {
                TGListRow(title: "Питание и режим", value: "\(dog.dailyGrams) г в день", systemImage: "fork.knife")
            }
            TGDivider()
            NavigationLink { CareScreen(dog: dog) } label: {
                TGListRow(title: "Уход и напоминания", systemImage: "scissors")
            }
            TGDivider()
            NavigationLink { TransferMatrixScreen(dog: dog) } label: {
                TGListRow(title: "Перенос навыка", systemImage: "square.grid.3x3")
            }
            TGDivider()
            NavigationLink { TripSetupScreen(dog: dog) } label: {
                TGListRow(title: "Поездка", systemImage: "car")
            }
        }
        .buttonStyle(.plain)
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Уход и напоминания. Сезонное само знает про сезон:
/// капли от клещей молчат зимой и просыпаются в апреле.
struct CareScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var editing: CareTask?
    @State private var isAdding = false

    private var tasks: [CareTask] { dog?.careTasks ?? [] }

    var body: some View {
        TGScreen {
            if tasks.isEmpty {
                EmptyStateCard(
                    systemImage: "scissors",
                    title: "Напоминаний пока нет",
                    message: "Заведи то, что повторяется: когти, вычёсывание, антипаразитарку, прививки. Всё это придёт одним брифом в выбранный час, а не восемью пушами.",
                    actionTitle: dog == nil ? nil : "Добавить напоминание",
                    action: dog == nil ? nil : { isAdding = true }
                )
            } else {
                ForEach(CareCategory.allCases, id: \.self) { category in
                    let group = tasks.filter { $0.category == category }
                    if !group.isEmpty {
                        TGCard(spacing: 0) {
                            TGSectionHeader(title: category.title)
                            ForEach(group.sorted { ($0.daysUntilDue() ?? 999) < ($1.daysUntilDue() ?? 999) }) { task in
                                CareTaskRow(task: task, onDone: { complete(task) }, onEdit: { editing = task })
                                if task.id != group.last?.id { TGDivider() }
                            }
                        }
                    }
                }
                TGExplainer(text: "Всё это приходит одним брифом в выбранный час, а не восемью пушами. Прерывают только доза и окно натощак.")
            }
        }
        .navigationTitle("Уход")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить напоминание")
                }
            }
        }
        .sheet(isPresented: $isAdding) { CareTaskEditorSheet(dog: dog) }
        .sheet(item: $editing) { task in CareTaskEditorSheet(task: task, dog: dog) }
    }

    private func complete(_ task: CareTask) {
        task.lastDone = Date()
        task.snoozeCount = 0
        let event = LogEvent(kind: .care, authorName: appState.currentUserName)
        event.note = task.title
        event.careTaskID = task.id
        event.dog = dog
        context.insert(event)
        Haptics.success()
        appState.showUndo("Записано · \(task.title)", eventID: event.id)
    }
}

private struct CareTaskRow: View {
    let task: CareTask
    var onDone: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(task.title).textStyle(AppFont.bodyEmphasis)
                Text(task.detail).textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            VStack(alignment: .trailing, spacing: Token.Space.s4) {
                Text(dueLabel).textStyle(AppFont.micro.color(dueColor))
                if task.snoozeCount >= 2 {
                    Text("откладывали \(task.snoozeCount) раза").textStyle(AppFont.micro.color(Token.Ink.faint))
                }
            }
            Button("Сделали", action: onDone)
                .textStyle(AppFont.captionEmphasis.color(Token.Action.done))
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        // Тап по строке правит напоминание, кнопка справа его закрывает.
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "Поправить", onEdit)
    }

    private var dueLabel: String {
        guard task.isInSeason() else { return "вне сезона" }
        guard let days = task.daysUntilDue() else { return "—" }
        if days < 0 { return "просрочено" }
        if days == 0 { return "сегодня" }
        if days == 1 { return "завтра" }
        return "через \(Fmt.days(days))"
    }

    private var dueColor: Color {
        guard task.isInSeason() else { return Token.Ink.faint }
        guard let days = task.daysUntilDue() else { return Token.Ink.secondary }
        if days < 0 { return Token.Status.overdueText }
        if days <= 1 { return Token.Status.waitingText }
        return Token.Ink.secondary
    }
}
