import Foundation
import SwiftData

/// Повторяющееся дело: когти, вычёсывание, антипаразитарка, прививка, взвешивание.
/// Всё это собирается в одну утреннюю сводку, а не в восемь отдельных напоминаний.
@Model
final class CareTask {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var kindRaw: String = CareKind.periodic.rawValue
    var categoryRaw: String = CareCategory.grooming.rawValue

    /// Для регулярного: раз в сколько дней.
    var intervalDays: Int = 30
    /// Для «по дате»: когда именно и за сколько дней предупредить.
    var scheduledDate: Date?
    var remindDaysBefore: Int = 14

    var lastDone: Date?
    /// Для ежедневного: сколько дней подряд делали. Не награда, а зеркало.
    var streak: Int = 0

    /// Сезонное само знает про сезон: капли от клещей молчат зимой.
    var seasonStartMonth: Int?
    var seasonEndMonth: Int?

    /// Отложенное дважды подсвечивается в сводке, но не переходит в тревогу.
    var snoozeCount: Int = 0

    var dog: Dog?

    init(
        title: String,
        detail: String,
        kind: CareKind = .periodic,
        intervalDays: Int = 30,
        category: CareCategory = .grooming,
        lastDone: Date? = nil,
        scheduledDate: Date? = nil
    ) {
        self.title = title
        self.detail = detail
        self.kindRaw = kind.rawValue
        self.intervalDays = intervalDays
        self.categoryRaw = category.rawValue
        self.lastDone = lastDone
        self.scheduledDate = scheduledDate
    }

    var kind: CareKind {
        get { CareKind(rawValue: kindRaw) ?? .periodic }
        set { kindRaw = newValue.rawValue }
    }

    var category: CareCategory {
        get { CareCategory(rawValue: categoryRaw) ?? .grooming }
        set { categoryRaw = newValue.rawValue }
    }

    // MARK: Когда

    /// Даты нет: для регулярного не знаем, когда делали, для «по дате»
    /// не назначен день. Это не просрочка — но и не молчание навсегда:
    /// такое дело видно в отдельной группе и просит поставить дату.
    ///
    /// Раньше здесь была дыра: дело без даты никогда не становилось сроком,
    /// то есть заведённое напоминание не напоминало вообще ни о чём.
    var needsDate: Bool {
        switch kind {
        case .daily: false
        case .periodic: lastDone == nil
        case .dated: scheduledDate == nil
        }
    }

    var isNeverDone: Bool { needsDate }

    var dueDate: Date? {
        switch kind {
        case .daily:
            return Calendar.current.startOfDay(for: .now)
        case .periodic:
            guard let lastDone else { return nil }
            return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastDone)
        case .dated:
            return scheduledDate
        }
    }

    func daysUntilDue(from date: Date = Date()) -> Int? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: dueDate)).day
    }

    func isDoneToday(on date: Date = Date()) -> Bool {
        guard let lastDone else { return false }
        return Calendar.current.isDate(lastDone, inSameDayAs: date)
    }

    func isInSeason(on date: Date = Date()) -> Bool {
        guard let start = seasonStartMonth, let end = seasonEndMonth else { return true }
        let month = Calendar.current.component(.month, from: date)
        return start <= end ? (month >= start && month <= end) : (month >= start || month <= end)
    }

    /// Просится ли на главный экран прямо сейчас.
    func isDue(on date: Date = Date()) -> Bool {
        guard isInSeason(on: date) else { return false }
        switch kind {
        case .daily:
            return !isDoneToday(on: date)
        case .periodic:
            guard let days = daysUntilDue(from: date) else { return false }
            return days <= 0
        case .dated:
            guard let days = daysUntilDue(from: date) else { return false }
            return days <= remindDaysBefore
        }
    }

    /// Просрочено по-настоящему — это только про даты и регулярное.
    /// У ежедневного просрочки нет: пропущенный день не долг.
    func isOverdue(on date: Date = Date()) -> Bool {
        guard kind != .daily, isInSeason(on: date), let days = daysUntilDue(from: date) else { return false }
        return days < 0
    }

    /// Что написать в строке справа. Одна фраза на все три сорта ухода.
    func statusText(on date: Date = Date()) -> String {
        guard isInSeason(on: date) else { return "вне сезона" }
        switch kind {
        case .daily:
            if isDoneToday(on: date) { return streak > 1 ? "\(streak) дней подряд" : "сегодня сделали" }
            return streak > 1 ? "серия \(streak) дней" : "сегодня"
        case .periodic:
            guard let days = daysUntilDue(from: date) else { return "когда делали?" }
            if days < 0 { return "просрочено на \(Fmt.days(-days))" }
            if days == 0 { return "сегодня" }
            if days == 1 { return "завтра" }
            return "через \(Fmt.days(days))"
        case .dated:
            guard let days = daysUntilDue(from: date) else { return "когда делали?" }
            if days < 0 { return "просрочено" }
            if days == 0 { return "сегодня" }
            return Fmt.shortDay(dueDate ?? date)
        }
    }

    /// Отметить сделанным. Для ежедневного ведёт серию, для «по дате»
    /// двигает дату на следующий раз.
    func markDone(at date: Date = Date()) {
        if kind == .daily {
            let calendar = Calendar.current
            if let lastDone, let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(lastDone, inSameDayAs: yesterday) {
                streak += 1
            } else if !isDoneToday(on: date) {
                streak = 1
            }
        }
        if kind == .dated, let scheduled = scheduledDate, intervalDays > 0 {
            scheduledDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: scheduled)
        }
        lastDone = date
        snoozeCount = 0
    }

    /// Отменить отметку.
    ///
    /// Отметили не то — обычное дело: сработал свайп, зубы почистил
    /// кто-то другой, прививку перенесли. Без отката отметка о прививке
    /// сдвигала дату на год вперёд, и вернуть её было нельзя ничем,
    /// кроме как завести напоминание заново.
    func undoDone(previousDone: Date?) {
        if kind == .dated, let scheduled = scheduledDate, intervalDays > 0 {
            scheduledDate = Calendar.current.date(byAdding: .day, value: -intervalDays,
                                                  to: scheduled)
        }
        if kind == .daily {
            streak = max(0, streak - 1)
        }
        lastDone = previousDone
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

    /// Доза с условием: открывается через N минут после еды.
    ///
    /// Инсулин колют не по часам, а после того, как собака поела —
    /// иначе сахар падает в пустой желудок. Такая доза стоит в плане дня
    /// замком: отметить её раньше нельзя, а таймер стартует сам от
    /// отметки еды. Не поела — укол не открывается вовсе, и это не сбой,
    /// а вопрос к врачу.
    ///
    /// Ноль — обычная доза по часам.
    var minutesAfterMeal: Int = 0

    /// Есть ли у дозы условие по еде.
    var dependsOnMeal: Bool { minutesAfterMeal > 0 }
    var isPaused: Bool = false

    /// Сколько таблеток осталось и сколько было в пачке.
    ///
    /// Дыра, которой не было в списке: пропуски чаще случаются не
    /// из забывчивости, а потому что таблетки кончились в пятницу
    /// вечером. Счёт живёт на отметках приёма — отдельного учёта вести
    /// не надо, минус одна с каждой отметкой.
    ///
    /// Ноль в `stockTotal` значит «не считаем»: навязывать учёт тому,
    /// кто покупает по коробке в год, незачем.
    var stockLeft: Int = 0
    var stockTotal: Int = 0

    var prescriber: String?
    var cancelledAt: Date?
    var cancelledNote: String?

    var dog: Dog?

    @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
    var dosesStorage: [DoseRecord]?

    init(name: String, doseText: String, times: [Int], fastingMinutes: Int = 0) {
        self.name = name
        self.doseText = doseText
        self.times = times
        self.fastingMinutes = fastingMinutes
    }

    // CloudKit требует опциональных связей — см. пояснение в Dog.
    var doses: [DoseRecord] { dosesStorage ?? [] }

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
    /// Когда этот телефон в последний раз трогал отметку. См. `LogEvent`.
    var changedAt: Date = Date()

    /// Дозу решили пропустить.
    ///
    /// Пропуск — это запись, а не пустота: врач спрашивает именно про
    /// него, а иначе в истории непонятно, забыли отметить или правда
    /// не дали.
    var skippedAt: Date?
    var skippedBy: String?

    var medication: Medication?

    init(scheduledAt: Date) {
        self.scheduledAt = scheduledAt
    }

    static let claimTTL: TimeInterval = 45 * 60

    var isGiven: Bool { givenAt != nil }
    var isSkipped: Bool { skippedAt != nil }

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
