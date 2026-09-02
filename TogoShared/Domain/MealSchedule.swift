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

// MARK: - Что из плана уже сделано

extension MealSchedule {
    /// Насколько запись может отстоять от запланированного времени
    /// и всё ещё считаться этим кормлением. Полтора часа — это «покормила
    /// не по будильнику, а когда встала».
    nonisolated static let doneTolerance = 90 * 60.0

    /// Разметить пункты плана: какие из них закрыты записями.
    ///
    /// Раньше каждый пункт спрашивал независимо: «есть ли хоть одна запись
    /// в пределах полутора часов». У щенка с пятью кормлениями пункты стоят
    /// в трёх с половиной часах друг от друга, но стоит расставить времена
    /// вручную поближе — и одна запись закрывала сразу два пункта. День
    /// выглядел выполненным, хотя собаку покормили один раз.
    ///
    /// Теперь каждая запись закрывает ровно один пункт — ближайший
    /// к себе и ещё свободный.
    nonisolated static func matchDone(
        planned: [Int],
        logged: [Date],
        startOfDay: Date
    ) -> [Bool] {
        var done = [Bool](repeating: false, count: planned.count)
        let calendar = Calendar.current
        let slots = planned.map { calendar.date(minuteOfDay: $0, on: startOfDay) }

        // Сначала самые «уверенные» пары: у кого расстояние меньше, тот
        // и занимает пункт. Иначе первая по времени запись могла бы забрать
        // пункт, который куда точнее подходит следующей.
        var pairs: [(distance: Double, slot: Int, record: Int)] = []
        for (recordIndex, date) in logged.enumerated() {
            for (slotIndex, slot) in slots.enumerated() {
                let distance = abs(date.timeIntervalSince(slot))
                guard distance <= doneTolerance else { continue }
                pairs.append((distance, slotIndex, recordIndex))
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var usedRecords = Set<Int>()
        for pair in pairs where !done[pair.slot] && !usedRecords.contains(pair.record) {
            done[pair.slot] = true
            usedRecords.insert(pair.record)
        }
        return done
    }
}
