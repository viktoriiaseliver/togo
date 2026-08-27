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
        if incidents.count == 1 { return "все — \(incidents[0].kind.title.lowercased())" }
        return incidents.map { "\($0.kind.title.lowercased()) \($0.count)" }.joined(separator: " · ")
    }

    /// «−0,4 кг за месяц».
    var weightDelta: String? {
        guard let first = weights.first, let last = weights.last, weights.count > 1 else { return nil }
        let delta = last.kg - first.kg
        guard abs(delta) >= 0.05 else { return "вес держится" }
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
    /// Насколько поздняя доза ещё считается данной вовремя.
    static let onTimeWindow: TimeInterval = 3600

    static func build(
        events: [LogEvent],
        doses: [DoseRecord],
        weights: [(date: Date, kg: Double)],
        from: Date,
        to: Date
    ) -> VetSummary {
        let window = doses.filter { $0.scheduledAt >= from && $0.scheduledAt <= to }
        let given = window.filter(\.isGiven)
        let onTime = given.filter { dose in
            guard let givenAt = dose.givenAt else { return false }
            return givenAt.timeIntervalSince(dose.scheduledAt) <= onTimeWindow
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

        let now = current.incidentTotal, was = previous.incidentTotal
        if now != was {
            let word = now < was ? "реже" : "чаще"
            lines.append("Инциденты \(word) — \(now) против \(was) за прошлый период.")
        } else if now > 0 {
            lines.append("Инциденты держатся: \(now) и в прошлый период столько же.")
        }

        if let share = current.onTimeShare, let before = previous.onTimeShare {
            let delta = Int(((share - before) * 100).rounded())
            if abs(delta) >= 5 {
                lines.append("Доз вовремя \(delta > 0 ? "больше" : "меньше") на \(abs(delta))%.")
            }
        }

        if let weight = current.weightDelta { lines.append("Вес: \(weight).") }
        return lines
    }
}
