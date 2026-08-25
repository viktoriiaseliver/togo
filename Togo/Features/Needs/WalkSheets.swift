import SwiftUI
import SwiftData



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
