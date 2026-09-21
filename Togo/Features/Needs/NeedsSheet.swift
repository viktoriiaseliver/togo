import SwiftUI
import SwiftData

/// «Просится» — главная кнопка приложения и единственное место, где приложение
/// может незаметно испортить поведение. Четыре исхода вердикта, и «Вывожу»
/// первой кнопкой во всех: вердикт не блокирует выход.
struct NeedsSheet: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var askSignal = false

    /// Считаем один раз при открытии: тело шторки обращается к вердикту
    /// и к фактам по три раза, а каждый расчёт проходит всю историю.
    @State private var signals = NeedSignals()
    @State private var verdict: NeedVerdict = .unknown(reason: .ambiguous)

    private func evaluate() {
        signals = Diary.signals(dog?.events ?? [], episodeActive: appState.isEpisodeActive)
        verdict = VerdictEngine.evaluate(signals)
    }

    var body: some View {
        TGSheet(title: verdict.title, subtitle: verdict.badge) {
            TGCard {
                Text(VerdictEngine.explanation(verdict, signals))
                    .textStyle(AppFont.body)
                    .foregroundStyle(Token.Ink.primary)
                TGDivider()
                Text(VerdictEngine.factLine(signals))
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                // Одной строкой: сколько раз в день выходите обычно.
                // Вердикт отвечает «сейчас или нет», а это — «а вообще как».
                WalkRhythmCard(rhythm: WalkRhythmAnalyzer.rhythm(events: dog?.events ?? []),
                               compact: true)
            }

            if case .unknown(.notEnoughData) = verdict {
                TGExplainer(text: "Через три-четыре дня приложение выучит его интервалы и начнёт подсказывать, настоящая ли нужда. Пока — выводи, как обычно.")
            }
        } footer: {
            // Главное действие закреплено внизу: до него дотягивается большой
            // палец, и оно не уезжает вместе с текстом вердикта.
            TGButton(title: "Вывожу", systemImage: "figure.walk.departure") { startOuting() }
            TGButton(title: verdict.alternativeAction, variant: .secondary, size: .medium) { dismiss() }
        }
        .presentationDetents([.medium, .large])
        .usageScreen(.needs)
        .task { evaluate() }
        .sheet(isPresented: $askSignal) {
            HowAskedSheet(dog: dog) { dismiss() }
        }
    }

    private func startOuting() {
        guard let dog,
              let event = EventLog(context: context, appState: appState)
                  .record(.outing, dog: dog, confirmation: nil)
        else { return }
        appState.startOuting(by: appState.currentUserName)
        LiveActivityController.startWalk(dogName: dog.name, by: appState.currentUserName, at: event.date)

        // Спрашиваем не каждый раз: только при смене сигнала или раз в пять выходов.
        if Diary.shouldAskHowAsked(dog.events) {
            askSignal = true
        } else {
            appState.showUndo("Записано · Выход", eventID: event.id)
            dismiss()
        }
    }
}

/// Один тап, который меняет поведение. Дверь откроется — то, что он сделал,
/// закрепится; приложение обязано спросить, что именно это было.
struct HowAskedSheet: View {
    let dog: Dog?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        TGSheet(
            title: "Как попросил?",
            subtitle: "Дверь откроется — то, что он сделал, закрепится. Отметь, и приложение покажет, если что-то идёт не туда."
        ) {
            VStack(spacing: 8) {
                ForEach(AskSignal.allCases, id: \.self) { signal in
                    Button { record(signal) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: signal.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(signal.isCalm ? Token.Action.doneText : Token.Ink.silhouette)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.title).textStyle(AppFont.body).foregroundStyle(Token.Ink.primary)
                                if signal == .satAtDoor {
                                    Text("то, что учим").textStyle(AppFont.micro).foregroundStyle(Token.Action.doneText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                        .padding(.horizontal, 14)
                        .background(Token.Surface.card, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TGExplainer(text: "Спрашиваем не каждый раз: только когда сигнал меняется или раз в несколько выходов.")
        }
        .presentationDetents([.medium])
    }

    private func record(_ signal: AskSignal) {
        if let dog, let last = Diary.last(dog.events, kind: .outing) {
            last.askSignal = signal
        }
        Haptics.tap()
        dismiss()
        onDone()
    }
}
