import Foundation

/// Что взять и о чём напомнить, когда собака едет с человеком.
nonisolated enum DayOutPlan {
    /// Как часто предлагать воду.
    ///
    /// Дома миска стоит всегда, и собака пьёт когда хочет. В разъездах
    /// воды нет, и она терпит молча — поэтому напоминание про воду тут
    /// нужно, а дома было бы шумом. Два часа — не медицинская норма,
    /// а частота, при которой не забываешь и не задалбываешься.
    static let waterEvery: TimeInterval = 2 * 3600

    /// Сколько корма взять на такой день.
    ///
    /// Считаем по кормлениям, которые попадут в окно, а не «норму, делённую
    /// на часы»: собака ест порциями, и половину порции с собой не берут.
    /// Плюс одна запасная — задержались, застряли, поехали дальше.
    struct Packing: Equatable, Sendable {
        var meals: Int
        var grams: Int
        var spareGrams: Int

        var totalGrams: Int { grams + spareGrams }
    }

    static func packing(for dog: Dog, hours: Int, from start: Date = Date(),
                        calendar: Calendar = .current) -> Packing {
        let window = start...start.addingTimeInterval(Double(hours) * 3600)
        let startOfDay = calendar.startOfDay(for: start)

        // Кормления берём из расписания собаки: приложение уже знает,
        // во сколько она ест, и выдумывать второй раз незачем.
        var meals = 0
        for minute in dog.mealTimes.sorted() {
            // И сегодня, и завтра: длинный день переваливает за полночь.
            for dayOffset in 0...1 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
                // Через `Calendar.date(minuteOfDay:on:)` (`DayTime.swift:20`),
                // а не сложением секунд: в сутки перевода часов начало дня
                // плюс 450 минут даёт не 07:30, и кормление у края окна
                // то теряется, то считается дважды — то есть корма берут
                // на порцию меньше или больше.
                let at = calendar.date(minuteOfDay: minute, on: day)
                if window.contains(at) { meals += 1 }
            }
        }

        let serving = dog.servingGrams
        return Packing(meals: meals,
                       grams: meals * serving,
                       // Запас — одна порция. Не «на всякий случай побольше»:
                       // лишний корм в рюкзаке съедается собакой при первой
                       // же возможности.
                       spareGrams: serving)
    }

    /// Когда в следующий раз предложить воду.
    static func nextWater(after last: Date?, start: Date, now: Date = Date()) -> Date {
        (last ?? start).addingTimeInterval(waterEvery)
    }

    /// Что сказать про завтра.
    ///
    /// Не предписание, а предупреждение: собака после долгого дня
    /// отсыпается, и хозяин, не связав одно с другим, идёт к врачу
    /// с «она весь день спит».
    static func restAdvice(hours: Double) -> String? {
        switch hours {
        case ..<DayOut.longDayHours:
            return nil
        case ..<10:
            return String(localized: "День был долгий. Завтра ей, скорее всего, захочется отсыпаться — это нормально и не повод для тревоги. Прогулки лучше короткие и спокойные.")
        default:
            return String(localized: "Очень долгий день. Завтра стоит разгрузить: короткие выходы, без занятий и гостей. Если послезавтра она всё ещё вялая или не ест — это уже к врачу.")
        }
    }
}

/// След долгих дней в дневнике.
///
/// Просьба была такая: находить, если после подобных дней собака потом
/// «диареит, много спит или не ест». Приложение не ставит диагнозов
/// и не утверждает причинность — оно показывает совпадение и оставляет
/// вывод человеку. Этого достаточно, чтобы прийти к врачу не с «ей плохо»,
/// а с «после долгих дней у неё вот что».
nonisolated struct DayOutTrace: Equatable, Sendable {
    /// Сколько долгих дней попало в наблюдение.
    var longDays: Int
    /// Из них — после скольких на следующий день был жидкий стул.
    var followedByLooseStool: Int
    /// После скольких собака съела заметно меньше нормы.
    var followedByPoorAppetite: Int
    /// После скольких был инцидент.
    var followedByIncident: Int

    static let empty = DayOutTrace(longDays: 0, followedByLooseStool: 0,
                                   followedByPoorAppetite: 0, followedByIncident: 0)

    /// Ниже этого о совпадениях говорить нельзя: два случая — это не картина.
    static let minimumDays = 3

    var isReliable: Bool { longDays >= Self.minimumDays }

    /// Что из этого стоит сказать вслух.
    var findings: [String] {
        guard isReliable else { return [] }
        var lines: [String] = []
        if followedByLooseStool * 2 >= longDays {
            lines.append("После долгих дней стул на следующий день бывал жиже — \(Fmt.times(followedByLooseStool)) из \(longDays).")
        }
        if followedByPoorAppetite * 2 >= longDays {
            lines.append("После долгих дней она ела заметно меньше обычного — \(Fmt.times(followedByPoorAppetite)) из \(longDays).")
        }
        if followedByIncident * 2 >= longDays {
            lines.append("После долгих дней случались инциденты — \(Fmt.times(followedByIncident)) из \(longDays).")
        }
        return lines
    }
}

nonisolated enum DayOutAnalyzer {
    /// Насколько меньше нормы — это «заметно меньше».
    static let appetiteDrop = 0.7

    static func trace(
        daysOut: [DayOut],
        events: [LogEvent],
        norm: Int,
        calendar: Calendar = .current
    ) -> DayOutTrace {
        let long = daysOut.filter { $0.endedAt != nil && $0.wasLong() }
        guard !long.isEmpty else { return .empty }

        // Записи РАЗ ЛОЖАТСЯ ПО ДНЯМ, а не фильтруются на каждый день.
        //
        // Прежде здесь стояло `active.filter { calendar.isDate(…) }`
        // ВНУТРИ цикла по длинным дням: проход по всему дневнику
        // столько раз, сколько таких дней, и каждое сравнение —
        // `Calendar.isDate(_:inSameDayAs:)`, одна из самых дорогих
        // операций Foundation.
        //
        // Та же форма, что чинили в календаре истории 28.10.2026:
        // цена росла от ПРОИЗВЕДЕНИЯ дней на записи. Зовётся это
        // из тела экрана «История» (`HistoryScreen:266`), то есть
        // на каждую перерисовку.
        let поДням = Diary.поДням(events, calendar: calendar)
        var trace = DayOutTrace(longDays: long.count, followedByLooseStool: 0,
                                followedByPoorAppetite: 0, followedByIncident: 0)

        for day in long {
            guard let next = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: day.startedAt)) else { continue }
            let ofDay = поДням[calendar.startOfDay(for: next)] ?? []
            guard !ofDay.isEmpty else { continue }   // день без записей ничего не говорит

            if ofDay.contains(where: { ($0.stoolForm?.bristolScore ?? 0) >= 6 }) {
                trace.followedByLooseStool += 1
            }
            if norm > 0 {
                let eaten = ofDay.filter { $0.kind == .meal }.compactMap(\.grams).reduce(0, +)
                if eaten > 0, Double(eaten) < Double(norm) * appetiteDrop {
                    trace.followedByPoorAppetite += 1
                }
            }
            if ofDay.contains(where: { $0.kind == .incident }) {
                trace.followedByIncident += 1
            }
        }
        return trace
    }
}
