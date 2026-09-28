import Foundation
import SwiftData

/// Смена схемы после приёма у врача.
///
/// Из хендофа (17c): «Старое и новое рядом, перечёркнуто только старое.
/// Вопрос „с какого момента“ задан явно — это место, где семьи чаще
/// всего ошибаются в первый день новой схемы».
///
/// Главное правило: **прошлые отметки не трогаем.** Меняется только план
/// вперёд. Иначе история приёмов задним числом станет неправдой — а её
/// потом читает тот же врач.
nonisolated struct ScheduleChange: Equatable, Sendable {
    /// С какого момента действует новое.
    enum StartsFrom: String, CaseIterable, Sendable {
        case tomorrowMorning
        case tonight

        var title: String {
            switch self {
            case .tomorrowMorning: String(localized: "С завтрашнего утра")
            case .tonight: String(localized: "Сегодня вечером")
            }
        }
    }

    var oldDoseText: String
    var oldTimes: [Int]
    var newDoseText: String
    var newTimes: [Int]
    var startsFrom: StartsFrom

    /// «дважды в день» / «один раз · утром».
    static func summary(_ times: [Int]) -> String {
        let sorted = times.sorted()
        switch sorted.count {
        case 0: return String(localized: "без расписания")
        case 1:
            let hour = sorted[0] / 60
            let when = hour < 12 ? String(localized: "утром") : (hour < 17 ? String(localized: "днём") : String(localized: "вечером"))
            return String(localized: "один раз · \(when)")
        case 2: return String(localized: "дважды в день")
        default: return "\(String(localized: "\(sorted.count) раз")) в день"
        }
    }

    /// С какого момента новое расписание вступает в силу.
    func effectiveFrom(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch startsFrom {
        case .tonight:
            return now
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            return tomorrow ?? now
        }
    }

    /// Какие уже заведённые отметки исчезнут.
    ///
    /// Считается заранее и показывается до нажатия: «Вечернее в 20:00
    /// удалится» — не сюрприз после сохранения.
    func doomedDoses(_ doses: [DoseRecord], now: Date = Date(),
                     calendar: Calendar = .current) -> [DoseRecord] {
        let from = effectiveFrom(now: now, calendar: calendar)
        let keep = Set(newTimes)
        return doses.filter { dose in
            guard dose.scheduledAt >= from, !dose.isGiven, !dose.isSkipped else { return false }
            let minute = calendar.component(.hour, from: dose.scheduledAt) * 60
                + calendar.component(.minute, from: dose.scheduledAt)
            return !keep.contains(minute)
        }
    }
}

nonisolated enum ScheduleChangeApplier {
    /// Применить новую схему.
    ///
    /// Возвращает, сколько будущих отметок убрано, — это надо сказать
    /// человеку теми же словами, какими его предупреждали.
    @MainActor
    @discardableResult
    static func apply(
        _ change: ScheduleChange,
        to medication: Medication,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) -> Int? {
        let doomed = change.doomedDoses(medication.doses, now: now, calendar: calendar)
        for dose in doomed { context.delete(dose) }

        // Прошлое остаётся как было: меняется только план вперёд.
        let былДоза = medication.doseText
        let былиЧасы = medication.times
        medication.doseText = change.newDoseText
        medication.times = change.newTimes.sorted()
        // Схема лечения — место, где молчание стоит дозы: экран покажет
        // новые часы, а напоминания придут по старым.
        guard context.persist(otherwise: {
            medication.doseText = былДоза
            medication.times = былиЧасы
        }) else { return nil }
        return doomed.count
    }
}
