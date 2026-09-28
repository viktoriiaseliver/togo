import Foundation

/// Смена: кто дежурил, что закрыл и что переходит дальше.
///
/// Из хендофа (18e): «Вместо потока „Игорь отметил…“ ×6 — одно
/// уведомление в конце смены: что закрыто, что переходит. „Принять
/// смену“ — явный акт: незакрытое не повисает ничьим».
///
/// Это единственное, что снимает главный страх второго человека в семье:
/// не «я не увижу запись», а «я решу, что покормили, а на самом деле нет».
nonisolated struct Shift: Equatable, Sendable {
    var person: String
    var from: Date
    var to: Date

    func covers(_ date: Date) -> Bool { date >= from && date <= to }

    var hours: String {
        "\(Fmt.clock(from)) — \(Fmt.clock(to))"
    }
}

/// Пункт плана глазами смены.
nonisolated struct ShiftItem: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    /// До какого часа его ждали.
    var due: Date
    var isDone: Bool
    /// Кто закрыл.
    var by: String?

    /// Незакрытое, чей срок ещё не вышел, — это не провал, а работа,
    /// которая переходит следующему.
    func isOpen(at now: Date) -> Bool { !isDone }
}

nonisolated struct ShiftSummary: Equatable, Sendable {
    var shift: Shift
    var items: [ShiftItem]

    var done: [ShiftItem] { items.filter(\.isDone) }
    var open: [ShiftItem] { items.filter { !$0.isDone } }

    /// «5 из 6 закрыто».
    var headline: String { String(localized: "\(done.count) из \(items.count) закрыто") }

    /// Строка для уведомления: сначала сделанное, потом открытое —
    /// человек читает её на локскрине за секунду.
    func notification(now: Date = Date()) -> String {
        guard !items.isEmpty else { return String(localized: "Записей за смену нет.") }
        var parts: [String] = []

        let doneTitles = done.map { $0.title.lowercased() }
        if !doneTitles.isEmpty {
            parts.append(doneTitles.joined(separator: ", ").prefix(1).uppercased()
                         + doneTitles.joined(separator: ", ").dropFirst() + String(localized: " — сделано"))
        }
        if let next = open.min(by: { $0.due < $1.due }) {
            parts.append(String(localized: "Открыто: \(next.title.lowercased()) до \(Fmt.clock(next.due))"))
        }
        return parts.joined(separator: ". ") + "."
    }
}
