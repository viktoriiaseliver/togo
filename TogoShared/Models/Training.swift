import Foundation
import SwiftData

/// Навык переносится по трём осям: кто просит, где просят и что вокруг.
/// «Ко мне» дома и «ко мне» на улице рядом с другой собакой — два разных навыка.
@Model
final class TrainingStep {
    var id: UUID = UUID()
    var cue: String = ""             // «Ко мне»
    var place: String = ""           // «Коридор»
    var person: String = ""          // «Виктория»
    var distanceMeters: Int = 2
    var statusRaw: String = SkillStatus.notStarted.rawValue
    /// Шаг закрыт, когда получилось 4 раза из 5 в двух занятиях подряд.
    var consecutiveGoodSessions: Int = 0
    var order: Int = 0

    var dog: Dog?

    init(cue: String, place: String, person: String, distanceMeters: Int, order: Int = 0) {
        self.cue = cue
        self.place = place
        self.person = person
        self.distanceMeters = distanceMeters
        self.order = order
    }

    var status: SkillStatus {
        get { SkillStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var summary: String { String(localized: "\(place), \(distanceMeters) м") }
    var fullSummary: String { String(localized: "\(cue) · \(place) · \(person) · \(distanceMeters) метров") }
    var isClosed: Bool { consecutiveGoodSessions >= 2 }
}

/// Занятие живёт отдельно от прогулки: 2–5 минут, до трёх раз в день.
/// Приложение здесь — секундомер и зеркало, а не счётчик корма.
@Model
final class TrainingSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var durationSeconds: Int = 0
    var cue: String = ""
    var place: String = ""
    var person: String = ""
    var distanceMeters: Int = 2

    /// Задержки маркера в миллисекундах. Пишутся всегда, показываются после.
    var markDelaysMs: [Int] = []
    var successes: Int = 0
    var attempts: Int = 0
    var gramsUsed: Int = 0
    var observationsRaw: [String] = []
    /// После трёх минут приложение перестаёт называть это занятием
    /// и не пишет прогресс: собака уже угадывает, а не учится.
    var countsTowardProgress: Bool = true

    var dog: Dog?

    init(cue: String, place: String, person: String, distanceMeters: Int) {
        self.cue = cue
        self.place = place
        self.person = person
        self.distanceMeters = distanceMeters
    }

    var observations: Set<SessionObservation> {
        get { Set(observationsRaw.compactMap(SessionObservation.init)) }
        set { observationsRaw = newValue.map(\.rawValue).sorted() }
    }

    var onTimeMarks: Int { markDelaysMs.filter { MarkAccuracy.from(delayMilliseconds: $0) == .onTime }.count }

    var averageDelayMs: Int {
        guard !markDelaysMs.isEmpty else { return 0 }
        return markDelaysMs.reduce(0, +) / markDelaysMs.count
    }

    /// «4 из 5» — не «сделали 100 повторов», а «работает предсказуемо».
    var isGoodSession: Bool { attempts > 0 && Double(successes) / Double(attempts) >= 0.8 }
    var isPoorSession: Bool { attempts > 0 && Double(successes) / Double(attempts) < 0.6 }

    /// Отказ от корма, за который собака обычно работает, снимает оценку целиком.
    var isVoided: Bool { observations.contains(where: \.stopsSession) }
}

/// Подготовка к процедурам: дать лапу, стоять при осмотре, зайти в переноску.
/// Приложение уже знает, что забор крови будет, — и может предложить готовиться.
@Model
final class ProcedureSkill {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var statusRaw: String = SkillStatus.notStarted.rawValue
    var targetDate: Date?
    var successes: Int = 0
    var attempts: Int = 0

    init(title: String, detail: String, targetDate: Date? = nil) {
        self.title = title
        self.detail = detail
        self.targetDate = targetDate
    }

    var status: SkillStatus {
        get { SkillStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }
}
