import Foundation

/// Собрать итог смены из того, что уже записано.
///
/// План дня и лента — один и тот же материал, просто нарезанный по часам
/// дежурства. Своего учёта смена не ведёт: он бы разошёлся с дневником
/// на второй же день.
nonisolated enum ShiftReport {

    /// - Parameters:
    ///   - plan: пункты режима дня со временем и признаком выполнения.
    ///   - events: записи дневника — из них берётся, кто закрыл пункт.
    @MainActor
    static func build(
        shift: Shift,
        plan: [(id: String, title: String, due: Date, isDone: Bool)],
        events: [LogEvent],
        tolerance: TimeInterval = MealSchedule.doneTolerance
    ) -> ShiftSummary {
        let active = Diary.active(events)

        let items = plan
            .filter { shift.covers($0.due) }
            .map { entry in
                // Кто закрыл — ищем ближайшую по времени запись смены.
                let author = active
                    .filter { shift.covers($0.date) }
                    .filter { abs($0.date.timeIntervalSince(entry.due)) <= tolerance }
                    .min { abs($0.date.timeIntervalSince(entry.due))
                         < abs($1.date.timeIntervalSince(entry.due)) }?
                    .authorName

                return ShiftItem(id: entry.id, title: entry.title, due: entry.due,
                                 isDone: entry.isDone, by: entry.isDone ? author : nil)
            }
            .sorted { $0.due < $1.due }

        return ShiftSummary(shift: shift, items: items)
    }
}
