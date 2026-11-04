import SwiftUI
import SwiftData

/// Начало дня с собакой: на сколько выходим и что взять.
struct DayOutStartSheet: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var hours = 4

    private var packing: DayOutPlan.Packing? {
        dog.map { DayOutPlan.packing(for: $0, hours: hours) }
    }

    var body: some View {
        TGSheet(title: "Собака со мной",
                subtitle: "режим на день по делам, в дороге или в гостях",
                closeTitle: "Отмена") {
            TGCard(spacing: 0) {
                Stepper(value: $hours, in: 1...16) {
                    HStack {
                        Text("Примерно на").textStyle(AppFont.body)
                        Spacer()
                        Text(String(localized: "\(hours) часов"))
                            .textStyle(AppFont.numeric(17))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Точность не нужна: цифра нужна, чтобы посчитать еду и не напоминать про воду каждые десять минут. Задержишься — режим просто продолжит идти.")
            }

            if let packing { packingCard(packing) }
            behaviourCard
        } footer: {
            TGButton(title: "Поехали", systemImage: "figure.walk.motion") { start() }
        }
        .presentationDetents([.large])
        .usageScreen(.dayOut)
    }

    private func packingCard(_ packing: DayOutPlan.Packing) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "что взять",
                            subtitle: "посчитано по её расписанию, а не на глаз")
            // Три разных ответа, и до 25.10 два последних сливались
            // в «0 г и запас»: ноль граммов при живых кормлениях —
            // это ненаписанная норма, а не «корм не нужен».
            row("Корм", packing.meals == 0
                ? "не понадобится — кормления в это окно не попадают"
                : packing.totalGrams == 0
                    ? "\(String(localized: "\(packing.meals) кормлений")) — сколько, скажет дневная норма, а она не записана"
                    : "\(packing.totalGrams) г · \(String(localized: "\(packing.meals) кормлений")) и запас")
            TGDivider()
            row("Вода", "предлагать каждые \(Fmt.duration(DayOutPlan.waterEvery))")
            TGDivider()
            row("Пакеты", "по числу выходов — их будет больше обычного")
        }
    }

    private var behaviourCard: some View {
        TGCard {
            TGSectionHeader(title: "что изменится")
            TGIconRow(symbol: "fork.knife", title: "Кормление по часам",
                      detail: "дома миска стоит и собака подходит сама, в разъездах кормят когда вспомнили")
            TGIconRow(symbol: "drop", title: "Напоминание про воду",
                      detail: "дома вода есть всегда, на улице её нет — и собака терпит молча")
            TGIconRow(symbol: "bell.slash", title: "Без «просится»",
                      detail: "она весь день рядом и выходит постоянно; вердикт в такой день считает ерунду")
            TGIconRow(symbol: "moon.zzz", title: "Разговор про завтра",
                      detail: "после долгого дня собака отсыпается — приложение скажет об этом заранее, а не когда ты уже волнуешься")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).textStyle(AppFont.body)
            Spacer(minLength: Token.Space.s8)
            Text(value)
                .textStyle(AppFont.caption)
                .multilineTextAlignment(.trailing)
                .wraps()
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    private func start() {
        guard let dog else { return }
        let day = DayOut(plannedHours: hours)
        day.dog = dog
        context.insert(day)
        guard context.persist(otherwise: { context.delete(day) }) else {
            // Была только вибрация — при том, что УСПЕХ этого же
            // действия говорится словом строкой ниже. Половина пары
            // молчала.
            Haptics.warning()
            appState.showFailure(
                String(localized: "Режим не включился · нажми ещё раз"))
            return
        }
        Haptics.success()
        appState.showUndo(String(localized: "Режим включён · собака с тобой"))
        dismiss()
    }
}

/// Итог дня: сколько вышло и что это значит для завтра.
struct DayOutSummarySheet: View {
    let day: DayOut

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var note = ""
    @State private var удаляем = false

    private var hours: Double { day.duration() / 3600 }

    var body: some View {
        TGSheet(title: "День закончился",
                subtitle: .готовая(Fmt.duration(day.duration())),
                hasUnsavedChanges: !note.isEmpty) {
            TGCard {
                // Два числа, не три — см. оговорку у `SkillAttemptSheet`:
                // двойные ряды из правила исключены и не померены.
                HStack(spacing: 0) {
                    TGStat(value: Fmt.gap(day.duration()), caption: "на ногах", size: 20)
                    TGStat(value: String(localized: "\(day.plannedHours) часов"),
                           caption: "рассчитывали", size: 20)
                }
            }

            if let advice = DayOutPlan.restAdvice(hours: hours) {
                TGBanner(tone: .waiting, title: "Про завтра", subtitle: .готовая(advice),
                         systemImage: "moon.zzz")
            }

            TGCard {
                TGSectionHeader(title: "как прошло",
                                subtitle: "одной строкой, если есть что запомнить")
                TextEditor(text: $note)
                    .textStyle(AppFont.body)
                    .frame(minHeight: 70)
                    .scrollContentBackground(.hidden)
            }

            TGExplainer(text: "Приложение запомнит этот день и посмотрит на следующий. Если после таких дней у неё регулярно жиже стул или пропадает аппетит — скажет в истории.")

            // Удалить день было нельзя ничем: единственный
            // `context.delete(day)` в дереве — откат при несохранении.
            // А день с собакой заводят одним тапом с главного экрана,
            // то есть заводят и по ошибке, и тогда он навсегда остаётся
            // в выборке «после долгих дней» и тянет туда чужие выводы.
            TGButton(title: "Удалить этот день", variant: .destructive, size: .medium,
                     systemImage: "trash") {
                удаляем = true
            }
            TGExplainer(text: "Записи дня — еда, выходы, дозы — останутся: удаляется только сам «день с собакой» и его след в наблюдениях истории.")
        } footer: {
            TGButton(title: "Готово", variant: .finish) { save() }
        }
        .confirmationDialog("Удалить этот день?", isPresented: $удаляем,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { удалить() }
            Button("Оставить", role: .cancel) {}
        } message: {
            Text("Сами записи останутся. Пропадёт только пометка, что собака была с тобой весь день, — и наблюдения «после долгих дней» перестанут считать его.")
        }
    }

    /// Убрать день целиком.
    ///
    /// Записи не трогаем: `DayOut` — это пометка «собака была со мной»,
    /// а не контейнер для еды и выходов. Удалив их вместе с ним,
    /// приложение стёрло бы дневник за целый день.
    /// **Откат здесь невозможен, и это названо, а не замаскировано.**
    /// После `context.delete` объект уже вынут из контекста; вернуть его
    /// нечем — `rollback()` на iOS 26 снимает признак изменений и
    /// не возвращает ни значений, ни вставок. Поэтому при неудаче
    /// человеку говорится правда: «не удалилось, посмотри после
    /// перезапуска», а не «удалено».
    private func удалить() {
        context.delete(day)
        guard context.persistNothingToUndo() else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не удалилось · проверь после перезапуска"))
            return
        }
        Haptics.success()
        dismiss()
    }

    private func save() {
        let былаЗаметка = day.note
        day.note = note.isEmpty ? nil : note
        guard context.persist(otherwise: { day.note = былаЗаметка }) else {
            // Была только вибрация.
            Haptics.warning()
            appState.showFailure(
                String(localized: "Заметка не сохранилась · нажми ещё раз"))
            return
        }
        Haptics.success()
        dismiss()
    }
}

/// Правка прошедшего дня с собакой: когда начался, когда кончился,
/// на сколько рассчитывали и как прошло.
///
/// **До 29.10.2026 прошедший день был неисправим.** Итог
/// (`DayOutSummarySheet`) показывается один раз — когда день
/// заканчивают, — и после него день уходил в выборку «после долгих
/// дней» без дороги обратно. А длина дня здесь не украшение: от неё
/// `DayOut.wasLong` решает, попадёт ли день в наблюдения истории.
/// Забыли нажать «Закончить» до утра — и в истории навсегда стоял
/// «долгий день» в двадцать часов, тянущий за собой чужие выводы.
struct DayOutEditSheet: View {
    let day: DayOut

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var начало = Date()
    @State private var конец = Date()
    @State private var рассчитывали = 4
    @State private var заметка = ""
    @State private var загружено = false
    @State private var удаляем = false

    var body: some View {
        TGSheet(title: "День с собакой", subtitle: .готовая(Fmt.shortDay(day.startedAt)),
                closeTitle: "Закрыть") {
            TGCard(spacing: 0) {
                DatePicker("Началась", selection: $начало, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .frame(minHeight: Token.Size.tapTarget)
                    // Тот же класс, что у поездки (`TripSetupScreen`):
                    // `in:` у конца не двигает уже выбранное значение.
                    .onChange(of: начало) { _, новое in
                        if конец < новое { конец = новое }
                    }
                TGDivider()
                DatePicker("Закончилась", selection: $конец, in: начало...,
                           displayedComponents: [.date, .hourAndMinute])
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Stepper(value: $рассчитывали, in: 1...16) {
                    HStack {
                        Text("Примерно на").textStyle(AppFont.body)
                        Spacer()
                        Text(String(localized: "\(рассчитывали) часов"))
                            .textStyle(AppFont.numeric(Token.FontSize.body))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
            }

            TGCard {
                TGSectionHeader(title: "как прошло",
                                subtitle: "одной строкой, если есть что запомнить")
                TextEditor(text: $заметка)
                    .textStyle(AppFont.body)
                    // Высота от цели касания, а не числом: литерал размера —
                    // долг `DesignLiteralTests`, и копия соседнего «70»
                    // его бы вырастила.
                    .frame(minHeight: Token.Size.tapTarget * 1.5)
                    .scrollContentBackground(.hidden)
            }

            TGButton(title: "Удалить этот день", variant: .destructive, size: .medium,
                     systemImage: "trash") {
                удаляем = true
            }
            TGExplainer(text: "Записи дня — еда, выходы, дозы — останутся: удаляется только сам «день с собакой» и его след в наблюдениях истории.")
        } footer: {
            TGButton(title: "Сохранить") { сохранить() }
        }
        .presentationDetents([.large])
        .task { загрузить() }
        .confirmationDialog("Удалить этот день?", isPresented: $удаляем,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { удалить() }
            Button("Оставить", role: .cancel) {}
        } message: {
            Text("Сами записи останутся. Пропадёт только пометка, что собака была с тобой весь день, — и наблюдения «после долгих дней» перестанут считать его.")
        }
    }

    private func загрузить() {
        guard !загружено else { return }
        загружено = true
        начало = day.startedAt
        конец = day.endedAt ?? max(day.startedAt, Date())
        рассчитывали = day.plannedHours
        заметка = day.note ?? ""
    }

    private func сохранить() {
        let былоНачало = day.startedAt
        let былКонец = day.endedAt
        let былиЧасы = day.plannedHours
        let былаЗаметка = day.note

        day.startedAt = начало
        day.endedAt = max(конец, начало)
        day.plannedHours = рассчитывали
        day.note = Fmt.notBlank(заметка)

        guard context.persist(otherwise: {
            day.startedAt = былоНачало
            day.endedAt = былКонец
            day.plannedHours = былиЧасы
            day.note = былаЗаметка
        }) else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не сохранилось · нажми «Сохранить» ещё раз"))
            return
        }
        Haptics.success()
        dismiss()
    }

    /// Та же форма удаления, что у итога дня (`DayOutSummarySheet
    /// .удалить`), и та же оговорка: откатить `context.delete` нечем,
    /// поэтому при отказе говорится правда, а не «удалено».
    private func удалить() {
        context.delete(day)
        guard context.persistNothingToUndo() else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не удалилось · проверь после перезапуска"))
            return
        }
        Haptics.success()
        dismiss()
    }
}

/// Идущий день на главном экране.
struct DayOutCard: View {
    let day: DayOut
    let now: Date
    /// Когда в последний раз предлагали воду — по записям `.water`
    /// в ленте, а не по памяти экрана (29.10.2026).
    let lastWater: Date?
    var onWater: () -> Void
    var onFinish: () -> Void

    private var waterDue: Bool {
        now >= DayOutPlan.nextWater(after: lastWater, start: day.startedAt, now: now)
    }

    var body: some View {
        TGCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("собака с тобой")
                        .textStyle(AppFont.micro.color(Token.Status.doneText))
                    Text(Fmt.duration(day.duration(at: now)))
                        .textStyle(AppFont.display)
                    Text("рассчитывали на \(String(localized: "\(day.plannedHours) часов"))")
                        .textStyle(AppFont.micro)
                }
                Spacer(minLength: 0)
                TGButton(title: "Закончить", variant: .finish, size: .medium,
                         fullWidth: false, action: onFinish)
            }

            if waterDue {
                TGDivider()
                // Единственное, о чём этот режим напоминает сам.
                // Всё остальное он, наоборот, приглушает.
                HStack(spacing: Token.Space.s8) {
                    Image(systemName: "drop")
                        .foregroundStyle(Token.Status.waitingText)
                        .accessibilityHidden(true)
                    Text("Пора предложить воду")
                        .textStyle(AppFont.body)
                    Spacer(minLength: 0)
                    // «Предложено», а не «Предложила»: пол человека
                    // приложение не знает (29.10.2026). Кнопка пишет
                    // настоящую запись `.water` — см. `TodayScreen.предложитьВоду`.
                    Button("Предложено", action: onWater)
                        .textStyle(AppFont.captionEmphasis)
                        .buttonStyle(.plain)
                        .foregroundStyle(Token.Status.doneText)
                        .frame(minHeight: Token.Size.tapTarget)
                }
            }
        }
    }
}
