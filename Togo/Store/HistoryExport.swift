import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// График истории — врачу, вместе с едой и препаратами за те же дни.
///
/// Экран истории обещал это словами с первого дня, а выгрузки не было:
/// врачу показывали столбики, а даты еды и доз искали в другом месте.
/// Строка — день: значение графика, сколько съела, сколько кормлений,
/// какие дозы дали и во сколько, был ли в этот день эпизод.
///
/// Отчёты врачу бесплатны — выгрузка не спрашивает подписку.
nonisolated enum HistoryExport {
    /// Данная доза: во сколько и какой препарат.
    nonisolated struct Dose: Sendable, Equatable {
        let at: Date
        let name: String
    }

    /// - Parameters:
    ///   - days: дни периода графика, по возрастанию.
    ///   - valueTitle: как называется столбец графика (фильтр).
    ///   - values: значение графика по началу дня. Нет ключа — пустая клетка:
    ///     день без взвешивания не «ноль килограммов».
    ///   - episodeDays: начала дней, накрытых эпизодом.
    static func csv(days: [Date],
                    valueTitle: String,
                    values: [Date: Double],
                    events: [LogEvent],
                    doses: [Dose],
                    episodeDays: Set<Date>,
                    calendar: Calendar = .current) -> String {
        let header = [
            String(localized: "дата"),
            valueTitle,
            String(localized: "съедено, г"),
            String(localized: "кормлений"),
            String(localized: "дозы"),
            String(localized: "эпизод"),
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone

        var rows = [header.map(escape).joined(separator: ";")]
        for day in days {
            let start = calendar.startOfDay(for: day)
            let summary = Diary.summary(events, day: start, dog: nil)
            let ofDay = doses
                .filter { calendar.isDate($0.at, inSameDayAs: start) }
                .sorted { $0.at < $1.at }
                .map { "\(Fmt.clock($0.at)) \($0.name)" }
            let fields: [String] = [
                formatter.string(from: start),
                values[start].map(Fmt.decimal) ?? "",
                summary.eatenGrams > 0 ? String(summary.eatenGrams) : "",
                summary.meals > 0 ? String(summary.meals) : "",
                ofDay.joined(separator: ", "),
                episodeDays.contains(start) ? String(localized: "да") : "",
            ]
            rows.append(fields.map(escape).joined(separator: ";"))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Обёртка, чтобы отдать выгрузку истории в системный `ShareLink`.
/// Своя, а не `CSVFile`: в журнале действий видно, что ушло именно врачу.
nonisolated struct HistoryCSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            UsageLog.note(.export, "history-csv")
            return SentTransferredFile(try Exporter.writeTemporary(file.text, named: file.name))
        }
    }
}
