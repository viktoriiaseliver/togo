import Foundation

nonisolated enum Fmt {
    static let time: Date.FormatStyle = .dateTime.hour().minute()

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func clock(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide)) + " · " + date.formatted(.dateTime.day().month(.wide))
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// «5 ч 20 мин» — так же, как в макете, без «5:20:00».
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes) мин" }
        if minutes == 0 { return "\(hours) ч" }
        return "\(hours) ч \(minutes) мин"
    }

    /// Промежуток для ленты: коротко и без ложной точности.
    ///
    /// «4 ч 58 мин» между записями — это точность, которой там неоткуда
    /// взяться и которая никому не нужна: промежуток читают глазами,
    /// чтобы понять порядок величины. Округляем до получаса, а после двух
    /// часов минуты выбрасываем совсем.
    /// Число с одним знаком после запятой — и без него, если знак нулевой.
    /// «4 раза в день» читается, «4,0 раза» выглядит отчётом.
    static func decimal(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Часы и минуты для героя: «2 ч 12 м».
    ///
    /// Секундомер здесь не годится — он считает минуты и секунды,
    /// и два с половиной часа превращались в «165:16».
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let hours = minutes / 60
        guard hours > 0 else { return "\(minutes) мин" }
        let rest = minutes % 60
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) м"
    }

    /// Порядковое числительное для строки «третий раз за шесть часов».
    ///
    /// Дальше десятого не идём: если рвота случилась одиннадцать раз,
    /// человек уже в клинике, а не читает подпись.
    static func ordinal(_ value: Int) -> String {
        let words = ["", "первый", "второй", "третий", "четвёртый", "пятый",
                     "шестой", "седьмой", "восьмой", "девятый", "десятый"]
        return words.indices.contains(value) ? words[value] : "\(value)-й"
    }

    static func gap(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 90 { return "\(minutes) мин" }

        let hours = Double(minutes) / 60
        if minutes >= 120 { return "\(Int(hours.rounded())) ч" }

        let half = (Double(minutes) / 30).rounded() * 30
        let wholeHours = Int(half) / 60
        let rest = Int(half) % 60
        return rest == 0 ? "\(wholeHours) ч" : "\(wholeHours) ч \(rest) мин"
    }

    static func stopwatch(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func weight(_ kg: Double) -> String {
        String(format: "%.1f кг", kg).replacingOccurrences(of: ".", with: ",")
    }

    /// Русские окончания там, где число видно человеку.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) \(one)" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) \(few)" }
        return "\(n) \(many)"
    }

    static func days(_ n: Int) -> String { plural(n, "день", "дня", "дней") }
    static func outings(_ n: Int) -> String { plural(n, "выход", "выхода", "выходов") }
}
