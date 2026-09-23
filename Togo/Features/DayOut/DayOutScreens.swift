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
                        Text(Fmt.plural(hours, "час", "часа", "часов"))
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
            row("Корм", packing.meals == 0
                ? "не понадобится — кормления в это окно не попадают"
                : "\(packing.totalGrams) г · \(Fmt.plural(packing.meals, "кормление", "кормления", "кормлений")) и запас")
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
        try? context.save()
        Haptics.success()
        appState.showUndo("Режим включён · собака с тобой")
        dismiss()
    }
}

/// Итог дня: сколько вышло и что это значит для завтра.
struct DayOutSummarySheet: View {
    let day: DayOut

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private var hours: Double { day.duration() / 3600 }

    var body: some View {
        TGSheet(title: "День закончился",
                subtitle: .готовая(Fmt.duration(day.duration())),
                hasUnsavedChanges: !note.isEmpty) {
            TGCard {
                HStack(spacing: 0) {
                    TGStat(value: Fmt.gap(day.duration()), caption: "на ногах", size: 20)
                    TGStat(value: Fmt.plural(day.plannedHours, "час", "часа", "часов"),
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
        } footer: {
            TGButton(title: "Готово", variant: .finish) { save() }
        }
    }

    private func save() {
        day.note = note.isEmpty ? nil : note
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

/// Идущий день на главном экране.
struct DayOutCard: View {
    let day: DayOut
    let now: Date
    /// Когда в последний раз предлагали воду.
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
                    Text("рассчитывали на \(Fmt.plural(day.plannedHours, "час", "часа", "часов"))")
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
                    Button("Предложила", action: onWater)
                        .textStyle(AppFont.captionEmphasis)
                        .buttonStyle(.plain)
                        .foregroundStyle(Token.Status.doneText)
                        .frame(minHeight: Token.Size.tapTarget)
                }
            }
        }
    }
}
