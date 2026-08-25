import Foundation

// MARK: - Обучение

/// Обучение не бинарно: «выучена / не выучена» — вредная рамка.
nonisolated enum SkillStatus: String, Codable, CaseIterable, Sendable {
    case notStarted, learning, works

    var title: String {
        switch self {
        case .notStarted: "не начинали"
        case .learning: "учится"
        case .works: "получается"
        }
    }

}

/// Оценка описывает условия, а не животное. «Хуже» из макета убрана.
nonisolated enum SessionObservation: String, Codable, CaseIterable, Sendable {
    case easy, distracted, yawned, refusedFood

    var title: String {
        switch self {
        case .easy: "легко, можно сложнее"
        case .distracted: "отвлекался"
        case .yawned: "зевал, отворачивался"
        case .refusedFood: "не брал еду"
        }
    }

    /// Отказ от корма останавливает занятие и снимает оценку:
    /// собака за порогом и учиться сейчас не может.
    var stopsSession: Bool { self == .refusedFood }
}

/// Чем маркируешь. Маркер всегда один и тот же и больше ничего не значит.
nonisolated enum MarkerKind: String, Codable, CaseIterable, Sendable {
    case clicker, wordYes, tongueClick

    var title: String {
        switch self {
        case .clicker: "кликер"
        case .wordYes: "слово «да»"
        case .tongueClick: "щелчок языком"
        }
    }
}

/// Оценка одной отметки маркера по задержке.
nonisolated enum MarkAccuracy: String, Sendable {
    case onTime, almost, late

    static func from(delayMilliseconds ms: Int) -> MarkAccuracy {
        // До полусекунды собака связывает маркер со своим действием.
        // После секунды она уже сделала что-то другое.
        if ms <= 500 { return .onTime }
        if ms <= 1000 { return .almost }
        return .late
    }

    var title: String {
        switch self {
        case .onTime: "в момент"
        case .almost: "почти"
        case .late: "поздно"
        }
    }

}
