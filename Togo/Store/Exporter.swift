import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Выгрузка. Ничего не надо вспоминать: всё, что попадёт в отчёт,
/// уже записано в бытовой ленте. CSV — без подписки.
nonisolated enum Exporter {
    static func csv(events: [LogEvent]) -> String {
        let header = [
            String(localized: "дата"), String(localized: "время"), String(localized: "тип"), String(localized: "результат"), String(localized: "форма стула"), String(localized: "особенности"),
            String(localized: "граммы"), String(localized: "миллилитры"), String(localized: "минуты"), String(localized: "как попросил"), String(localized: "инцидент"),
            String(localized: "прогулка"), String(localized: "автор"), String(localized: "заметка"),
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let active = Diary.active(events)
        // Связь отметки с прогулкой живёт в `walkEventID`; подпись
        // «на прогулке» — только слово, и словами эту связь уже пробовали
        // (см. комментарий в `LogEvent`). В выгрузке до сих пор были одни
        // слова: по ней нельзя было сказать, к какой прогулке относится
        // отметка, — а именно это и спрашивают, глядя на две отметки
        // «на прогулке» в стороне от единственной прогулки дня.
        let walkStart = Dictionary(active.filter { $0.kind == .walk }.map { ($0.id, $0.date) },
                                   uniquingKeysWith: { first, _ in first })

        var rows = [header.joined(separator: ";")]
        for event in active.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                formatter.string(from: event.date),
                Fmt.clock(event.date),
                event.kind.title,
                event.outcome?.shortTitle ?? "",
                event.stoolForm?.title ?? "",
                event.stoolFlags.map(\.title).joined(separator: ", "),
                event.grams.map(String.init) ?? "",
                event.milliliters.map(String.init) ?? "",
                event.durationSeconds.map { String($0 / 60) } ?? "",
                event.askSignal?.title ?? "",
                event.incidentKind?.title ?? "",
                event.walkEventID.flatMap { walkStart[$0] }.map(Fmt.clock) ?? "",
                event.authorName,
                event.note ?? "",
            ]
            rows.append(fields.map(escape).joined(separator: ";"))
        }
        return rows.joined(separator: "\n")
    }

    /// Бристольская шкала живёт только здесь — в базе и в выгрузке для врача.
    static func clinicalCSV(events: [LogEvent]) -> String {
        var rows = [String(localized: "дата;время;форма;бристоль;особенности;автор")]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for event in Diary.active(events).filter({ $0.kind == .stool }).sorted(by: { $0.date < $1.date }) {
            rows.append([
                formatter.string(from: event.date),
                Fmt.clock(event.date),
                event.stoolForm?.title ?? "",
                event.stoolForm.map { String($0.bristolScore) } ?? "",
                event.stoolFlags.map(\.title).joined(separator: ", "),
                event.authorName,
            ].map(escape).joined(separator: ";"))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Пишем во временную папку: файл живёт ровно до конца шаринга.
    static func writeTemporary(_ text: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Обёртка, чтобы отдать CSV в системный `ShareLink`.
nonisolated struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            // Отмечаем здесь, а не у кнопки: `ShareLink` не даёт действия,
            // а сюда управление приходит ровно тогда, когда файл правда
            // ушёл в «Поделиться».
            UsageLog.note(.export, "csv")
            return SentTransferredFile(try Exporter.writeTemporary(file.text, named: file.name))
        }
    }
}
