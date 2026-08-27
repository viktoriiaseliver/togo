import Foundation
import SwiftData

/// Строитель режима дня.
nonisolated enum DayPlanBuilder {
    /// Режим дня одним списком.
    ///
    /// Жил внутри экрана «Сегодня» и понадобился второму месту — итогу
    /// смены. Копия разошлась бы с оригиналом на первом же изменении:
    /// правил здесь много, и все они про то, что человек считает
    /// сделанным.
    @MainActor
    static func items(dog: Dog?, events: [LogEvent], now: Date = Date(),
                      seesMedical: Bool = true) -> [DayPlanItem] {
        guard let dog else { return [] }
        var items: [DayPlanItem] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let doneMealTimes = Diary.onDay(events, now).filter { $0.kind == .meal }.map(\.date)

        // Каждая запись закрывает ровно один пункт — ближайший к себе.
        let mealMinutes = dog.mealTimes.sorted()
        let mealDone = MealSchedule.matchDone(planned: mealMinutes, logged: doneMealTimes,
                                              startOfDay: startOfDay)
        for (index, minute) in mealMinutes.enumerated() {
            let at = startOfDay.addingTimeInterval(Double(minute) * 60)
            items.append(DayPlanItem(id: "meal-\(minute)", time: at,
                                     title: "Еда · \(dog.servingGrams) г",
                                     hint: dog.foodBrand, kind: .meal, isDone: mealDone[index]))
        }
        // Уход — такой же пункт дня, как еда и доза. Отдельной карточкой
        // он говорил, что надо сделать, но сделать оттуда было нельзя:
        // тап уводил на вкладку собаки, где дело приходилось искать
        // руками. Пять шагов на действие в одну секунду.
        for task in dog.careTasks where task.isDue(on: now) {
            items.append(DayPlanItem(
                id: "care-\(task.id)",
                // Уход ставим в конец дня: у него нет часа, и он не должен
                // мешаться между кормлениями.
                time: startOfDay.addingTimeInterval(Double(dog.sleepMinuteOfDay) * 60),
                title: task.title,
                hint: task.detail.isEmpty ? nil : task.detail,
                kind: .care,
                isDone: task.isDoneToday(on: now),
                careTask: task,
                showsTime: false
            ))
        }

        if dog.isOnTreatment, seesMedical {
            for medication in dog.medications where !medication.isPaused {
                for minute in medication.times.sorted() {
                    let at = startOfDay.addingTimeInterval(Double(minute) * 60)
                    let done = medication.doses.contains { $0.isGiven && cal.isDate($0.scheduledAt, equalTo: at, toGranularity: .minute) }
                    items.append(DayPlanItem(
                        id: "dose-\(medication.id)-\(minute)", time: at,
                        title: "\(medication.name) · \(medication.doseText)",
                        hint: medication.fastingMinutes > 0 ? "натощак \(medication.fastingMinutes) мин" : nil,
                        kind: .dose, isDone: done,
                        medication: medication,
                        gate: DoseGate.state(for: medication, events: events,
                                             scheduledAt: at, now: now)))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }
}
