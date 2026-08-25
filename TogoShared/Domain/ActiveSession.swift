import Foundation

/// Идущий выход или прогулка.
///
/// Разница не в длительности, а в том, зачем вышли. Выход — по нужде,
/// две минуты, у него один вопрос в конце: сходил или нет. Прогулка —
/// это режим: таймер идёт, а человек по ходу отмечает, что собака сделала,
/// одной рукой и не думая.
///
/// Время считается от `startedAt`, а не счётчиком: приложение можно свернуть,
/// заблокировать телефон и убрать в карман — секунды не собьются.
nonisolated struct ActiveSession: Equatable, Sendable {
    enum Kind: String, Sendable {
        case outing
        case walk

        var title: String { self == .outing ? "Выход" : "Прогулка" }
        var runningTitle: String { self == .outing ? "выход идёт" : "гуляем" }
        var pausedTitle: String { self == .outing ? "выход на паузе" : "на паузе" }
    }

    struct Mark: Equatable, Identifiable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case urine, stool, water, treat, training, incident, note

            var title: String {
                switch self {
                case .urine: "Пописал"
                case .stool: "Стул"
                case .water: "Попил"
                case .treat: "Лакомство"
                case .training: "Занятие"
                case .incident: "Инцидент"
                case .note: "Заметка"
                }
            }

            var symbol: String {
                switch self {
                case .urine: "drop"
                case .stool: "leaf"
                case .water: "waterbottle"
                case .treat: "sparkles"
                case .training: "target"
                case .incident: "exclamationmark.triangle"
                case .note: "text.alignleft"
                }
            }

            /// В какую запись ленты превращается отметка.
            var logKind: LogKind {
                switch self {
                case .urine: .outing
                case .stool: .stool
                case .water: .water
                case .treat: .treat
                case .training: .training
                case .incident: .incident
                case .note: .note
                }
            }

            /// Отметки, которые ставят по несколько раз за прогулку.
            var isRepeatable: Bool { self == .urine || self == .stool || self == .water }
        }

        let id = UUID()
        var kind: Kind
        var at: Date

        init(kind: Kind, at: Date = Date()) {
            self.kind = kind
            self.at = at
        }
    }

    var kind: Kind
    var startedAt: Date
    var startedBy: String
    var marks: [Mark] = []

    /// Когда поставили на паузу. Пауза нужна не для красоты: зашли
    /// в магазин, встретили знакомого, ждёте у перехода — время идёт,
    /// а прогулки в этот момент нет.
    var pausedAt: Date?
    /// Сколько уже простояли на паузе за эту прогулку.
    var pausedTotal: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }

    /// Чистое время прогулки: без пауз.
    func duration(at now: Date = Date()) -> TimeInterval {
        let raw = max(0, now.timeIntervalSince(startedAt))
        let current = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, raw - pausedTotal - current)
    }

    mutating func pause(at now: Date = Date()) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date = Date()) {
        guard let pausedAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    func count(of kind: Mark.Kind) -> Int {
        marks.filter { $0.kind == kind }.count
    }

    /// Короткая сводка для карточки и для итога: «моча 2 · стул · вода».
    var tally: String {
        let order: [Mark.Kind] = [.urine, .stool, .water, .treat, .training, .incident]
        let parts: [String] = order.compactMap { kind in
            let count = count(of: kind)
            guard count > 0 else { return nil }
            return count > 1 ? "\(kind.title.lowercased()) ×\(count)" : kind.title.lowercased()
        }
        return parts.isEmpty ? "пока ничего не отмечено" : parts.joined(separator: " · ")
    }

    /// Результат выхода выводится из отметок — спрашивать лишний раз незачем.
    var outcome: OutingOutcome? {
        let urine = count(of: .urine) > 0
        let stool = count(of: .stool) > 0
        switch (urine, stool) {
        case (true, true): return .both
        case (true, false): return .urine
        case (false, true): return .stool
        case (false, false): return marks.isEmpty ? nil : OutingOutcome.none
        }
    }
}
