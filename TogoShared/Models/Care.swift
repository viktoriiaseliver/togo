import Foundation
import SwiftData

/// Повторяющееся дело: когти, вычёсывание, антипаразитарка, прививка, взвешивание.
/// Всё это собирается в один утренний бриф, а не в восемь отдельных пушей.
@Model
final class CareTask {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var intervalDays: Int = 30
    var lastDone: Date?
    var categoryRaw: String = CareCategory.grooming.rawValue

    /// Сезонное само знает про сезон: капли от клещей молчат зимой.
    var seasonStartMonth: Int?
    var seasonEndMonth: Int?

    /// Отложенное дважды подсвечивается в брифе, но не переходит в тревогу.
    var snoozeCount: Int = 0

    var dog: Dog?

    init(title: String, detail: String, intervalDays: Int, category: CareCategory, lastDone: Date? = nil) {
        self.title = title
        self.detail = detail
        self.intervalDays = intervalDays
        self.categoryRaw = category.rawValue
        self.lastDone = lastDone
    }

    var category: CareCategory {
        get { CareCategory(rawValue: categoryRaw) ?? .grooming }
        set { categoryRaw = newValue.rawValue }
    }

    var dueDate: Date? {
        guard let lastDone else { return Date() }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastDone)
    }

    func isInSeason(on date: Date = Date()) -> Bool {
        guard let start = seasonStartMonth, let end = seasonEndMonth else { return true }
        let month = Calendar.current.component(.month, from: date)
        return start <= end ? (month >= start && month <= end) : (month >= start || month <= end)
    }

    func daysUntilDue(from date: Date = Date()) -> Int? {
        guard let dueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                               to: Calendar.current.startOfDay(for: dueDate)).day
    }

    func isDue(on date: Date = Date()) -> Bool {
        guard isInSeason(on: date), let days = daysUntilDue(from: date) else { return false }
        return days <= 0
    }
}

/// Схему лечения меняет только владелец. Остальные видят и исполняют.
@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var doseText: String = ""
    /// Минуты от полуночи.
    var times: [Int] = []
    /// Окно натощак после дозы: еда внутри него мешает всасыванию.
    var fastingMinutes: Int = 0
    var isPaused: Bool = false
    var prescriber: String?
    var cancelledAt: Date?
    var cancelledNote: String?

    var dog: Dog?

    @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
    var doses: [DoseRecord] = []

    init(name: String, doseText: String, times: [Int], fastingMinutes: Int = 0) {
        self.name = name
        self.doseText = doseText
        self.times = times
        self.fastingMinutes = fastingMinutes
    }

    var scheduleSummary: String {
        let clock = times.sorted().map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: " и ")
        return fastingMinutes > 0 ? "\(clock) · натощак \(fastingMinutes) мин" : clock
    }
}

@Model
final class DoseRecord {
    var id: UUID = UUID()
    var scheduledAt: Date = Date()
    var givenAt: Date?
    var givenBy: String?
    /// «Беру на себя» с TTL 45 минут снимает двойную дозу.
    var claimedBy: String?
    var claimedAt: Date?
    /// Отмена дозы оставляет запись об отмене, а не стирает её.
    var cancelledAt: Date?
    var cancelReason: String?

    var medication: Medication?

    init(scheduledAt: Date) {
        self.scheduledAt = scheduledAt
    }

    static let claimTTL: TimeInterval = 45 * 60

    var isGiven: Bool { givenAt != nil }

    func claimIsActive(at date: Date = Date()) -> Bool {
        guard let claimedAt else { return false }
        return date.timeIntervalSince(claimedAt) < Self.claimTTL
    }

    /// Лестница эскалации: т−10 дежурному, т+30 со-владельцам, т+60 всем и запись «пропуск».
    func escalationStage(at date: Date = Date()) -> Int {
        if isGiven || cancelledAt != nil { return 0 }
        let minutes = date.timeIntervalSince(scheduledAt) / 60
        if minutes >= 60 { return 3 }
        if minutes >= 30 { return 2 }
        if minutes >= -10 { return 1 }
        return 0
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var kg: Double = 0
    var dog: Dog?

    init(date: Date = Date(), kg: Double) {
        self.date = date
        self.kg = kg
    }
}
