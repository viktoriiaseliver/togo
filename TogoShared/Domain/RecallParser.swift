import Foundation

/// Разбор дозаписи, написанной словами.
///
/// Человек пишет всё целиком, своими словами и задним числом:
/// «13.09.26 был понос», «кормили 3 раза в день с 04.09 по 20.09»,
/// «гуляли примерно каждый день по 4 часа с 04.09 по 20.09».
///
/// **Правилами, а не моделью.** Сети у приложения нет — это красная линия
/// продукта, и отправлять текст о собаке наружу ради разбора нельзя.
/// Значит разбор целиком здесь: даты, диапазоны, виды, количества.
///
/// **Непонятое не молчит.** Строка, которую разобрать не вышло, возвращается
/// как `.notUnderstood` вместе с исходным текстом — её показывают человеку
/// и дают поправить руками. Тихо проглотить строку нельзя: это вернёт ровно
/// ту дыру в истории, ради закрытия которой всё и делается.
///
/// **Период — не семнадцать прогулок.** «Каждый день по 4 часа с 04.09
/// по 20.09» превращается в одну запись-период, а не в семнадцать событий
/// с придуманным временем: придуманное время в выгрузке врачу стало бы
/// неотличимо от измеренного. Разбор — `docs/ТЗ-дозапись-задним-числом.md`.
nonisolated enum RecallParser {

    // MARK: Что получается на выходе

    public struct Moment: Equatable {
        public var kind: LogKind
        public var at: Date
        public var grams: Int?
        public var stool: StoolForm?
        /// Сколько раз за день, если сказано «3 раза».
        public var times: Int?
    }

    public struct Period: Equatable {
        public var kind: LogKind
        public var from: Date
        public var to: Date
        /// Сколько раз в день — «кормили 3 раза в день».
        public var timesPerDay: Int?
        /// Сколько длилось за раз — «по 4 часа».
        public var durationSeconds: Int?

        /// Сколько суток покрывает период, включительно.
        public var days: Int {
            let calendar = Calendar.current
            let a = calendar.startOfDay(for: from), b = calendar.startOfDay(for: to)
            return (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        }

        /// Разложить период по дням — по одному черновику на сутки.
        ///
        /// **Это не то же самое, что выдумать семнадцать записей.** Черновики
        /// показываются человеку списком: он видит каждый день отдельно,
        /// правит дату, дописывает своими словами («в среду почти не гуляли»)
        /// и выбрасывает лишние. В базу уходит только то, что он подтвердил.
        ///
        /// Час не подставляется **ничем**: у каждого дня `date` — начало
        /// суток, а `isDayOnly` говорит, что точнее не известно. Придуманное
        /// «14:02» в выгрузке врачу стало бы неотличимо от измеренного,
        /// а «13 сентября» — честная правда.
        public func byDay() -> [DayDraft] {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: from)
            return (0..<max(days, 0)).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start)
                else { return nil }
                return DayDraft(kind: kind, day: day,
                                timesPerDay: timesPerDay, durationSeconds: durationSeconds)
            }
        }
    }

    /// Один день из разложенного периода — до того, как человек его
    /// подтвердил. Дату можно поменять, описание — дописать.
    public struct DayDraft: Equatable {
        public var kind: LogKind
        /// Начало суток. Часа нет и не будет: см. `Period.byDay()`.
        public var day: Date
        public var timesPerDay: Int?
        public var durationSeconds: Int?
        /// Своими словами — то, что человек допишет к этому дню.
        /// Пусто, пока он не написал.
        public var note: String?
        /// Снято галочкой: день был, а записи по нему не нужно.
        public var isExcluded: Bool = false
    }

    public enum Line: Equatable {
        case moment(Moment)
        case period(Period)
        /// Разобрать не вышло. Текст возвращается как есть — человеку.
        case notUnderstood(String)
    }

    // MARK: Разбор

    /// Разобрать текст целиком. Каждая непустая строка — отдельная запись.
    public static func parse(_ text: String, today: Date = Date()) -> [Line] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line(from: $0, today: today) }
    }

    static func line(from raw: String, today: Date) -> Line {
        let text = raw.lowercased()
        guard let kind = kind(in: text) else { return .notUnderstood(raw) }

        if let (from, to) = range(in: text, today: today) {
            return .period(Period(kind: kind, from: from, to: to,
                                  timesPerDay: timesPerDay(in: text),
                                  durationSeconds: duration(in: text)))
        }
        guard let at = day(in: text, today: today) else { return .notUnderstood(raw) }
        return .moment(Moment(kind: kind, at: at,
                              grams: grams(in: text),
                              stool: stool(in: text),
                              times: timesPerDay(in: text)))
    }

    // MARK: Вид записи

    /// Слова подобраны по тому, как пишут в переписке, а не по названиям
    /// в интерфейсе: «был понос», а не «стул, форма: лужа».
    static let words: [(LogKind, [String])] = [
        (.stool,  ["понос", "стул", "какал", "покакал", "диаре"]),
        (.meal,   ["кормил", "корми", "поел", "ел ", "еда", "покормил"]),
        (.dose,   ["таблет", "дал", "дали", "доза", "препарат", "лекарств"]),
        (.walk,   ["гулял", "гуляли", "прогул", "выгул"]),
        (.outing, ["выходил", "выходили", "пописал", "по делам"]),
        (.incident, ["рвот", "вырвал", "тошнил", "лужа"]),
        (.weight, ["весит", "взвесил", "вес "]),
    ]

    static func kind(in text: String) -> LogKind? {
        // Порядок важен: «понос» встречается раньше «дал», и строка
        // «13.09 дали таблетку, был понос» — про две разные вещи.
        // Пока берём первую найденную и честно признаём ограничение:
        // две записи в одной строке не разбираются.
        for (kind, stems) in words where stems.contains(where: text.contains) {
            return kind
        }
        return nil
    }

    // MARK: Даты

    static let dayMonth = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})[.\/](\d{1,2})(?:[.\/](\d{2,4}))?\b"#
    )

    /// Одна дата: «13.09.26», «13.09», «вчера», «сегодня», «позавчера».
    static func day(in text: String, today: Date) -> Date? {
        let calendar = Calendar.current
        if text.contains("позавчера") {
            return calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))
        }
        if text.contains("вчера") {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
        }
        if text.contains("сегодня") { return calendar.startOfDay(for: today) }
        return dates(in: text, today: today).first
    }

    /// Диапазон «с 04.09 по 20.09». Нужны обе даты и слово-связка:
    /// две даты подряд без «с … по» — это две записи, а не период.
    static func range(in text: String, today: Date) -> (Date, Date)? {
        guard text.contains(" с ") || text.hasPrefix("с ") else { return nil }
        guard text.contains(" по ") || text.contains("–") || text.contains("—")
                || text.contains(" до ") else { return nil }
        let found = dates(in: text, today: today)
        guard found.count >= 2 else { return nil }
        let sorted = found.sorted()
        return (sorted.first!, sorted.last!)
    }

    static func dates(in text: String, today: Date) -> [Date] {
        guard let dayMonth else { return [] }
        let calendar = Calendar.current
        let ns = text as NSString
        return dayMonth.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> Date? in
                func part(_ i: Int) -> Int? {
                    guard match.range(at: i).location != NSNotFound else { return nil }
                    return Int(ns.substring(with: match.range(at: i)))
                }
                guard let d = part(1), let m = part(2), (1...31).contains(d), (1...12).contains(m)
                else { return nil }
                var year = calendar.component(.year, from: today)
                if let y = part(3) { year = y < 100 ? 2000 + y : y }
                var components = DateComponents()
                components.year = year; components.month = m; components.day = d
                guard let date = calendar.date(from: components) else { return nil }
                // Дата без года, оказавшаяся в будущем, — это прошлый год:
                // «31.12» в январе значит прошлый декабрь, а не следующий.
                if part(3) == nil, date > today {
                    return calendar.date(byAdding: .year, value: -1, to: date)
                }
                return date
            }
    }

    // MARK: Количества

    static func number(in text: String, after unit: [String]) -> Int? {
        for u in unit {
            guard let r = text.range(of: #"(\d+)\s*"# + u, options: .regularExpression) else { continue }
            let digits = text[r].prefix { $0.isNumber || $0 == " " }
            if let n = Int(digits.trimmingCharacters(in: .whitespaces)) { return n }
        }
        return nil
    }

    static func grams(in text: String) -> Int? { number(in: text, after: ["г\\b", "грамм"]) }

    static func timesPerDay(in text: String) -> Int? { number(in: text, after: ["раз"]) }

    static func duration(in text: String) -> Int? {
        if let hours = number(in: text, after: ["час"]) { return hours * 3600 }
        if let minutes = number(in: text, after: ["мин"]) { return minutes * 60 }
        return nil
    }

    // MARK: Стул

    static func stool(in text: String) -> StoolForm? {
        if text.contains("понос") || text.contains("диаре") || text.contains("жидк") { return .liquid }
        if text.contains("кашиц") { return .mushy }
        if text.contains("мягк") { return .soft }
        if text.contains("твёрд") || text.contains("тверд") { return .hard }
        if text.contains("колбаск") || text.contains("норм") { return .sausage }
        return nil
    }
}
