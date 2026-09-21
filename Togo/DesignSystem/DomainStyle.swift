import SwiftUI

/// Мост между доменом и токенами.
///
/// Модели и логика про цвета не знают вообще: `SkillStatus` — это состояние
/// обучения, а не оттенок. Всё, что превращает домен в оформление, лежит здесь
/// одним файлом — так видно, что смысловых цветов ровно столько, сколько ролей.

extension SkillStatus {
    var tone: TGTone {
        switch self {
        case .notStarted: .neutral
        case .learning: .waiting
        case .works: .done
        }
    }

    var color: Color {
        switch self {
        case .notStarted: Token.Ink.secondary
        case .learning: Token.Status.waitingText
        case .works: Token.Action.doneText
        }
    }
}

extension MarkAccuracy {
    var color: Color {
        switch self {
        case .onTime: Token.Action.doneText
        case .almost: Token.Status.waitingText
        case .late: Token.Status.overdueText
        }
    }

    var tone: TGTone {
        switch self {
        case .onTime: .done
        case .almost: .waiting
        case .late: .alarm
        }
    }
}

extension StoolFlag {
    var tone: TGTone { raisesAlarm ? .alarm : .neutral }
}

extension LogEvent {
    /// Кровь — единственный флаг, поднимающий бытовую запись в терракот.
    var titleColor: Color { raisesAlarm ? Token.Status.overdueText : Token.Ink.primary }
    var symbolColor: Color { raisesAlarm ? Token.Status.overdueText : Token.Ink.silhouette }
}

extension NeedVerdict {
    /// Вердикт не красится в тревожное: «срочно» — это слово, а не красный экран.
    var tone: TGTone {
        switch self {
        case .urgent: .alarm
        case .likelyNeed: .waiting
        case .unknown, .probablyAttention, .episode: .neutral
        }
    }
}
