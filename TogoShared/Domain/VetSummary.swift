import Foundation

/// Сводка для врача: разворот за минуту.
///
/// Из хендофа (18b): «Сначала цифры, потом дельта словами — врач читает
/// сверху вниз за минуту». И главное: **всё собирается из уже записанного.**
/// Ни одного поля «заполните для врача» — их не заполняют никогда,
/// а если заполняют, то по памяти, то есть неправдой.
nonisolated struct VetSummary: Equatable, Sendable {
    var from: Date
    var to: Date

    /// Доз дано вовремя, доз со сдвигом, пропущено.
    var dosesOnTime: Int
    var dosesShifted: Int
    var dosesSkipped: Int

    /// Инциденты по видам, от частого к редкому.
    var incidents: [(kind: IncidentKind, count: Int)]

    /// Вес: точки от старой к новой.
    var weights: [(date: Date, kg: Double)]

    var totalDoses: Int { dosesOnTime + dosesShifted }

    /// «94% доз вовремя». Без доз процента не бывает.
    var onTimeShare: Double? {
        guard totalDoses > 0 else { return nil }
        return Double(dosesOnTime) / Double(totalDoses)
    }

    var incidentTotal: Int { incidents.reduce(0) { $0 + $1.count } }

    /// «все — рвота» или «рвота и лужи».
    var incidentDetail: String? {
        guard !incidents.isEmpty else { return nil }
        if incidents.count == 1 { return String(localized: "все — \(incidents[0].kind.title.lowercased())") }
        return incidents.map { "\($0.kind.title.lowercased()) \($0.count)" }.joined(separator: " · ")
    }

    /// «−0,4 кг за месяц».
    var weightDelta: String? {
        guard let first = weights.first, let last = weights.last, weights.count > 1 else { return nil }
        let delta = last.kg - first.kg
        guard abs(delta) >= 0.05 else { return String(localized: "вес держится") }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(Fmt.decimal(abs(delta))) кг за период"
    }

    static func == (lhs: VetSummary, rhs: VetSummary) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to
            && lhs.dosesOnTime == rhs.dosesOnTime
            && lhs.dosesShifted == rhs.dosesShifted
            && lhs.dosesSkipped == rhs.dosesSkipped
            && lhs.incidents.map(\.kind) == rhs.incidents.map(\.kind)
            && lhs.incidents.map(\.count) == rhs.incidents.map(\.count)
            && lhs.weights.map(\.kg) == rhs.weights.map(\.kg)
    }
}

nonisolated enum VetSummaryBuilder {
    /// Период из двух дат пикера — ЦЕЛЫМИ СУТКАМИ.
    ///
    /// **Заведено 29.10.2026.** `DatePicker(displayedComponents: .date)`
    /// показывает только день, а несёт полную дату — с часом, в который
    /// экран открыли. «С 29 сентября» на деле значило «с 29 сентября,
    /// 14:37», «по 29 октября» — «по 29 октября, 14:37»: утро первого
    /// дня и вечер последнего выпадали из сводки и выгрузки молча,
    /// хотя на экране оба дня стояли целиком.
    ///
    /// Начало — полночь первого дня, конец — последний миг последнего:
    /// сравнения здесь и у читателей `>=` / `<=`, поэтому конец берётся
    /// на миллисекунду раньше следующей полуночи, а не самой полуночью.
    static func целыеСутки(с from: Date, по to: Date,
                           calendar: Calendar = .current) -> (from: Date, to: Date) {
        let начало = calendar.startOfDay(for: min(from, to))
        let последнийДень = calendar.startOfDay(for: max(from, to))
        let следующаяПолночь = calendar.date(byAdding: .day, value: 1, to: последнийДень)
            ?? последнийДень.addingTimeInterval(86_400)
        return (from: начало, to: следующаяПолночь.addingTimeInterval(-0.001))
    }

    /// Насколько поздняя доза ещё считается данной вовремя — **и число,
    /// и предикат берутся у `TreatmentCourse`.**
    ///
    /// Здесь стояла своя `onTimeWindow = 3600` и свой трёхстрочный
    /// фильтр, посимвольно совпадавший с тем, что в
    /// `TreatmentCourse.summary`. Две копии одного порога, из которых
    /// одну человек видит на экране, а вторую несёт врачу.
    static var onTimeWindow: TimeInterval { TreatmentCourse.onTimeWindow }

    static func build(
        events: [LogEvent],
        doses: [DoseRecord],
        weights: [(date: Date, kg: Double)],
        from: Date,
        to: Date
    ) -> VetSummary {
        let window = doses.filter { $0.scheduledAt >= from && $0.scheduledAt <= to }
        let given = window.filter(\.isGiven)
        let onTime = given.filter {
            TreatmentCourse.даноВовремя(scheduledAt: $0.scheduledAt, givenAt: $0.givenAt)
        }

        let incidentEvents = Diary.active(events)
            .filter { $0.kind == .incident && $0.date >= from && $0.date <= to }
        let byKind = Dictionary(grouping: incidentEvents) { $0.incidentKind ?? .other }
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        return VetSummary(
            from: from,
            to: to,
            dosesOnTime: onTime.count,
            dosesShifted: given.count - onTime.count,
            dosesSkipped: window.filter(\.isSkipped).count,
            incidents: byKind,
            weights: weights.filter { $0.date >= from && $0.date <= to }
                .sorted { $0.date < $1.date }
        )
    }

    /// «Что изменилось» словами — сравнение с прошлым таким же периодом.
    ///
    /// Врач спрашивает не «сколько было», а «стало лучше или хуже».
    /// Считаем это сами, потому что человек в кабинете не помнит.
    static func delta(current: VetSummary, previous: VetSummary) -> [String] {
        var lines: [String] = []

        // **Все пять строк были склеены по-русски и в каталог не попадали
        //   никогда** (замер 26.10.2026). Это сводка, которую читает ВРАЧ:
        //   куски шли через интерполяцию обычной `String`, а не через
        //   `String(localized:)`, поэтому извлечение строк их не видело,
        //   и сторож полноты каталога — тоже: он сверяет то, что В каталоге,
        //   а этих строк там не бывало.
        //
        // **Два ключа вместо склейки со словом из тернарника.** Прежде
        //   «реже»/«чаще» и «больше»/«меньше» выбирались ПО-РУССКИ
        //   и уезжали в подстановку. Даже оберни склейку целиком —
        //   носитель получил бы «Инциденты %@ — …» и не узнал бы, какое
        //   из двух слов там окажется; а в языке с согласованием выбрать
        //   второе слово по первому нельзя вовсе.
        //
        // > **Слово, выбранное кодом, переводом не становится.**
        //   Переводится фраза, а не её кусок.
        let now = current.incidentTotal, was = previous.incidentTotal
        if now != was {
            lines.append(now < was
                ? String(localized: "Инциденты реже — \(now) против \(was) за прошлый период.")
                : String(localized: "Инциденты чаще — \(now) против \(was) за прошлый период."))
        } else if now > 0 {
            lines.append(String(localized: "Инциденты держатся: \(now) и в прошлый период столько же."))
        }

        if let share = current.onTimeShare, let before = previous.onTimeShare {
            let delta = Int(((share - before) * 100).rounded())
            if abs(delta) >= 5 {
                lines.append(delta > 0
                    ? String(localized: "Доз вовремя больше на \(abs(delta))%.")
                    : String(localized: "Доз вовремя меньше на \(abs(delta))%."))
            }
        }

        if let weight = current.weightDelta { lines.append(String(localized: "Вес: \(weight).")) }
        return lines
    }
}
