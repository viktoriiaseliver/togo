import Foundation
import ActivityKit
import WidgetKit

/// Управление Live Activity идущего выхода и снимком для виджетов.
///
/// Приложение — единственный, кто пишет: виджет только читает.
enum LiveActivityController {

    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func startWalk(dogName: String, by person: String, at date: Date) {
        // Список живых активностей — единственный источник правды.
        // Своей копии не держим: она разъедется после перезапуска приложения.
        guard isAvailable, Activity<WalkActivityAttributes>.activities.isEmpty else { return }
        do {
            _ = try Activity.request(
                attributes: WalkActivityAttributes(dogName: dogName, startedBy: person),
                content: .init(state: .init(startedAt: date), staleDate: date.addingTimeInterval(4 * 3600)),
                pushType: nil
            )
        } catch {
            log.notice("Live Activity не запустилась: \(error.localizedDescription)")
        }
    }

    /// Гасим всё, что осталось живого: активность могла пережить перезапуск.
    nonisolated static func finishWalk(outcome: String?) async {
        let state = WalkActivityAttributes.ContentState(startedAt: .now, outcome: outcome)
        for activity in Activity<WalkActivityAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    /// Снимок для виджетов пересобирается из тех же данных, что и главный экран,
    /// чтобы виджет и приложение никогда не расходились.
    static func publishSnapshot(dog: Dog?, appState: AppState, now: Date = Date()) {
        guard let dog else { return }
        let events = dog.events
        let signals = Diary.signals(events, now: now, episodeActive: appState.isEpisodeActive)
        let verdict = VerdictEngine.evaluate(signals)

        let snapshot = WidgetSnapshot(
            dogName: dog.name,
            dogInitial: dog.initial,
            verdictTitle: verdict.title,
            verdictBadge: verdict.badge,
            sinceUrineSeconds: signals.sinceUrine,
            lastStoolSummary: signals.lastStool.map { "стул \(Fmt.clock($0))" },
            lastWalkSummary: signals.lastWalk.map { "гулял \(Fmt.duration(now.timeIntervalSince($0))) назад" },
            walkStartedAt: appState.walkStartedAt,
            walkStartedBy: appState.walkStartedBy,
            fastingEndsAt: fastingEnd(for: dog, now: now),
            updatedAt: now
        )
        WidgetBridge.publish(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func fastingEnd(for dog: Dog, now: Date) -> Date? {
        guard dog.isOnTreatment else { return nil }
        for medication in dog.medications where medication.fastingMinutes > 0 && !medication.isPaused {
            guard let dose = medication.doses.filter({ $0.isGiven })
                .max(by: { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }),
                  let givenAt = dose.givenAt else { continue }
            let ends = givenAt.addingTimeInterval(Double(medication.fastingMinutes) * 60)
            if now < ends { return ends }
        }
        return nil
    }
}
