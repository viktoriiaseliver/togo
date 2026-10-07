import Foundation

/// Исходы вердикта «просится». Во всех кнопка «Вывожу» — первая:
/// вердикт не блокирует выход и не знает лучше человека.
///
/// **Пять случаев, шесть разных объяснений:** у `.unknown` три причины,
/// и `VerdictEngine.explanation` различает все три, хотя `title`
/// сводит их к одному «Непонятно», а `badge` — к двум строкам.
///
/// Здесь было написано «четыре исхода». 07.10.2026 посчитано —
/// неверно; `.episode` и `.silence` приехали позже, а число осталось.
/// Та же строка стояла и в `NeedsSheet.swift`, то есть **устаревшее
/// утверждение размножилось по двум файлам** и читалось вместо кода.
/// Поэтому счёт здесь привязан к устройству типа, а не к числу:
/// «у `.unknown` три причины» проверяется глазами по соседним строкам,
/// «четыре исхода» не проверяется ничем.
nonisolated enum NeedVerdict: Equatable, Sendable {
    /// Дольше, чем он когда-либо терпел.
    case urgent
    /// Дольше, чем обычно.
    case likelyNeed
    /// Данных мало или картина неоднозначная — и это написано прямо.
    case unknown(reason: UnknownReason)
    /// Вышли недавно, и он сходил.
    case probablyAttention
    /// Эпизод активен — вердикт не считается вовсе.
    case episode

    enum UnknownReason: Equatable, Sendable {
        case notEnoughData(days: Int)
        case ambiguous
        /// Про мочу молчат дольше суток, и про выходы молчат тоже.
        /// Считать тут нечего — правило и повод в `UrineSilence`.
        case silence(since: Date)
    }

    var badge: String {
        switch self {
        case .urgent: String(localized: "срочно")
        case .likelyNeed: String(localized: "похоже на нужду")
        // Тишину нельзя объявлять «неясной картиной»: картины нет вовсе.
        case .unknown(.silence): String(localized: "отметок мочи нет")
        case .unknown: String(localized: "неясно")
        case .probablyAttention: String(localized: "не похоже · выход всё равно доступен")
        case .episode: String(localized: "эпизод")
        }
    }

    var title: String {
        switch self {
        case .urgent: String(localized: "Выведи сейчас")
        case .likelyNeed: String(localized: "Выведи")
        case .unknown: String(localized: "Непонятно")
        case .probablyAttention: String(localized: "Скорее внимания")
        case .episode: String(localized: "Выводи по первому знаку")
        }
    }

    /// Вторая кнопка. Первая всегда «Вывожу».
    var alternativeAction: String {
        switch self {
        case .urgent, .likelyNeed: String(localized: "Не сейчас")
        case .unknown: String(localized: "Играем, не пойдём")
        case .probablyAttention: String(localized: "Поиграю с ним")
        case .episode: String(localized: "Не сейчас")
        }
    }
}

/// Срез фактов, из которых считается вердикт. Отдельная структура,
/// чтобы логику можно было проверить тестами без базы.
nonisolated struct NeedSignals: Sendable {
    var now: Date
    var lastUrine: Date?
    var lastStool: Date?
    var lastMeal: Date?
    var lastWalk: Date?
    /// Интервалы между мочеиспусканиями за всю историю, в секундах.
    var urineIntervals: [TimeInterval]
    var daysOfData: Int
    var episodeActive: Bool
    /// Последний выход закончился результатом.
    var lastOutingHadResult: Bool
    /// Когда последний раз отмечали выход — **любой**, с результатом
    /// и без. Это и есть разделитель тишины: отсюда видно, ведут ли
    /// дневник вообще. Отличается от `lastWalk`: прогулка и выход
    /// у Togo разные события, а мочу приносит выход.
    var lastOutingAt: Date?

    init(
        now: Date = Date(),
        lastUrine: Date? = nil,
        lastStool: Date? = nil,
        lastMeal: Date? = nil,
        lastWalk: Date? = nil,
        urineIntervals: [TimeInterval] = [],
        daysOfData: Int = 0,
        episodeActive: Bool = false,
        lastOutingHadResult: Bool = false,
        lastOutingAt: Date? = nil
    ) {
        self.now = now
        self.lastUrine = lastUrine
        self.lastStool = lastStool
        self.lastMeal = lastMeal
        self.lastWalk = lastWalk
        self.urineIntervals = urineIntervals
        self.daysOfData = daysOfData
        self.episodeActive = episodeActive
        self.lastOutingHadResult = lastOutingHadResult
        self.lastOutingAt = lastOutingAt
    }

    var sinceUrine: TimeInterval? { lastUrine.map { now.timeIntervalSince($0) } }

    /// Дата, с которой про мочу нечего сказать. Живёт здесь, а не во вью:
    /// величину читают три поверхности (лист вердикта, виджет, локскрин),
    /// и своя арифметика в каждой — уже случившийся у Togo дефект.
    var urineSilence: Date? {
        UrineSilence.start(now: now, lastUrineAt: lastUrine, lastOutingAt: lastOutingAt)
    }

    var typicalUrineInterval: TimeInterval? {
        guard !urineIntervals.isEmpty else { return nil }
        let sorted = urineIntervals.sorted()
        return sorted[sorted.count / 2]
    }

    var longestUrineInterval: TimeInterval? { urineIntervals.max() }
}

nonisolated enum VerdictEngine {
    /// Меньше четырёх дней данных — всегда «непонятно».
    static let minimumDaysOfData = 4
    /// Дольше обычного, но не рекорд.
    static let likelyNeedFactor = 1.15
    /// Только что вышли и он сходил.
    static let recentFactor = 0.35

    static func evaluate(_ s: NeedSignals) -> NeedVerdict {
        // Эпизод активен — вердикты гасим, вместо них «выводи по первому знаку».
        if s.episodeActive { return .episode }

        guard s.daysOfData >= minimumDaysOfData else {
            return .unknown(reason: .notEnoughData(days: max(1, s.daysOfData)))
        }

        // Тишина проверяется ДО интервалов нарочно. Стой она ниже —
        // пара «моча 434 ч назад, медиана 6 ч» уходила бы в `.urgent`
        // через `since > longest`, то есть приложение объявляло бы
        // «дольше, чем он когда-либо терпел» из того, что дневник
        // забросили. И выше `guard` про `typical` — иначе дневник
        // без истории интервалов отвечал бы «картина неоднозначная»
        // там, где картины нет вовсе.
        if let тишина = s.urineSilence {
            return .unknown(reason: .silence(since: тишина))
        }

        guard let since = s.sinceUrine, let typical = s.typicalUrineInterval, typical > 0 else {
            return .unknown(reason: .ambiguous)
        }

        if let longest = s.longestUrineInterval, since > longest {
            return .urgent
        }
        if since > typical * likelyNeedFactor {
            return .likelyNeed
        }
        if since < typical * recentFactor, s.lastOutingHadResult {
            return .probablyAttention
        }
        return .unknown(reason: .ambiguous)
    }

    /// Строка фактов под вердиктом: ничего не надо вспоминать.
    static func factLine(_ s: NeedSignals) -> String {
        var parts: [String] = []
        if let stool = s.lastStool {
            let cal = Calendar.current
            parts.append(cal.isDateInToday(stool)
                ? String(localized: "стул сегодня \(Fmt.clock(stool))")
                : String(localized: "стул \(Fmt.shortDay(stool))"))
        } else {
            parts.append(String(localized: "стула ещё не было"))
        }
        // Еда и прогулка — через `FactAge`, а не голыми часами. До 05.10
        // здесь стояло `Fmt.duration` без потолка, и на заброшенном
        // дневнике строка печатала «ел 437 ч 19 мин назад» под вердиктом,
        // который строкой выше честно говорит «приложение не знает».
        // Разветвление у стула было, у этих двух — нет; это не решение
        // печатать часы, а пропуск, который выглядит как решение.
        if let meal = s.lastMeal {
            switch FactAge.answer(since: meal, now: s.now) {
            case .elapsed(let прошло):
                parts.append(String(localized: "ел \(Fmt.duration(прошло)) назад"))
            case .day(let день):
                parts.append(String(localized: "ел \(Fmt.shortDay(день))"))
            }
        }
        if let walk = s.lastWalk {
            switch FactAge.answer(since: walk, now: s.now) {
            case .elapsed(let прошло):
                parts.append(String(localized: "гулял \(Fmt.duration(прошло)) назад"))
            case .day(let день):
                parts.append(String(localized: "гулял \(Fmt.shortDay(день))"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Объяснение под заголовком — то, что человек читает вместо процента уверенности.
    static func explanation(_ verdict: NeedVerdict, _ s: NeedSignals) -> String {
        switch verdict {
        case .urgent:
            let since = s.sinceUrine.map(Fmt.duration) ?? String(localized: "долго")
            return String(localized: "Не писал \(since). Это дольше, чем он когда-либо терпел.")
        case .likelyNeed:
            let since = s.sinceUrine.map(Fmt.duration) ?? String(localized: "долго")
            return String(localized: "Не писал \(since) — дольше, чем обычно.")
        case .unknown(.notEnoughData(let days)):
            return String(localized: "Приложение пока не знает его интервалов. Выведи, если сомневаешься: записей всего за \(Fmt.days(days)) — это мало.")
        case .unknown(.silence(let since)):
            // Называем ровно измеренное — и вслух говорим, чего не знаем.
            // До 28.09 на этих же данных тут стояло «Не писал 434 ч. Это
            // дольше, чем он когда-либо терпел»: утверждение о собаке,
            // выведенное из отсутствия записи.
            //
            // **Дата стоит НЕ последней, и это не стиль.** 05.10 кадр
            // показал «нет отметок с 17 сент.. Приложение не знает…» —
            // две точки: `Fmt.shortDay` отдаёт сокращение месяца
            // со СВОЕЙ точкой, а шаблон ставил свою. Убрать точку
            // из шаблона нельзя: сокращение кончается точкой не во всех
            // языках, и починка русского сломала бы остальные молча.
            // Править `Fmt.shortDay` нельзя тем более — точка приходит
            // из локали вместе с сокращением и стоит там по праву.
            //
            // Поэтому вопрос «чем кончается подстановка» снят структурой:
            // посреди фразы точка сокращения служит сама собой, и решение
            // верно во всех языках разом, а не принимается в каждом
            // отдельно.
            return String(localized: "С \(Fmt.shortDay(since)) отметок мочи нет. Приложение не знает, писал он или просто никто не отметил.")
        case .unknown(.ambiguous):
            let since = s.sinceUrine.map(Fmt.duration) ?? String(localized: "недавно")
            return String(localized: "Писал \(since) назад. Может, скучно — а может, живот. Выведи, если сомневаешься: приложение не знает лучше тебя.")
        case .probablyAttention:
            let since = s.sinceUrine.map(Fmt.duration) ?? String(localized: "недавно")
            return String(localized: "Вышли \(since) назад, и он сходил. Всё равно можно вывести — запись ляжет в дневник, и в следующий раз вердикт будет точнее.")
        case .episode:
            return String(localized: "Идёт эпизод: два инцидента за сутки. Пока он не закончится, приложение не считает вердикты — выводи по первому знаку.")
        }
    }
}
