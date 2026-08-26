import SwiftUI
import SwiftData

/// Стул — самая частая запись. Один тап в норме, два — когда что-то не так.
/// Формы записываются сразу, без «Сохранить»; кнопка подтверждения появляется
/// только когда отмечены особенности: такая запись уходит в медицинскую часть.
struct StoolSheet: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var form: StoolForm?
    @State private var flags: Set<StoolFlag> = []
    @State private var created: LogEvent?

    private var usual: StoolForm? { Diary.usualStool(dog?.events ?? []) }

    var body: some View {
        TGSheet(title: "Стул", subtitle: Fmt.clock(Date())) {
            if let usual {
                Button { pick(usual) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: usual.symbol).foregroundStyle(Token.Ink.silhouette)
                        Text("Как всегда · \(usual.title.lowercased())").textStyle(AppFont.cardTitle)
                        Spacer()
                        Image(systemName: "checkmark.circle").foregroundStyle(Token.Action.done)
                    }
                    .foregroundStyle(Token.Ink.primary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Token.Action.doneQuiet, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            TGSectionHeader(title: "форма")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(StoolForm.allCases, id: \.self) { candidate in
                    Button { pick(candidate) } label: {
                        VStack(spacing: 6) {
                            // Силуэты одним тёплым серо-коричневым: человек видит форму,
                            // а не цвет содержимого.
                            Image(systemName: candidate.symbol)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Token.Ink.silhouette)
                            Text(candidate.title).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Token.Ink.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous)
                                .fill(form == candidate ? Token.Action.primaryQuiet : Token.Surface.card)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            TGSectionHeader(title: "особенности", subtitle: "если ничего не отмечено — запись уже сохранена")
            TGChipGroup(
                items: StoolFlag.allCases,
                title: \.title,
                isSelected: { flags.contains($0) },
                tone: { $0.raisesAlarm ? .alarm : .neutral }
            ) { flag in
                toggle(flag)
            }

            if flags.contains(.blood) {
                TGBanner(
                    tone: .alarm,
                    title: "Кровь — это к врачу",
                    subtitle: Diary.suggestsVetReport(dog?.events ?? [])
                        ? "Второй жидкий с кровью подряд. Приложение может собрать выписку за эти дни."
                        : "Запись поднимется в истории и попадёт в отчёт врачу.",
                    systemImage: "cross.case"
                )
            }

            TGExplainer(text: flags.isEmpty
                ? "Бристольская шкала 1–7 существует, но только в базе и в отчёте врачу — выбирать её руками не нужно."
                : "Подтверждение нужно потому, что запись с особенностью уходит в медицинскую часть и попадает в отчёт врачу.")
        } footer: {
            // Кнопка появляется, только когда отмечены особенности: без них
            // форма уже записана, и подтверждать нечего.
            if !flags.isEmpty {
                TGButton(title: "Подтвердить запись") { confirm() }
            }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ flag: StoolFlag) {
        if flags.contains(flag) { flags.remove(flag) } else { flags.insert(flag) }
        Haptics.tap()
    }

    private func pick(_ candidate: StoolForm) {
        form = candidate
        Haptics.tap()
        // Форма пишется сразу: отменить можно тостом, «Сохранить» здесь лишний шаг.
        let event = ensureEvent()
        event.stoolForm = candidate
        if flags.isEmpty {
            appState.showUndo("Записано · Стул · \(candidate.title.lowercased())", eventID: event.id)
            dismiss()
        }
    }

    private func confirm() {
        let event = ensureEvent()
        event.stoolForm = form
        event.stoolFlags = flags
        Haptics.success()
        appState.showUndo("Записано · Стул", eventID: event.id)
        dismiss()
    }

    private func ensureEvent() -> LogEvent {
        if let created { return created }
        let event = LogEvent(kind: .stool, authorName: appState.currentUserName)
        event.dog = dog
        context.insert(event)
        created = event
        return event
    }
}

/// Универсальная шторка на числовую запись: еда, вода, лакомство.
struct QuantitySheet: View {
    let title: String
    let subtitle: String?
    let unit: String
    let step: Int
    let range: ClosedRange<Int>
    var explainer: String?
    var onSave: (Int) -> Void

    /// Начальное значение приходит снаружи, но живёт как состояние.
    /// Просто `@State var amount: Int` с присваиванием из параметра —
    /// смелл: SwiftUI обновит его только при первом создании, и это
    /// поведение легко принять за ошибку.
    @State private var amount: Int

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        subtitle: String?,
        unit: String,
        step: Int,
        range: ClosedRange<Int>,
        amount: Int,
        explainer: String? = nil,
        onSave: @escaping (Int) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.unit = unit
        self.step = step
        self.range = range
        self.explainer = explainer
        self.onSave = onSave
        _amount = State(initialValue: amount)
    }

    var body: some View {
        TGSheet(title: title, subtitle: subtitle) {
            TGCard {
                TGStepper(value: $amount, unit: unit, step: step, range: range)
            }
            if let explainer { TGExplainer(text: explainer) }
        } footer: {
            TGButton(title: "Записать") {
                onSave(amount)
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }
}


struct MealSheet: View {
    let dog: Dog?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        QuantitySheet(
            title: "Еда",
            subtitle: dog?.foodBrand.isEmpty == false ? dog?.foodBrand : nil,
            unit: "граммов",
            step: 5,
            range: 0...600,
            amount: dog?.servingGrams ?? 60,
            explainer: "Порция подставлена из профиля: жать нужно один раз, граммы уже подписаны."
        ) { grams in
            EventLog(context: context, appState: appState)
                .record(.meal, dog: dog, confirmation: "Записано · Еда \(grams) г") { event in
                    event.grams = grams
                    event.note = dog?.foodBrand.isEmpty == false ? dog?.foodBrand : nil
                }
        }
    }
}

struct WaterSheet: View {
    let dog: Dog?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        QuantitySheet(
            title: "Вода",
            subtitle: dog.map { "норма примерно \($0.waterNormMl) мл в день" },
            unit: "миллилитров",
            step: 20,
            range: 0...2000,
            amount: 100,
            explainer: "В поездке эта строка поднимается выше таймлайна: смена воды чаще всего даёт сбой именно тут."
        ) { ml in
            EventLog(context: context, appState: appState)
                .record(.water, dog: dog, confirmation: "Записано · Вода \(ml) мл") { event in
                    event.milliliters = ml
                }
        }
    }
}

struct TreatSheet: View {
    let dog: Dog?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        QuantitySheet(
            title: "Лакомство",
            subtitle: dog?.rewards.isEmpty == false ? dog?.rewards.joined(separator: " · ") : nil,
            unit: "граммов",
            step: 1,
            range: 0...200,
            amount: 5,
            explainer: "Лимита на лакомства нет. Есть дневная норма, часть которой собака зарабатывает, — это и снимает конфликт между занятиями и весом."
        ) { grams in
            EventLog(context: context, appState: appState)
                .record(.treat, dog: dog, confirmation: "Записано · Лакомство \(grams) г") { event in
                    event.grams = grams
                    event.fromPortion = dog?.trainingFoodFromPortion ?? true
                }
        }
    }
}

struct NoteSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var text = ""

    var body: some View {
        TGSheet(title: "Заметка", subtitle: "то, что не попадает ни в одну кнопку",
                hasUnsavedChanges: !text.trimmingCharacters(in: .whitespaces).isEmpty) {
            TGCard {
                TextEditor(text: $text)
                    .textStyle(AppFont.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }
        } footer: {
            TGButton(title: "Записать",
                     isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                EventLog(context: context, appState: appState)
                    .record(.note, dog: dog, confirmation: "Записано · Заметка") { event in
                        event.note = text
                    }
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }
}

/// Правка события. Удаление обратимо 5 секунд, и в истории остаётся след,
/// что запись была и кто её убрал.
struct EventEditSheet: View {
    let eventID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var events: [LogEvent]
    @Query private var careTasks: [CareTask]
    @Query private var medications: [Medication]
    @Query private var trainingSessions: [TrainingSession]

    private var event: LogEvent? { events.first { $0.id == eventID } }

    /// Свои записи ведут все, кому это разрешено; править и удалять
    /// уже записанное — отдельное право.
    private var canEdit: Bool { appState.can(.editRecords) }

    var body: some View {
        TGSheet(title: event?.kind.title ?? "Запись",
                      // «синхронизировано» отсюда убрано вместе с галочкой:
                      // обмена между устройствами пока нет, и говорить о нём
                      // нельзя.
                      subtitle: event.map { "Записала \($0.authorName) в \(Fmt.clock($0.date))" }) {
            if !canEdit {
                TGBanner(tone: .waiting, title: "Только чтение",
                         subtitle: "Твоя роль позволяет записывать своё, но не править уже записанное. Права выдаёт владелец в разделе «Семья».",
                         systemImage: "lock")
            }
            if let event {
                TGCard(padding: 4) {
                    VStack(spacing: 0) {
                        // Запись в будущем ломает всё, что считается
                        // от «последнего раза»: вердикт решит, что собака
                        // только что выходила. В живом дневнике такая
                        // запись уже появилась — время выставили вечером.
                        DatePicker("Время", selection: Binding(
                            get: { event.date },
                            set: { event.date = min($0, .now) }
                        ), in: ...Date(), displayedComponents: .hourAndMinute)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)

                        if event.kind == .walk {
                            TGDivider()
                            Stepper(value: Binding(
                                get: { (event.durationSeconds ?? 0) / 60 },
                                set: { event.durationSeconds = $0 * 60 }
                            ), in: 0...300, step: 5) {
                                HStack {
                                    Text("Сколько гуляли").textStyle(AppFont.body)
                                    Spacer()
                                    Text("\((event.durationSeconds ?? 0) / 60) мин")
                                        .textStyle(AppFont.numeric(15))
                                }
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                        }

                        if event.kind == .outing {
                            TGDivider()
                            Picker("Результат", selection: Binding(
                                get: { event.outcome ?? .none },
                                set: { event.outcome = $0 }
                            )) {
                                ForEach(OutingOutcome.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .textStyle(AppFont.body)
                            .frame(minHeight: Token.Size.tapTarget)
                        }

                        TGDivider()
                        HStack {
                            Text("Заметка").textStyle(AppFont.body)
                            Spacer()
                            TextField("добавить", text: Binding(
                                get: { event.note ?? "" },
                                set: { event.note = $0.isEmpty ? nil : $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .textStyle(AppFont.body)
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                    }
                    .padding(.horizontal, 12)
                }
                .disabled(!canEdit)

                originCard

                if canEdit {
                TGButton(title: "Удалить запись", variant: .destructive, size: .medium, systemImage: "trash") {
                    event.deletedAt = Date()
                    event.deletedBy = appState.currentUserName
                    Haptics.warning()
                    appState.showUndo("Удалено · \(event.kind.title)")
                    dismiss()
                }
                TGExplainer(text: "Удаление можно отменить 5 секунд. В истории останется след, что запись была и кто её убрал.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Откуда взялась запись.
    ///
    /// Связи с задачей ухода, препаратом и занятием писались в модель
    /// и не читались никем: из ленты нельзя было понять, какое напоминание
    /// отметили и какое занятие оставило след. Особенно это било по дозам:
    /// препарат могли переименовать, а в записи оставалось старое имя.
    @ViewBuilder
    private var originCard: some View {
        if let origin {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "откуда эта запись")
                TGListRow(title: origin.title, value: origin.detail,
                          systemImage: origin.symbol, accessory: .none)
                TGExplainer(text: origin.explainer)
            }
        }
    }

    private struct Origin {
        var title: String
        var detail: String?
        var symbol: String
        var explainer: String
    }

    private var origin: Origin? {
        guard let event else { return nil }

        if let id = event.careTaskID, let task = careTasks.first(where: { $0.id == id }) {
            return Origin(title: task.title, detail: task.kind.title, symbol: task.kind.symbol,
                          explainer: "Отмечено по напоминанию из ухода. Само напоминание правится там же — здесь меняется только эта запись.")
        }
        if let id = event.medicationID, let medication = medications.first(where: { $0.id == id }) {
            return Origin(title: medication.name, detail: medication.doseText, symbol: "pills",
                          explainer: "Приём по схеме лечения. Если препарат переименовали, здесь всё равно видно, какой именно отметили.")
        }
        if let id = event.trainingSessionID,
           let session = trainingSessions.first(where: { $0.id == id }) {
            let result = session.attempts > 0 ? "\(session.successes) из \(session.attempts)" : nil
            return Origin(title: "\(session.cue) · \(session.place)", detail: result, symbol: "target",
                          explainer: "След занятия. Само занятие лежит в «Занятиях и шагах» — там его можно и убрать.")
        }
        return nil
    }
}

