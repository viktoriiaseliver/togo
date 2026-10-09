import SwiftUI
import SwiftData

/// Закрыть выход.
///
/// Вынесено из шторки, потому что закрывается выход двумя путями:
/// человек ответил «как сходил» — и тихие часы, когда его об этом
/// не спрашивают вовсе. Логика одна, и жить в двух местах она не должна.
@MainActor
enum OutingFinisher {
    /// **Здесь не было сохранения вовсе** — ни `save()`, ни даже `try?`.
    /// Результат прогулки и её длительность ставились в память и держались
    /// на автосохранении контекста, то есть на удаче: человек отвечал «как
    /// сходил», шторка закрывалась, а в дневнике оставался выход без
    /// результата. Разбор «просится» строится на этих самых полях, и тихая
    /// потеря одного ответа так же тихо портила всю статистику.
    ///
    /// Отсюда и параметр `context`: раньше сохранять было нечем — его
    /// просто не существовало, и отсутствие сохранения нельзя было заметить,
    /// глядя на эту функцию.
    static func finish(outcome: OutingOutcome?, dog: Dog?,
                       appState: AppState, context: ModelContext) {
        let duration = appState.stopWalk()
        Task { await LiveActivityController.finishWalk(outcome: outcome?.shortTitle) }
        guard let dog, let last = Diary.last(dog.events, kind: .outing) else { return }

        let былРезультат = last.outcome
        let былаДлительность = last.durationSeconds
        last.outcome = outcome
        last.durationSeconds = Int(duration)

        guard context.persist(otherwise: {
            last.outcome = былРезультат
            last.durationSeconds = былаДлительность
        }) else {
            Haptics.warning()
            appState.showFailure("Ответ не записался · отметь ещё раз")
            return
        }
    }
}

/// Результат спрашивается один раз. Не ответили — запись остаётся без результата,
/// повторно не спрашиваем. В тихие часы не спрашиваем вообще — выход
/// закрывается молча, а день соберёт утреннюю сводку.
struct WalkResultSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

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
        OutingFinisher.finish(outcome: outcome, dog: dog, appState: appState, context: context)
        dismiss()
    }
}
