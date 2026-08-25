import Foundation

/// Как разложить кормления по суткам.
///
/// Считаем не «внутри дня», а по кругу в 24 часа: ночь — это тоже промежуток
/// между кормлениями, и для собаки он часто самый длинный. Слишком долгий
/// ночной перерыв — известная причина утренней рвоты желчью, поэтому
/// приложение старается его сократить и показывает, что получилось.
///
/// Правила:
/// * первое кормление — вскоре после подъёма, но после первого выхода:
///   собака сначала идёт в туалет, потом ест;
/// * дальше — ровно через 24 ч ÷ число кормлений, чтобы промежутки были
///   одинаковыми и днём, и ночью;
/// * последнее не позже чем за полтора часа до сна — нужно успеть погулять;
/// * если идеальный шаг в это окно не влезает, кормления сжимаются
///   и раскладываются поровну между первым и последним.
nonisolated enum MealSchedule {
    static let minutesInDay = 24 * 60
    /// Сколько ждать после подъёма до первого кормления.
    static let afterWake = 30
    /// За сколько до сна должно пройти последнее кормление.
    static let beforeSleep = 90
    /// Дольше этого ночной перерыв стоит обсудить с врачом.
    static let longNightThreshold = 14 * 60

    /// Итог раскладки: времена и то, что о них стоит знать человеку.
    struct Plan: Equatable, Sendable {
        var times: [Int]
        /// Промежуток между дневными кормлениями.
        var dayInterval: Int?
        /// От последнего кормления до первого следующего дня.
        var nightGap: Int
        /// Идеальный шаг не влез в окно бодрствования — пришлось сжать.
        var isCompressed: Bool

        var hasLongNight: Bool { nightGap > MealSchedule.longNightThreshold }

        /// Насколько ночь длиннее дневного промежутка.
        var nightOverhang: Int? {
            guard let dayInterval else { return nil }
            return max(0, nightGap - dayInterval)
        }
    }

    static func plan(mealsPerDay: Int, wake: Int, sleep: Int) -> Plan {
        let times = evenTimes(mealsPerDay: mealsPerDay, wake: wake, sleep: sleep)
        return Plan(
            times: times,
            dayInterval: dayInterval(times),
            nightGap: nightGap(times),
            isCompressed: isCompressed(mealsPerDay: mealsPerDay, wake: wake, sleep: sleep)
        )
    }

    /// Времена кормлений. Первое привязано к подъёму, дальше — ровный шаг
    /// по кругу суток, сжатый при необходимости в окно бодрствования.
    static func evenTimes(mealsPerDay: Int, wake: Int, sleep: Int) -> [Int] {
        guard mealsPerDay > 0 else { return [] }

        let first = normalize(wake + afterWake)
        guard mealsPerDay > 1 else { return [first] }

        let latest = latestMeal(wake: wake, sleep: sleep)
        let window = forward(from: first, to: latest)
        let idealStep = minutesInDay / mealsPerDay
        let idealSpan = idealStep * (mealsPerDay - 1)

        // Ровный шаг по суткам умещается в бодрствование — берём его:
        // одинаковые промежутки днём и ночью лучше всего.
        if idealSpan <= window {
            return (0..<mealsPerDay).map { normalize(first + idealStep * $0) }
        }

        // Не умещается — раскладываем поровну между первым и последним.
        let step = window / (mealsPerDay - 1)
        return (0..<mealsPerDay).map { normalize(first + step * $0) }
    }

    static func isCompressed(mealsPerDay: Int, wake: Int, sleep: Int) -> Bool {
        guard mealsPerDay > 1 else { return false }
        let window = forward(from: normalize(wake + afterWake), to: latestMeal(wake: wake, sleep: sleep))
        return (minutesInDay / mealsPerDay) * (mealsPerDay - 1) > window
    }

    /// Ночной перерыв: от последнего кормления до первого на следующий день.
    static func nightGap(_ times: [Int]) -> Int {
        guard let first = times.first, let last = times.last, times.count > 0 else { return 0 }
        guard times.count > 1 else { return minutesInDay }
        return forward(from: last, to: first)
    }

    /// Дневной промежуток. Если они разные — берём самый короткий:
    /// именно он показывает, насколько ночь выбивается из ритма.
    static func dayInterval(_ times: [Int]) -> Int? {
        guard times.count > 1 else { return nil }
        let gaps = zip(times, times.dropFirst()).map { forward(from: $0, to: $1) }
        return gaps.min()
    }

    // MARK: Мелочи

    static func latestMeal(wake: Int, sleep: Int) -> Int {
        let awake = forward(from: wake, to: sleep)
        // Окно короче трёх часов — не режим, а опечатка: оставляем хотя бы час.
        let span = max(60, awake - beforeSleep)
        return normalize(wake + span)
    }

    static func normalize(_ minute: Int) -> Int {
        ((minute % minutesInDay) + minutesInDay) % minutesInDay
    }

    /// Сколько минут вперёд по кругу суток от одного времени до другого.
    static func forward(from: Int, to: Int) -> Int {
        let delta = normalize(to) - normalize(from)
        return delta > 0 ? delta : delta + minutesInDay
    }
}
