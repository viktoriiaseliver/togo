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
        // Кобель без ответа НЕ пишется мочой, хотя мочой читается
        // (`ToiletClock`): пропуск вопроса «Покакал?» — не ответ «нет».
        // Запиши его «пописал», и `StoolSilence` принял бы каждый
        // пропуск за доказательство, что стула не было.
        let итог = outcome
        let duration = appState.stopWalk()
        Task { await LiveActivityController.finishWalk(outcome: итог?.shortTitle) }
        guard let dog, let last = Diary.last(dog.events, kind: .outing) else { return }

        let былРезультат = last.outcome
        let былаДлительность = last.durationSeconds
        last.outcome = итог
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

    /// У кобеля спрашиваем только про стул: моча у него — сам выход.
    private var кобель: Bool { dog?.sex == .male }

    /// Что предлагаем. У кобеля «Пописал» и «И то и другое» сводятся
    /// к одному вопросу «покакал ли», а «Не сходил» остаётся: выход
    /// без результата — настоящий сигнал и у кобеля.
    private var варианты: [(OutingOutcome, String)] {
        кобель
            ? [(.both, String(localized: "Покакал")),
               (.urine, String(localized: "Только пописал")),
               (.none, OutingOutcome.none.title)]
            : OutingOutcome.allCases.map { ($0, $0.title) }
    }

    var body: some View {
        TGSheet(title: кобель ? "Покакал?" : "Как сходил?", subtitle: "спросим только сейчас") {
            VStack(spacing: Token.Space.s8) {
                ForEach(варианты, id: \.0) { вариант in
                    Button { record(вариант.0) } label: {
                        Text(вариант.1)
                            .textStyle(AppFont.body)
                            .foregroundStyle(Token.Ink.primary)
                            .frame(maxWidth: .infinity, minHeight: Token.Size.controlL)
                            .background(Token.Surface.card, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TGExplainer(text: "Не ответишь — запись всё равно останется, просто без результата. Спрашивать второй раз не будем.", памятка: "выход.неОтветишь")
            TGButton(title: "Пропустить", variant: .secondary, size: .medium) { finish(nil) }
        }
        .presentationDetents([.medium, .large])
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
