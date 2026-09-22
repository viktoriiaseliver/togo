import Foundation

/// Можно ли кормить прямо сейчас, если собака на лекарстве натощак.
///
/// **Дыра, ради которой это заведено.** В модели было окно натощак
/// ТОЛЬКО ПОСЛЕ дозы (`Medication.fastingMinutes`) — «еда внутри него
/// мешает всасыванию». Но «натощак» означает пустой желудок, а пустым
/// он бывает не после таблетки, а **до** неё. Схема, где человек
/// покормил в 20:55 и дал таблетку в 21:00, по прежней модели была
/// безупречной: окно после дозы соблюдено, а таблетка при этом выпита
/// на полный желудок — то есть ровно то, чего схема запрещает.
///
/// Половина правила молча отсутствовала, и заметить это было нечем:
/// приложение не спорило, потому что не знало.
///
/// Теперь окно двустороннее, и у него две разные причины:
///
/// | | Почему нельзя кормить |
/// |---|---|
/// | до дозы | желудок должен быть пустым, иначе таблетка не всосётся |
/// | после дозы | еда мешает всасыванию уже выпитой |
///
/// Окно «до» берётся у `Medication.fastingBefore`, и у старых схем оно
/// равно окну «после» — см. там, почему это исправление, а не догадка.
nonisolated enum FeedingGate {

    /// Почему кормить нельзя. Причина называется словами: «нельзя»
    /// без причины человек выполнит один раз, а на второй обойдёт.
    enum Block: Equatable, Sendable {
        /// До дозы: желудок должен быть пустым к приёму.
        case before(medication: String, doseAt: Date)
        /// После дозы: еда помешает всасыванию.
        case after(medication: String, givenAt: Date, until: Date)

        /// Когда снова можно кормить. У «до» это момент самой дозы:
        /// дальше решает уже отметка приёма, а не расписание.
        var freeAt: Date {
            switch self {
            case .before(_, let doseAt): doseAt
            case .after(_, _, let until): until
            }
        }

        var medication: String {
            switch self {
            case .before(let name, _), .after(let name, _, _): name
            }
        }
    }

    /// Состояние на момент `now`. `nil` — кормить можно.
    ///
    /// Порядок проверки не случаен: **сначала «после», потом «до»**.
    /// Уже выпитая доза — факт, а ближайшая по расписанию — только план;
    /// когда окна накладываются, человеку важнее то, что уже произошло.
    static func block(
        for medications: [Medication],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Block? {
        let active = medications.filter { !$0.isPaused }

        for medication in active where medication.fastingMinutes > 0 {
            guard let givenAt = lastGiven(medication, notAfter: now) else { continue }
            let until = givenAt.addingTimeInterval(Double(medication.fastingMinutes) * 60)
            if now < until {
                return .after(medication: medication.name, givenAt: givenAt, until: until)
            }
        }

        for medication in active where medication.fastingBefore > 0 {
            for doseAt in upcoming(medication, from: now, calendar: calendar) {
                let opens = doseAt.addingTimeInterval(-Double(medication.fastingBefore) * 60)
                if now >= opens && now < doseAt {
                    return .before(medication: medication.name, doseAt: doseAt)
                }
            }
        }

        return nil
    }

    /// Последняя отметка приёма не позже `now`.
    private static func lastGiven(_ medication: Medication, notAfter now: Date) -> Date? {
        medication.doses
            .filter { $0.isGiven }
            .compactMap(\.givenAt)
            .filter { $0 <= now }
            .max()
    }

    /// Плановые приёмы сегодня и завтра, которые ещё впереди.
    ///
    /// Завтрашние нужны из-за полуночи: доза в 00:30 запирает еду
    /// с 23:30 предыдущего дня, и без завтрашнего дня это окно
    /// не существовало бы вовсе.
    private static func upcoming(
        _ medication: Medication, from now: Date, calendar: Calendar
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        return [today, tomorrow]
            .flatMap { day in
                medication.times.compactMap { minutes in
                    // Минуты от полуночи — это час на часах, а не отрезок:
                    // сложением секунд доза 21:00 в день перевода часов
                    // становилась 20:00 (см. DayTime).
                    calendar.date(minuteOfDay: minutes, on: day)
                }
            }
            .filter { $0 > now }
            // Уже отмеченную дозу запирать нельзя: если её дали раньше
            // срока, еда упирается в окно «после», а не в план.
            .filter { doseAt in
                !medication.doses.contains { dose in
                    dose.isGiven && calendar.isDate(dose.givenAt ?? .distantPast,
                                                    equalTo: doseAt, toGranularity: .hour)
                }
            }
            .sorted()
    }
}
