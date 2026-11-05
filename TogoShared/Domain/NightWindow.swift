import Foundation

/// Ночь, в которую собака в туалет не ходит.
///
/// **Просьба Виктории 29.10.2026: «просчитай, что собака ночью в туалет
/// не пойдёт, и следующий день обновиться не должен».** Ритм «обычно
/// выходите каждые 4 ч» мерился по часам на стене: последний туалет
/// в 22:30, ночь — и в 7 утра шкала «пора ли» стояла переполненной
/// вдвое, а «обычно до 02:30» обещало выход посреди сна. Собака спала,
/// приложение считало это терпением.
///
/// Ночь — это тихие часы из настроек (`Settings.quietHoursStart/End`,
/// по умолчанию 23–7): человек их уже назвал, второго вопроса «когда
/// он спит» не заводим.
///
/// > Само показание («9 ч назад») ночь НЕ вычитает: это факт о мире,
/// > и он верен. Вычитается только там, где число сравнивается с нормой.
nonisolated struct NightWindow: Sendable, Equatable {
    /// Часы начала и конца, 0…23. Равные — ночи нет.
    let startHour: Int
    let endHour: Int

    static let standard = NightWindow(startHour: 23, endHour: 7)

    /// Ночи, задевающие сутки `day` и соседние, по возрастанию.
    private func nights(around date: Date, calendar: Calendar) -> [(Date, Date)] {
        guard startHour != endHour else { return [] }
        let день = calendar.startOfDay(for: date)
        return (-1...1).compactMap { сдвиг -> (Date, Date)? in
            guard let d = calendar.date(byAdding: .day, value: сдвиг, to: день),
                  let начало = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: d)
            else { return nil }
            // Через полночь (23–7) конец — на следующие сутки.
            let деньКонца = startHour > endHour ? calendar.date(byAdding: .day, value: 1, to: d) : d
            guard let деньКонца,
                  let конец = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: деньКонца)
            else { return nil }
            return (начало, конец)
        }
    }

    /// Бодрствующее время между двумя моментами: ночь вычтена.
    func awake(from: Date, to: Date, calendar: Calendar = .current) -> TimeInterval {
        guard to > from else { return 0 }
        var ночью: TimeInterval = 0
        var день = calendar.startOfDay(for: from)
        var видели = Set<Date>()
        // Шагом по суткам: промежуток в неделю — семь ночей.
        while день <= to {
            for (начало, конец) in nights(around: день, calendar: calendar) where видели.insert(начало).inserted {
                let a = max(начало, from), b = min(конец, to)
                if b > a { ночью += b.timeIntervalSince(a) }
            }
            guard let следующий = calendar.date(byAdding: .day, value: 1, to: день) else { break }
            день = следующий
        }
        return max(0, to.timeIntervalSince(from) - ночью)
    }

    /// Момент, когда после `from` пройдёт `awake` бодрствующего времени.
    ///
    /// «Обычно до 02:30» при ночи 23–7 становится «обычно до 10:30»:
    /// те же четыре часа, только бодрствующих.
    func adding(awake: TimeInterval, to from: Date, calendar: Calendar = .current) -> Date {
        var момент = from
        var осталось = max(0, awake)
        // Предел шагов — страховка, а не логика: больше двух ночей
        // промежуток «обычно» не бывает.
        for _ in 0..<14 {
            let ночи = nights(around: момент, calendar: calendar)
            if let текущая = ночи.first(where: { $0.0 <= момент && момент < $0.1 }) {
                момент = текущая.1
                continue
            }
            guard let следующая = ночи.first(where: { $0.0 > момент }) else {
                guard let завтра = calendar.date(byAdding: .day, value: 1, to: момент) else { break }
                let доЗавтра = завтра.timeIntervalSince(момент)
                if осталось <= доЗавтра { return момент.addingTimeInterval(осталось) }
                осталось -= доЗавтра
                момент = завтра
                continue
            }
            let доНочи = следующая.0.timeIntervalSince(момент)
            if осталось <= доНочи { return момент.addingTimeInterval(осталось) }
            осталось -= доНочи
            момент = следующая.1
        }
        return момент.addingTimeInterval(осталось)
    }
}
