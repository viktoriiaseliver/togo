import SwiftUI
import SwiftData

/// Занятие. Приложение здесь — секундомер и зеркало, а не счётчик корма.
struct TrainingSessionScreen: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var steps: [TrainingStep]

    @State private var session: MarkerSession
    @State private var now = Date()
    @State private var summary: TrainingSession?
    @State private var isConfirmingExit = false

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(dog: Dog?) {
        self.dog = dog
        _session = State(initialValue: MarkerSession(limitMinutes: dog?.sessionLengthMinutes ?? 3))
    }

    private var mySteps: [TrainingStep] {
        steps.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
            .sorted { $0.order < $1.order }
    }

    private var currentStep: TrainingStep? {
        mySteps.first { !$0.isClosed } ?? mySteps.first
    }

    /// Первый шаг заводится сам при первом занятии.
    ///
    /// Раньше шаги не создавал никто: занятие всегда шло «без шага»,
    /// прогресс не двигался, а матрица переноса оставалась пустой навсегда.
    /// Начинаем с самого лёгкого — дома, два метра: с этого и начинают.
    private func ensureFirstStep() {
        guard let dog, mySteps.isEmpty else { return }
        let step = TrainingStep(cue: "Ко мне", place: "Дома",
                                person: appState.currentUserName,
                                distanceMeters: 2, order: 0)
        step.status = .learning
        step.dog = dog
        context.insert(step)
        try? context.save()
    }

    var body: some View {
        Group {
            if let summary {
                SessionSummarySheet(session: summary, step: currentStep) { dismiss() }
            } else {
                sessionSheet
            }
        }
        .presentationDetents([.large])
        .task { ensureFirstStep() }
        .onReceive(tick) { now = $0 }
        .confirmationDialog("Занятие не сохранится", isPresented: $isConfirmingExit, titleVisibility: .visible) {
            Button("Сохранить и выйти") { finish() }
            Button("Выйти без записи", role: .destructive) { dismiss() }
            Button("Вернуться к занятию", role: .cancel) {}
        } message: {
            Text("Отметок уже \(session.delaysMs.count). Их можно записать — прогресс посчитается, если занятие уложилось в три минуты.")
        }
    }

    private var sessionSheet: some View {
        TGSheet(
            title: session.isRunning ? "Занятие идёт" : "Точность маркера",
            subtitle: currentStep?.fullSummary ?? "поставь руку один раз — потом маркер уйдёт на кнопку громкости",
            closeTitle: session.isRunning ? "Прервать занятие" : "Закрыть",
            // Молча терять отметки нельзя: занятие уже прошло, даже если
            // человек передумал его сохранять.
            onClose: session.isRunning && !session.delaysMs.isEmpty
                ? { isConfirmingExit = true }
                : nil
        ) {
            clock
            markerPad
            recentMarks
            markerKindRow
            observations
        } footer: {
            if session.isRunning {
                TGButton(title: "Закончить на удаче", variant: .finish,
                     systemImage: "checkmark") { finish() }
                TGButton(title: "Сбросить отметки", variant: .quiet, size: .medium) { session.reset() }
            } else {
                TGButton(title: "Начать занятие · \(dog?.sessionLengthMinutes ?? 3) минуты", systemImage: "play.fill") {
                    session.start()
                    Haptics.tap()
                }
            }
        }
    }

    // MARK: Часы

    private var clock: some View {
        TGCard {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.stopwatch(session.elapsed(at: now))).textStyle(AppFont.display)
                Spacer()
                if let accuracy = session.lastAccuracy, let ms = session.lastDelayMs {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(accuracy.title).textStyle(AppFont.cardTitle.color(accuracy.color))
                        Text("\(ms) мс").textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                    }
                }
            }
            ProgressView(value: min(1, session.elapsed(at: now) / Double(session.limitSeconds)))
                .tint(session.isOvertime(at: now) ? Token.Status.overdueText : Token.Action.primary)
            Text(session.hint(at: now)).textStyle(AppFont.caption)

            if session.isOvertime(at: now) {
                TGBanner(tone: .alarm, title: "Три минуты прошли",
                         subtitle: "Дальше прогресс не пишем: после трёх минут собака угадывает, а не учится.",
                         systemImage: "hourglass")
            }
        }
    }

    // MARK: Два тапа — вся точность

    private var markerPad: some View {
        VStack(spacing: Token.Space.s10) {
            Button { session.markAction(); Haptics.tap() } label: {
                VStack(spacing: Token.Space.s2) {
                    Text("Он сделал").textStyle(AppFont.cardTitle)
                    Text("сел, посмотрел, подошёл").textStyle(AppFont.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(Token.Surface.sunken,
                            in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRunning || session.isWaitingForMark)

            Button { mark() } label: {
                VStack(spacing: Token.Space.s2) {
                    Text("Клик").textStyle(AppFont.cardTitle)
                    Text(dog?.markerKind.title ?? "маркер").textStyle(AppFont.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(session.isWaitingForMark ? Token.Action.primary : Token.Action.primaryQuiet,
                            in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!session.isWaitingForMark)

            Button("Не получилось") { session.markMiss() }
                .textStyle(AppFont.caption)
                .disabled(!session.isRunning)
        }
    }

    private func mark() {
        session.markMarker()
        Haptics.marker()
    }

    // MARK: Последние отметки

    private var recentMarks: some View {
        TGCard {
            HStack {
                TGSectionHeader(title: "последние отметки")
                Spacer()
                Text("среднее \(session.averageDelayMs) мс").textStyle(AppFont.micro)
            }
            Text("\(session.onTimeCount) из \(session.delaysMs.count) в момент")
                .textStyle(AppFont.numeric(20))
            HStack(spacing: Token.Space.s4) {
                ForEach(Array(session.delaysMs.suffix(12).enumerated()), id: \.offset) { _, ms in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MarkAccuracy.from(delayMilliseconds: ms).color)
                        .frame(height: CGFloat(min(48, max(6, ms / 25))))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48, alignment: .bottom)
            TGExplainer(text: "Ниже — быстрее. До полусекунды собака связывает маркер со своим действием. После секунды она уже сделала что-то другое, и вы отмечаете именно это.")
        }
    }

    // MARK: Чем маркируешь

    private var markerKindRow: some View {
        TGCard {
            TGSectionHeader(title: "чем маркируешь")
            TGChipGroup(
                items: MarkerKind.allCases,
                title: \.title,
                isSelected: { dog?.markerKind == $0 }
            ) { kind in
                dog?.markerKind = kind
                Haptics.tap()
            }
            TGExplainer(text: "Маркер один и тот же всегда и больше ничего не значит. «Молодец» не годится: его говорят весь день.")
        }
    }

    // MARK: Что заметила

    private var observations: some View {
        TGCard {
            TGSectionHeader(title: "что заметила", subtitle: "это про условия, а не про собаку")
            TGChipGroup(
                items: SessionObservation.allCases,
                title: \.title,
                isSelected: { session.observations.contains($0) },
                tone: { $0.stopsSession ? .alarm : .neutral }
            ) { observation in
                toggle(observation)
            }
            if session.observations.contains(.refusedFood) {
                TGBanner(tone: .alarm, title: "Если не берёт еду — заканчивай",
                         subtitle: "Отказ от корма, за который он обычно работает, значит, что сейчас он учиться не может. Это не упрямство. Вернись к задаче попроще завтра.",
                         systemImage: "hand.raised")
            }
        }
    }

    private func toggle(_ observation: SessionObservation) {
        if session.observations.contains(observation) {
            session.observations.remove(observation)
        } else {
            session.observations.insert(observation)
        }
        Haptics.tap()
    }

    /// Шаг закрыт — открываем следующий, изменив **одно** условие.
    /// Сначала растёт дистанция, и только потом меняется место: менять
    /// два условия разом значит не понять, что именно не сработало.
    private func openNextStep(after step: TrainingStep, for dog: Dog) {
        let дистанции = [2, 5, 10, 20]
        let места = ["Дома", "Коридор", "Двор", "Улица без собак", "Парк, есть собаки"]

        let next: TrainingStep
        if let дальше = дистанции.first(where: { $0 > step.distanceMeters }) {
            next = TrainingStep(cue: step.cue, place: step.place, person: step.person,
                                distanceMeters: дальше, order: step.order + 1)
        } else if let индекс = места.firstIndex(of: step.place), индекс + 1 < места.count {
            // Новое место — возвращаем короткую дистанцию.
            next = TrainingStep(cue: step.cue, place: места[индекс + 1], person: step.person,
                                distanceMeters: дистанции[0], order: step.order + 1)
        } else {
            return
        }

        next.status = .notStarted
        next.dog = dog
        context.insert(next)
        try? context.save()
    }

    // MARK: Итог

    private func finish() {
        guard let dog else { return }
        let record = TrainingSession(
            cue: currentStep?.cue ?? "Занятие",
            place: currentStep?.place ?? "дома",
            person: appState.currentUserName,
            distanceMeters: currentStep?.distanceMeters ?? 2
        )
        record.durationSeconds = Int(session.elapsed(at: now))
        record.markDelaysMs = session.delaysMs
        record.successes = session.successes
        record.attempts = max(session.attempts, session.delaysMs.count)
        record.gramsUsed = session.gramsUsed()
        record.observations = session.observations
        record.countsTowardProgress = session.countsTowardProgress(at: now)
        record.dog = dog
        context.insert(record)

        // Шаг закрыт при 4 из 5 в двух занятиях подряд; два плохих подряд —
        // предложение вернуться на шаг назад.
        if let step = currentStep, record.countsTowardProgress {
            if record.isGoodSession {
                step.consecutiveGoodSessions += 1
                step.status = step.isClosed ? .works : .learning
                if step.isClosed { openNextStep(after: step, for: dog) }
            } else if record.isPoorSession {
                step.consecutiveGoodSessions = 0
            }
        }

        let event = LogEvent(kind: .training, authorName: appState.currentUserName)
        event.grams = record.gramsUsed
        event.note = record.cue
        event.trainingSessionID = record.id
        event.dog = dog
        context.insert(event)

        Haptics.success()
        summary = record
    }
}
