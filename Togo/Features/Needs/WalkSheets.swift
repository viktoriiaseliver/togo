import SwiftUI
import SwiftData

/// Закрыть выход.
///
/// Вынесено из шторки, потому что закрывается выход двумя путями:
/// человек ответил «как сходил» — и тихие часы, когда его об этом
/// не спрашивают вовсе. Логика одна, и жить в двух местах она не должна.
@MainActor
enum OutingFinisher {
    static func finish(outcome: OutingOutcome?, dog: Dog?, appState: AppState) {
        let duration = appState.stopWalk()
        Task { await LiveActivityController.finishWalk(outcome: outcome?.shortTitle) }
        guard let dog, let last = Diary.last(dog.events, kind: .outing) else { return }
        last.outcome = outcome
        last.durationSeconds = Int(duration)
    }
}

/// Результат спрашивается один раз. Не ответили — запись остаётся без результата,
/// повторно не спрашиваем. В тихие часы не спрашиваем вообще — выход
/// закрывается молча, а день соберёт утреннюю сводку.
struct WalkResultSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

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
        // Отмечаем не «закончил» — это сделает сам выход, — а судьбу
        // вопроса о результате: пропустили его или ответили.
        if outcome == nil { UsageLog.note(.record, "outcome", outcome: .cancelled) }
        OutingFinisher.finish(outcome: outcome, dog: dog, appState: appState)
        dismiss()
    }
}
