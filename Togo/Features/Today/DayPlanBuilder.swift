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
    /// - Parameter часСводки: `Settings.briefHour`. `nil` — зовущий
    ///   про него не знает, и пункт ухода останется без части дня.
    static func items(dog: Dog?, events: [LogEvent], now: Date = Date(),
                      seesMedical: Bool = true,
                      часСводки: Int? = nil) -> [DayPlanItem] {
        guard let dog else { return [] }
        var items: [DayPlanItem] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let mealEvents = Diary.onDay(events, now).filter { $0.kind == .meal }
        let doneMealTimes = mealEvents.map(\.date)

        // Каждая запись закрывает ровно один пункт — ближайший к себе.
        // Часы берутся у `часыКормленийНа(_:)`, а не у `mealTimes`:
        // на сутки, которым человек назначил разовое исключение, план
        // дня обязан показывать названный им час, иначе приложение
        // «забывает» то, что ему сказали час назад.
        let mealMinutes = dog.часыКормленийНа(now, calendar: cal).sorted()
        let сегодняИначе = dog.естьРазовоеИсключение(now, calendar: cal)
        // Разметка, а не `[Bool]`: пункту нужен не только исход,
        // но и ЗАПИСЬ, которая его закрыла, — иначе снятие отметки
        // и итог смены ситтера ищут её заново, каждый по своему
        // правилу.
        let разметка = MealSchedule.разметить(planned: mealMinutes, logged: doneMealTimes,
                                             startOfDay: startOfDay)
        for (index, minute) in mealMinutes.enumerated() {
            let at = cal.date(minuteOfDay: minute, on: startOfDay)
            // Сколько выйдет до этого кормления от ПРОШЛОГО — от записи,
            // которую назвала разметка, а не от «последней записи о еде».
            // Второе правило рядом с первым разошлось бы: на этом Togo
            // ловился трижды и чинил это 04.11 тем же коммитом, что завёл
            // `закрытаЗаписью`.
            let промежуток = (index > 0 ? разметка.закрыто[index - 1] : nil)
                .flatMap { запись in
                    MealSchedule.промежуток(planned: mealMinutes, слот: index,
                                            фактПрошлого: mealEvents[запись].date,
                                            датаСлота: at)
                }
            // Граммов в заголовке нет, пока нормы нет: порция считается
            // из неё, и выдуманное число в плане дня человек выполняет
            // не задумываясь — это самый короткий путь от умолчания
            // до миски.
            items.append(DayPlanItem(id: "meal-\(minute)", time: at,
                                     title: dog.servingGrams > 0
                                         ? String(localized: "Еда · \(dog.servingGrams) г")
                                         : String(localized: "Еда"),
                                     hint: dog.foodBrand, kind: .meal,
                                     isDone: разметка.закрыто[index] != nil,
                                     фактВремя: разметка.закрыто[index].map { mealEvents[$0].date },
                                     промежуток: промежуток,
                                     закрытаЗаписью: разметка.закрыто[index].map { mealEvents[$0].id },
                                     сегодняИначе: сегодняИначе))
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
                time: cal.date(minuteOfDay: dog.sleepMinuteOfDay, on: startOfDay),
                title: task.title,
                hint: task.detail.isEmpty ? nil : task.detail,
                kind: .care,
                isDone: task.isDoneToday(on: now),
                careTask: task,
                showsTime: false,
                частьДня: часСводки.map(ЧастьДня.по(часу:))
            ))
        }

        if dog.isOnTreatment, seesMedical {
            for medication in dog.medications where !medication.isPaused {
                for minute in medication.times.sorted() {
                    let at = cal.date(minuteOfDay: minute, on: startOfDay)
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
