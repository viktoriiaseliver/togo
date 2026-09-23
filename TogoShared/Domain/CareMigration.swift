import Foundation
import SwiftData

/// Разовая починка ухода у тех, кто ставил приложение до его переделки.
///
/// Раньше уход был устроен одинаково для всего: «раз в N дней от последнего
/// раза». Отсюда два наследства на живых устройствах:
///
/// * «Уши и зубы» одной строкой раз в неделю — а зубы чистят каждый день,
///   налёт твердеет за сутки;
/// * прививки как «раз в 365 дней от последнего раза», хотя у них есть
///   конкретная дата.
///
/// Правится один раз и молча: человек не должен ничего чинить руками.
nonisolated enum CareMigration {
    /// Что во что превращается. Ключ — старое название.
    static let dailyTitles: Set<String> = ["Зубы", "Вычесать", "Лапы после улицы", "Глаза"]
    static let datedTitles: Set<String> = [
        "Бешенство", "Комплексная", "Прививка от бешенства",
        "Комплексная прививка", "Осмотр у врача",
    ]

    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Int {
        guard let tasks = try? context.fetch(FetchDescriptor<CareTask>()) else { return 0 }
        var changed = 0

        for task in tasks {
            // «Уши и зубы» — два разных дела с разной частотой.
            if task.title == "Уши и зубы" {
                task.title = "Уши"
                task.detail = "осмотреть и почистить, если нужно"
                task.kind = .periodic
                task.intervalDays = 7

                let teeth = CareTask(title: "Зубы", detail: "чистить каждый день — налёт твердеет за сутки",
                                     kind: .daily, intervalDays: 1, category: .grooming)
                teeth.dog = task.dog
                context.insert(teeth)
                changed += 2
                continue
            }

            if dailyTitles.contains(task.title), task.kind != .daily {
                task.kind = .daily
                task.intervalDays = 1
                changed += 1
                continue
            }

            if datedTitles.contains(task.title), task.kind != .dated {
                task.kind = .dated
                // Дату не выдумываем: её поставит человек. До тех пор дело
                // просто ждёт и ни о чём не напоминает.
                task.scheduledDate = nil
                changed += 1
            }
        }

        // Миграция, которая не записалась, повторится при следующем
        // запуске — но если молчать, она будет повторяться вечно.
        if changed > 0, !context.persist(otherwise: {}) {
            log.error("миграция не записалась")
            return 0
        }
        return changed
    }
}
