import SwiftUI
import SwiftData

/// Идущий выход — карточка с секундами. Live Activity показывает то же самое
/// на локскрине всей семье.
struct WalkInProgressCard: View {
    let startedAt: Date
    let by: String
    let now: Date
    var onFinish: () -> Void

    var body: some View {
        TGCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("выход идёт").textStyle(AppFont.micro).foregroundStyle(Token.Action.primary)
                    Text(Fmt.stopwatch(now.timeIntervalSince(startedAt)))
                        .textStyle(AppFont.numeric(34, weight: .bold))
                        .foregroundStyle(Token.Ink.primary)
                }
                Spacer()
                Button("Стоп") { onFinish() }
                    .textStyle(AppFont.cardTitle)
                    .foregroundStyle(Token.Ink.primary)
                    .padding(.horizontal, 22)
                    .frame(minHeight: Token.Size.tapTarget)
                    .background(Token.Action.primary, in: RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
            }
            Text("\(by) вывела в \(Fmt.clock(startedAt)) · остальные видят это на локскрине")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }
}

struct WalkStartSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var minutes = 30

    var body: some View {
        TGSheet(title: "Прогулка", subtitle: "не занятие — просто прогулка") {
            TGCard {
                Stepper(value: $minutes, in: 5...180, step: 5) {
                    HStack {
                        Text("Сколько гуляли").textStyle(AppFont.body)
                        Spacer()
                        Text("\(minutes) мин").textStyle(AppFont.numeric(17)).foregroundStyle(Token.Ink.primary)
                    }
                }
            }
            TGExplainer(text: "Занятие живёт отдельно и длится две-три минуты. Отмечать команду в конце получасовой прогулки бесполезно: собака учится в первые минуты, дальше устаёт и начинает угадывать.")
            TGButton(title: "Записать прогулку") { save() }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let dog else { return }
        let event = LogEvent(kind: .walk, authorName: appState.currentUserName)
        event.durationSeconds = minutes * 60
        event.dog = dog
        context.insert(event)
        Haptics.success()
        appState.showUndo("Записано · Прогулка \(minutes) мин", eventID: event.id)
        dismiss()
    }
}

/// Результат спрашивается один раз. Не ответили — запись остаётся без результата,
/// повторно не спрашиваем. В тихие часы не спрашиваем вообще.
struct WalkResultSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(Settings.self) private var settings

    var body: some View {
        TGSheet(title: "Как сходил?", subtitle: "спросим только сейчас") {
            VStack(spacing: 8) {
                ForEach(OutingOutcome.allCases, id: \.self) { outcome in
                    Button { record(outcome) } label: {
                        Text(outcome.title)
                            .textStyle(AppFont.body)
                            .foregroundStyle(Token.Ink.primary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Token.Surface.card, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TGExplainer(text: "Не ответишь — запись всё равно останется, просто без результата. Спрашивать второй раз не будем.")
            TGButton(title: "Пропустить", variant: .secondary, size: .medium) { finish(nil) }
        }
        .presentationDetents([.medium])
    }

    private func record(_ outcome: OutingOutcome) {
        Haptics.tap()
        finish(outcome)
    }

    private func finish(_ outcome: OutingOutcome?) {
        let duration = appState.stopWalk()
        Task { await LiveActivityController.finishWalk(outcome: outcome?.shortTitle) }
        if let dog, let last = Diary.last(dog.events, kind: .outing) {
            last.outcome = outcome
            last.durationSeconds = Int(duration)
        }
        dismiss()
    }
}
