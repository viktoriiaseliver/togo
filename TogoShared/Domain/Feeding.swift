import Foundation

/// Питание: сколько, сколько раз и во сколько.
///
/// Приложение не ставит целей по проценту и не считает норму само —
/// норму называет врач, она лежит в профиле как порция × число кормлений.
/// Здесь считается только одно: расходится ли то, что записано, с этой нормой,
/// и во сколько собака ест на самом деле.
nonisolated struct FeedingReport: Equatable, Sendable {
    /// Один день: сколько съел и во сколько.
    struct Day: Equatable, Sendable, Identifiable {
        var date: Date
        var grams: Int
        /// Минуты от полуночи по каждому кормлению.
        var mealMinutes: [Int]
        var isComplete: Bool

        var id: Date { date }
        var meals: Int { mealMinutes.count }
    }

    enum Status: Equatable, Sendable {
        /// Меньше трёх полных дней — выводов не делаем и говорим об этом прямо.
        case notEnoughData(days: Int)
        case underNorm
        case onNorm
        case overNorm

        var title: String {
            switch self {
            case .notEnoughData: String(localized: "Пока не с чем сравнивать")
            case .underNorm: String(localized: "Ест меньше нормы")
            case .onNorm: String(localized: "Ест по норме")
            case .overNorm: String(localized: "Ест больше нормы")
            }
        }
    }

    var days: [Day]
    var normGramsPerDay: Int
    var normMealsPerDay: Int
    var averageGramsPerDay: Double
    var averageMealsPerDay: Double
    var status: Status
    /// Во сколько он ест на самом деле — по наблюдениям, а не по расписанию.
    var observedMealTimes: [Int]
    /// Что предложить, если расходится с нормой.
    ///
    /// Отдельной подсказки по порции здесь нет намеренно. Она была,
    /// и предлагала «норму, делённую на кормления» — то есть ровно ту
    /// порцию, которая и так стоит в профиле. Появиться такая подсказка
    /// могла только после того, как порцию рассогласовали с нормой руками,
    /// и предлагала отменить только что сделанное.
    var suggestedMealTimes: [Int]
    /// Сколько в среднем проходит от еды до стула — из этого и растут выходы.
    var stoolLagMinutes: Int?
    var suggestedOutingTimes: [Int]
    /// Предложенное время попало в окно натощак — показываем конфликт явно.
    var conflicts: [String]

    static let empty = FeedingReport(
        days: [], normGramsPerDay: 0, normMealsPerDay: 0,
        averageGramsPerDay: 0, averageMealsPerDay: 0,
        status: .notEnoughData(days: 0), observedMealTimes: [],
        suggestedMealTimes: [],
        stoolLagMinutes: nil, suggestedOutingTimes: [], conflicts: []
    )

    var todayGrams: Int { days.last?.grams ?? 0 }
    var todayMeals: Int { days.last?.meals ?? 0 }
    var remainingGramsToday: Int { max(0, normGramsPerDay - todayGrams) }

    /// На сколько процентов расходится с нормой. Отрицательное — недоедает.
    var deviationPercent: Int {
        guard normGramsPerDay > 0, averageGramsPerDay > 0 else { return 0 }
        return Int(((averageGramsPerDay / Double(normGramsPerDay)) - 1) * 100)
    }
}

nonisolated enum FeedingAnalyzer {
    /// Сколько дней смотрим назад. Две недели — достаточно, чтобы увидеть
    /// режим, и мало, чтобы не тащить прошлые схемы кормления.
    static let windowDays = 14
    /// Три полных дня — минимум, ниже которого выводы врут.
    static let minimumCompleteDays = 3
    /// Порог, ниже которого расхождение не стоит внимания человека.
    static let tolerance = 0.05

    static func report(
        events: [LogEvent],
        dog: Dog?,
        now: Date = Date(),
        calendar: Calendar = .current,
        fastingWindows: [(start: Int, end: Int)] = []
    ) -> FeedingReport {
        let norm = dog?.dailyGrams ?? 0
        let normMeals = dog?.mealsPerDay ?? 0
        let days = dailyIntake(events: events, now: now, calendar: calendar)
        let complete = days.filter(\.isComplete)

        let averageGrams = complete.isEmpty ? 0
            : Double(complete.map(\.grams).reduce(0, +)) / Double(complete.count)
        let averageMeals = complete.isEmpty ? 0
            : Double(complete.map(\.meals).reduce(0, +)) / Double(complete.count)

        let status = self.status(completeDays: complete.count, average: averageGrams, norm: norm)
        let observed = mealTimeClusters(days: complete)
        let lag = mealToStoolLag(events: events)

        let suggestedTimes = suggestedMealTimes(
            observed: observed,
            normMeals: normMeals,
            days: complete,
            awakeWindow: dog.map { (wake: $0.wakeMinuteOfDay, sleep: $0.sleepMinuteOfDay) },
            calendar: calendar
        )

        return FeedingReport(
            days: days,
            normGramsPerDay: norm,
            normMealsPerDay: normMeals,
            averageGramsPerDay: averageGrams,
            averageMealsPerDay: averageMeals,
            status: status,
            observedMealTimes: observed,
            suggestedMealTimes: suggestedTimes,
            stoolLagMinutes: lag,
            suggestedOutingTimes: suggestedOutingTimes(mealTimes: suggestedTimes, lag: lag, days: complete),
            conflicts: conflicts(mealTimes: suggestedTimes, fastingWindows: fastingWindows)
        )
    }

    // MARK: По дням

    static func dailyIntake(
        events: [LogEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FeedingReport.Day] {
        // Граммы и кормления считаются по-разному, и это важно.
        //
        // Лакомство из порции — та же еда, в граммы оно обязано попасть:
        // иначе «ест меньше нормы» вылезет у всех, кто занимается
        // с собакой. Но кормлением оно не является. Пока лакомства шли
        // в общую кучу, горсть корма на занятии в 15:40 становилась
        // третьим кормлением: приложение считало, что собака ест три раза,
        // и предлагало под это расписание.
        let active = Diary.active(events)
        let meals = active.filter { $0.kind == .meal }
        let extras = active.filter { $0.kind == .treat && $0.fromPortion }
        let today = calendar.startOfDay(for: now)

        return (0..<windowDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let mealsOfDay = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let extrasOfDay = extras.filter { calendar.isDate($0.date, inSameDayAs: day) }
            // Пустые прошлые дни — это не «съел ноль», а «дневник не вели».
            // Такие дни в среднее не попадают.
            let isToday = offset == 0
            let hasAnything = !mealsOfDay.isEmpty || !extrasOfDay.isEmpty
            guard hasAnything || isToday else { return nil }
            return FeedingReport.Day(
                date: day,
                grams: (mealsOfDay + extrasOfDay).compactMap(\.grams).reduce(0, +),
                mealMinutes: mealsOfDay.map { minuteOfDay($0.date, calendar: calendar) }.sorted(),
                isComplete: !isToday && hasAnything
            )
        }
    }

    static func status(completeDays: Int, average: Double, norm: Int) -> FeedingReport.Status {
        guard completeDays >= minimumCompleteDays, norm > 0 else {
            return .notEnoughData(days: completeDays)
        }
        let ratio = average / Double(norm)
        if ratio > 1 + tolerance { return .overNorm }
        if ratio < 1 - tolerance * 2 { return .underNorm }
        return .onNorm
    }

    // MARK: Во сколько ест на самом деле

    /// Одномерная кластеризация времён: соседние кормления в пределах
    /// полутора часов — это одно и то же кормление в разные дни.
    static func mealTimeClusters(days: [FeedingReport.Day], gapMinutes: Int = 90) -> [Int] {
        let times = days.flatMap(\.mealMinutes).sorted()
        guard !times.isEmpty else { return [] }

        var clusters: [[Int]] = [[times[0]]]
        for time in times.dropFirst() {
            if time - (clusters[clusters.count - 1].last ?? time) <= gapMinutes {
                clusters[clusters.count - 1].append(time)
            } else {
                clusters.append([time])
            }
        }

        // Кластер считается настоящим кормлением, если он есть хотя бы
        // в трети дней: разовый ночной перекус расписанием не становится.
        let threshold = max(1, days.count / 3)
        return clusters
            .filter { $0.count >= threshold }
            .map { median($0) }
            .sorted()
    }

    // MARK: Что предложить

    /// Кормления раскладываются по дню равномерно внутри бодрствования,
    /// но отталкиваются от того, во сколько собака уже ест.
    static func suggestedMealTimes(
        observed: [Int],
        normMeals: Int,
        days: [FeedingReport.Day],
        awakeWindow: (wake: Int, sleep: Int)? = nil,
        calendar: Calendar = .current
    ) -> [Int] {
        guard normMeals > 0 else { return [] }
        // Если человек уже кормит столько раз, сколько собирался, — его
        // расписание и есть правильное. Ломать сложившийся ритм незачем.
        if observed.count == normMeals { return observed }

        // Иначе раскладываем по суткам целиком: ночь — тоже промежуток
        // между кормлениями, и её тоже надо учитывать.
        if let awakeWindow {
            return MealSchedule.evenTimes(mealsPerDay: normMeals,
                                          wake: awakeWindow.wake,
                                          sleep: awakeWindow.sleep)
        }

        let first = observed.first ?? 7 * 60 + 30
        let last = observed.last ?? 18 * 60 + 30

        guard normMeals > 1 else { return [first % (24 * 60)] }
        let step = max(60, last - first) / (normMeals - 1)
        return (0..<normMeals).map { (first + step * $0) % (24 * 60) }
    }

    // MARK: Еда → стул → выходы

    /// Сколько в среднем проходит от кормления до стула. Из этого числа
    /// и получаются осмысленные времена выходов.
    static func mealToStoolLag(events: [LogEvent], maxLagHours: Double = 8) -> Int? {
        let active = Diary.active(events)
        let meals = active.filter { $0.kind == .meal }.map(\.date).sorted()
        let stools = active
            .filter { $0.kind == .stool || ($0.kind == .outing && ($0.outcome == .stool || $0.outcome == .both)) }
            .map(\.date)
            .sorted()
        guard !meals.isEmpty, !stools.isEmpty else { return nil }

        // Оба массива отсортированы, поэтому идём по ним одним проходом.
        // Поиск `meals.last(where:)` внутри цикла давал квадрат: на годе
        // записей это десятки тысяч сравнений на каждую перерисовку.
        var lags: [Int] = []
        var mealIndex = 0
        for stool in stools {
            while mealIndex + 1 < meals.count, meals[mealIndex + 1] < stool {
                mealIndex += 1
            }
            guard mealIndex < meals.count, meals[mealIndex] < stool else { continue }
            let lag = stool.timeIntervalSince(meals[mealIndex])
            if lag <= maxLagHours * 3600 { lags.append(Int(lag / 60)) }
        }
        guard lags.count >= 3 else { return nil }
        return median(lags)
    }

    /// Выходы предлагаются двумя источниками: через задержку после каждого
    /// кормления и утром сразу после подъёма.
    static func suggestedOutingTimes(mealTimes: [Int], lag: Int?, days: [FeedingReport.Day]) -> [Int] {
        guard let lag, let firstMeal = mealTimes.first else { return [] }
        var times = [max(0, firstMeal - 30)]                 // утренний, до еды
        times += mealTimes.map { ($0 + lag) % (24 * 60) }    // после каждого кормления
        return Array(Set(times)).sorted()
    }

    // MARK: Конфликты с лечением

    /// Стич — сложный случай: лечение даёт окна натощак, и предложенное
    /// кормление может попасть внутрь окна. Такое надо показывать явно,
    /// а не молча двигать: двигать должен человек вместе с врачом.
    static func conflicts(mealTimes: [Int], fastingWindows: [(start: Int, end: Int)]) -> [String] {
        var result: [String] = []
        for time in mealTimes {
            for window in fastingWindows where isInside(time, window) {
                result.append(
                    "Кормление в \(Fmt.clock(minuteOfDay: time)) попадает в окно натощак "
                    + "\(Fmt.clock(minuteOfDay: window.start))–\(Fmt.clock(minuteOfDay: window.end))"
                )
            }
        }
        return result
    }

    private static func isInside(_ minute: Int, _ window: (start: Int, end: Int)) -> Bool {
        window.start <= window.end
            ? (minute >= window.start && minute < window.end)
            : (minute >= window.start || minute < window.end)
    }

    // MARK: Мелочи

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}
