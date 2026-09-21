import SwiftUI
import SwiftData

/// Шаги и занятия: посмотреть, что накопилось, и убрать лишнее.
///
/// До этого экрана шаги и занятия нельзя было удалить поштучно — только
/// вместе со всеми данными приложения. Шаг заводится сам при первом
/// занятии и сам плодит следующие, так что «Ко мне · Коридор · 2 м»,
/// заведённое на пробу, оставалось в матрице переноса навсегда.
struct TrainingLibraryScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \TrainingStep.order) private var allSteps: [TrainingStep]
    @Query(sort: \TrainingSession.startedAt, order: .reverse) private var allSessions: [TrainingSession]

    @State private var removingStep: TrainingStep?
    @State private var removingSession: TrainingSession?

    private var steps: [TrainingStep] {
        allSteps.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
    }

    private var sessions: [TrainingSession] {
        allSessions.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
    }

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            if steps.isEmpty && sessions.isEmpty {
                EmptyStateCard(
                    systemImage: "target",
                    title: "Занятий пока не было",
                    message: "Первый шаг заведётся сам, как только начнёшь занятие. Здесь потом будет видно, что накопилось, и лишнее можно будет убрать.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                stepsCard
                sessionsCard
            }
        }
        .navigationTitle("Занятия и шаги")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Удалить шаг?",
                            isPresented: Binding(get: { removingStep != nil },
                                                 set: { if !$0 { removingStep = nil } }),
                            titleVisibility: .visible,
                            presenting: removingStep) { step in
            Button("Удалить", role: .destructive) { delete(step) }
            Button("Отмена", role: .cancel) { removingStep = nil }
        } message: { step in
            Text("\(step.fullSummary). Из матрицы переноса он тоже уйдёт. Занятия, которые уже прошли, останутся.")
        }
        .confirmationDialog("Удалить занятие?",
                            isPresented: Binding(get: { removingSession != nil },
                                                 set: { if !$0 { removingSession = nil } }),
                            titleVisibility: .visible,
                            presenting: removingSession) { session in
            Button("Удалить", role: .destructive) { delete(session) }
            Button("Отмена", role: .cancel) { removingSession = nil }
        } message: { session in
            Text("\(Fmt.shortDay(session.startedAt)) · \(session.cue). Запись в ленте останется — её убирают там же, где и любую другую.")
        }
    }

    // MARK: Шаги

    @ViewBuilder
    private var stepsCard: some View {
        if !steps.isEmpty {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "шаги",
                                subtitle: "из них складывается матрица переноса")
                ForEach(steps) { step in
                    row(title: step.cue, detail: step.fullSummary,
                        badge: step.status.title, tone: step.status.color) {
                        if canEdit { removingStep = step }
                    }
                    if step.id != steps.last?.id { TGDivider() }
                }
                if canEdit { TGExplainer(text: "Лишнее — тапни и удали.") }
            }
        }
    }

    // MARK: Занятия

    @ViewBuilder
    private var sessionsCard: some View {
        if !sessions.isEmpty {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "занятия",
                                subtitle: "последние сверху")
                ForEach(sessions.prefix(20)) { session in
                    row(title: "\(session.cue) · \(Fmt.shortDay(session.startedAt))",
                        detail: detail(of: session),
                        badge: session.countsTowardProgress ? nil : "не в счёт",
                        tone: Token.Ink.secondary) {
                        if canEdit { removingSession = session }
                    }
                    if session.id != sessions.prefix(20).last?.id { TGDivider() }
                }
                if sessions.count > 20 {
                    TGExplainer(text: "Показаны последние двадцать из \(sessions.count).")
                }
            }
        }
    }

    private func detail(of session: TrainingSession) -> String {
        var parts = ["\(session.place) · \(session.distanceMeters) м"]
        if session.attempts > 0 { parts.append("\(session.successes) из \(session.attempts)") }
        if session.durationSeconds > 0 {
            parts.append(Fmt.duration(Double(session.durationSeconds)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Общая строка

    private func row(title: String, detail: String, badge: String?,
                     tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Token.Space.s8) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(title).textStyle(AppFont.body)
                    Text(detail).textStyle(AppFont.caption).wraps()
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge).textStyle(AppFont.micro.color(tone))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
    }

    // MARK: Удаление

    private func delete(_ step: TrainingStep) {
        context.delete(step)
        try? context.save()
        Haptics.warning()
        removingStep = nil
    }

    private func delete(_ session: TrainingSession) {
        context.delete(session)
        try? context.save()
        Haptics.warning()
        removingSession = nil
    }
}
