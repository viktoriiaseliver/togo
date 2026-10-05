import Foundation
import SwiftData

/// Течка. Обычная запись в календаре, а не медицина.
///
/// Приложение ничего не диагностирует и не советует по здоровью: оно
/// запоминает даты, считает средний промежуток и подсказывает, когда
/// ждать следующую. Это то, что владельцы держат в голове или в заметках
/// и регулярно забывают.
@Model
final class HeatRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var note: String?

    var dog: Dog?

    init(startedAt: Date, endedAt: Date? = nil, note: String? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }

    var isOngoing: Bool { endedAt == nil }

    // Календарь аргументом — он несёт пояс читающего, и на нём стоят
    // «опасные дни». Замер 05.10: у семьи западнее владельца день цикла
    // смещался на сутки, и проверить это было нечем. Подробно —
    // в `CalendarDay`.

    func dayCount(calendar: Calendar = .current) -> Int? {
        guard let endedAt else { return nil }
        return CalendarDay.daysBetween(startedAt, endedAt, calendar: calendar) + 1
    }

    func dayNumber(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        CalendarDay.daysBetween(startedAt, date, calendar: calendar) + 1
    }
}

/// Расчёты по циклу. Отдельно от модели, чтобы их можно было проверить
/// тестами и не тащить в них SwiftData.
nonisolated enum HeatCycle {
    /// Ориентир для взрослой собаки — примерно раз в полгода. Он именно
    /// ориентир: у мелких пород чаще, у крупных реже, и всё это нормально.
    static let typicalIntervalDays = 180
    /// Сколько обычно длится. Нужно только чтобы подписать «идёт» и «закончилась».
    static let typicalDurationDays = 21
    /// Меньше двух записей — среднего нет, и врать про него нельзя.
    static let minimumRecordsForAverage = 2

    struct Forecast: Equatable, Sendable {
        var lastStart: Date?
        var averageIntervalDays: Int?
        var expectedNext: Date?
        var daysUntilNext: Int?
        var isEstimate: Bool
    }

    static func forecast(_ records: [HeatRecord], now: Date = Date()) -> Forecast {
        let starts = records.map(\.startedAt).sorted()
        guard let last = starts.last else {
            return Forecast(lastStart: nil, averageIntervalDays: nil,
                            expectedNext: nil, daysUntilNext: nil, isEstimate: true)
        }

        let intervals = zip(starts, starts.dropFirst()).compactMap {
            Calendar.current.dateComponents([.day], from: $0, to: $1).day
        }
        let average = intervals.count >= minimumRecordsForAverage - 1 && !intervals.isEmpty
            ? intervals.reduce(0, +) / intervals.count
            : nil

        let step = average ?? typicalIntervalDays
        let next = Calendar.current.date(byAdding: .day, value: step, to: last)
        let days = next.flatMap {
            Calendar.current.dateComponents([.day],
                                            from: Calendar.current.startOfDay(for: now),
                                            to: Calendar.current.startOfDay(for: $0)).day
        }

        return Forecast(lastStart: last,
                        averageIntervalDays: average,
                        expectedNext: next,
                        daysUntilNext: days,
                        isEstimate: average == nil)
    }
}
