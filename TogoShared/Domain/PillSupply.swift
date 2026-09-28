import Foundation

/// Хватит ли таблеток до конца курса.
///
/// Пропуски чаще случаются не из забывчивости, а потому что таблетки
/// кончились в пятницу вечером, а аптека везёт два-три дня. Поэтому
/// предупреждать надо не когда кончились, а когда до конца осталось
/// меньше, чем идёт доставка.
nonisolated struct PillSupply: Equatable, Sendable {
    /// Сколько осталось.
    var left: Int
    /// Сколько было в пачке.
    var total: Int
    /// Сколько уходит в сутки.
    var perDay: Int
    /// До какого дня хватит.
    var lastDay: Date?
    /// До какого дня идёт курс, если он назначен.
    var courseEnds: Date?

    /// На сколько дней хватит.
    var days: Int {
        guard perDay > 0 else { return 0 }
        return left / perDay
    }

    /// Не хватит на столько дней курса.
    var shortfallDays: Int? {
        guard let courseEnds, let lastDay, lastDay < courseEnds else { return nil }
        return Calendar.current.dateComponents([.day], from: lastDay, to: courseEnds).day
    }

    /// «Таблеток на 4 дня».
    var headline: String {
        guard perDay > 0 else { return String(localized: "Счёт таблеток не ведётся") }
        return String(localized: "Таблеток на \(Fmt.days(days))")
    }
}

nonisolated enum PillSupplyAdvisor {
    /// За сколько дней предупреждать.
    ///
    /// Три дня — не круглое число, а срок доставки из аптеки: раньше
    /// предупреждать бессмысленно, позже — поздно.
    static let warningDays = 3

    static func supply(
        left: Int,
        total: Int,
        timesPerDay: Int,
        courseEnds: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PillSupply? {
        // Ноль в пачке значит «не считаем»: навязывать учёт тому, кто
        // покупает коробку в год, незачем.
        guard total > 0, timesPerDay > 0 else { return nil }

        let days = left / timesPerDay
        let lastDay = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))

        return PillSupply(left: left, total: total, perDay: timesPerDay,
                          lastDay: lastDay, courseEnds: courseEnds)
    }

    /// Пора ли говорить об этом вслух.
    static func needsWarning(_ supply: PillSupply?) -> Bool {
        guard let supply, supply.perDay > 0 else { return false }
        return supply.days <= warningDays || supply.shortfallDays != nil
    }
}
