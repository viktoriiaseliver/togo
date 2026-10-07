import SwiftUI
import SwiftData

/// «Просится» — главная кнопка приложения и единственное место, где приложение
/// может незаметно испортить поведение. **Пять случаев вердикта и шесть
/// разных объяснений** (у `.unknown` три причины), и «Вывожу» первой
/// кнопкой во всех: вердикт не блокирует выход.
///
/// **Здесь было написано «четыре исхода» — 07.10.2026 это посчитано
/// и оказалось неверно**, ровно как и та же фраза в `NeedVerdict.swift:3`.
/// Числа в документации стареют молча: `.episode` и `.silence`
/// приехали позже, а строка осталась и читается ВМЕСТО кода —
/// тем же способом, каким у Gamut имя теста пять дней рассказывало
/// отменённое поведение.
struct NeedsSheet: View {
    let dog: Dog?

    /// Готовый срез фактов вместо чтения из базы — вход для галереи.
    ///
    /// Без него шесть состояний вердикта требуют шести собак с нужной
    /// историей событий в SwiftData, то есть поверхность остаётся
    /// **проверяемой только живой собакой**. Тот же ход, что
    /// у `WalkActivityView`: не новый вид рядом с настоящим,
    /// а второй вход в настоящий — иначе кадр доказывал бы, что верна
    /// копия.
    var демоСигналы: NeedSignals?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var askSignal = false

    /// Считаем один раз при открытии: тело шторки обращается к вердикту
    /// и к фактам по три раза, а каждый расчёт проходит всю историю.
    @State private var signals = NeedSignals()
    @State private var verdict: NeedVerdict = .unknown(reason: .ambiguous)

    private func evaluate() {
        // Галерея подставляет срез фактов; вердикт всё равно считает
        // НАСТОЯЩИЙ движок. Подставь сюда готовый вердикт — и кадр
        // доказывал бы, что верна подпись под картинкой, а не что
        // правило считает то, что написано.
        signals = демоСигналы
            ?? Diary.signals(dog?.events ?? [], episodeActive: appState.isEpisodeActive)
        verdict = VerdictEngine.evaluate(signals)
    }

    var body: some View {
        TGSheet(title: .готовая(verdict.title), subtitle: .готовая(verdict.badge)) {
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
            TGButton(title: .готовая(verdict.alternativeAction), variant: .secondary, size: .medium) { dismiss() }
        }
        .presentationDetents([.medium, .large])
        // Демо-показ в журнал не пишем: шесть состояний галереи дали бы
        // шесть посещений «Просится», которых человек не делал.
        .usageScreen(демоСигналы == nil ? .needs : nil)
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
        LiveActivityController.startWalk(dogName: dog.name, by: appState.currentUserName, at: event.date)  // кличка-в-слот: вход живой активности кормит и именительный ярлык, и винительные подписи — падеж знает слот

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
