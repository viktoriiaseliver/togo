import Foundation
import SwiftData

/// Одна запись ленты дня. Всё, что видит человек на главном экране, — это они.
@Model
final class LogEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = LogKind.note.rawValue

    /// Кто записал. В ленте стоит инициал и галочка синхронизации:
    /// видно, что запись дошла до остальных, а не только «записалась у меня».
    var authorName: String = ""
    var isSynced: Bool = true

    var note: String?

    // Выход
    var outcomeRaw: String?
    var askSignalRaw: String?
    var durationSeconds: Int?

    // Стул
    var stoolFormRaw: String?
    var stoolFlagsRaw: [String] = []

    // Еда, вода, лакомство
    var grams: Int?
    var milliliters: Int?
    var fromPortion: Bool = false

    // Инцидент
    var incidentKindRaw: String?
    var incidentDetailRaw: String?
    var toldFamily: Bool = false

    // Ссылки
    var trainingSessionID: UUID?
    var medicationID: UUID?
    var careTaskID: UUID?

    /// Удаление обратимо 5 секунд и оставляет след в истории:
    /// молчаливой перезаписи и тихого удаления в приложении нет нигде.
    var deletedAt: Date?
    var deletedBy: String?

    var dog: Dog?

    init(kind: LogKind, date: Date = Date(), authorName: String) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.date = date
        self.authorName = authorName
    }

    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var outcome: OutingOutcome? {
        get { outcomeRaw.flatMap(OutingOutcome.init) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var askSignal: AskSignal? {
        get { askSignalRaw.flatMap(AskSignal.init) }
        set { askSignalRaw = newValue?.rawValue }
    }

    var stoolForm: StoolForm? {
        get { stoolFormRaw.flatMap(StoolForm.init) }
        set { stoolFormRaw = newValue?.rawValue }
    }

    var stoolFlags: Set<StoolFlag> {
        get { Set(stoolFlagsRaw.compactMap(StoolFlag.init)) }
        set { stoolFlagsRaw = newValue.map(\.rawValue).sorted() }
    }

    var incidentKind: IncidentKind? {
        get { incidentKindRaw.flatMap(IncidentKind.init) }
        set { incidentKindRaw = newValue?.rawValue }
    }

    var vomitDetail: VomitDetail? {
        get { incidentDetailRaw.flatMap(VomitDetail.init) }
        set { incidentDetailRaw = newValue?.rawValue }
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Кровь — единственный флаг, поднимающий бытовую запись в терракот.
    var raisesAlarm: Bool {
        if stoolFlags.contains(where: \.raisesAlarm) { return true }
        if let vomitDetail, vomitDetail.raisesAlarm { return true }
        return false
    }

    /// Подпись под строкой ленты: «стул как всегда · моча».
    var subtitle: String? {
        var parts: [String] = []
        if let outcome { parts.append(outcome.shortTitle) }
        if let stoolForm { parts.append(stoolForm.title.lowercased()) }
        if !stoolFlags.isEmpty { parts.append(stoolFlags.map { $0.title.lowercased() }.joined(separator: ", ")) }
        if let grams { parts.append("\(grams) г") }
        if let milliliters { parts.append("\(milliliters) мл") }
        if let durationSeconds, durationSeconds > 0 { parts.append("\(durationSeconds / 60) мин") }
        if let incidentKind { parts.append(incidentKind.title.lowercased()) }
        if let vomitDetail { parts.append(vomitDetail.title) }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
