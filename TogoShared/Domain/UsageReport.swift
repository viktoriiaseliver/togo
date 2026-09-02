import Foundation

/// Отчёт по журналу действий.
///
/// Сам журнал — это список тапов, и читать его строку за строкой через две
/// недели невозможно: там тысячи строк. Отчёт отвечает на три вопроса,
/// ради которых журнал и заводился:
///
/// 1. **Чем вообще пользуются.** Экраны, которые не открыли ни разу за две
///    недели, — это либо ненужный раздел, либо его не нашли.
/// 2. **Где приложение мешало.** Отмена сразу после записи, удаление через
///    минуту, пойманный двойной тап, отказ по правам, сбой — каждое из
///    этого чинится, и каждое видно только в журнале.
/// 3. **Как выглядит обычный день.** Сколько сеансов, сколько записей,
///    сколько живёт сеанс.
///
/// Считается на чистых значениях, без файлов и базы, — поэтому проверяется
/// тестами целиком.
nonisolated struct UsageReport: Sendable {

    /// Строка «сколько раз».
    struct Count: Sendable, Identifiable {
        var name: String
        var count: Int
        var id: String { name }
    }

    /// Непрерывная работа с приложением.
    struct Session: Sendable, Identifiable {
        var id: String
        var startedAt: Date
        var endedAt: Date
        var actions: Int
        var records: Int
        var screens: [String]

        var length: TimeInterval { endedAt.timeIntervalSince(startedAt) }
        /// Открыл и закрыл, ничего не записав.
        var isIdle: Bool { records == 0 }
    }

    /// То, что стоит починить. Не «ошибка приложения» — а место, где
    /// человеку было неудобно, и это видно по его действиям.
    struct Friction: Sendable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var count: Int
        /// Где это чаще всего случалось.
        var screens: [String]
    }

    var from: Date
    var to: Date
    var days: Int
    var total: Int
    var records: Int
    var sessions: [Session]
    var byAction: [Count]
    var byScreen: [Count]
    var byRecordKind: [Count]
    var byDay: [Count]
    var outcomes: [Count]
    var frictions: [Friction]
    /// Экраны, которых человек не открыл ни разу.
    var untouchedScreens: [String]

    var isEmpty: Bool { total == 0 }

    var averageSessionLength: TimeInterval {
        let lengths = sessions.map(\.length).filter { $0 > 0 }
        guard !lengths.isEmpty else { return 0 }
        return lengths.reduce(0, +) / Double(lengths.count)
    }

    var recordsPerDay: Double {
        days > 0 ? Double(records) / Double(days) : 0
    }

    // MARK: Сборка

    /// Насколько быстрая отмена считается промахом, а не решением.
    static let misTapWindow: TimeInterval = 20
    /// Удаление вскоре после записи — тот же промах, только замеченный позже.
    static let quickDeleteWindow: TimeInterval = 90
    /// Экран, закрытый быстрее этого, не успели прочитать.
    static let glanceWindow: TimeInterval = 2.5
    /// Сколько раз подряд надо ткнуть в одно и то же, чтобы это было «жму
    /// и не понимаю, сработало ли».
    static let insistentTaps = 3
    static let insistentWindow: TimeInterval = 30

    static func build(_ entries: [UsageLog.Entry], now: Date = Date()) -> UsageReport {
        let sorted = entries.sorted { $0.at < $1.at }
        let calendar = Calendar.current

        guard let first = sorted.first, let last = sorted.last else {
            return UsageReport(from: now, to: now, days: 0, total: 0, records: 0,
                               sessions: [], byAction: [], byScreen: [], byRecordKind: [],
                               byDay: [], outcomes: [], frictions: [],
                               untouchedScreens: UsageLog.Screen.allCases.map(\.rawValue))
        }

        let days = (calendar.dateComponents([.day],
                                            from: calendar.startOfDay(for: first.at),
                                            to: calendar.startOfDay(for: last.at)).day ?? 0) + 1

        let recorded = sorted.filter { $0.kind == .record && $0.result == .done }
        let touched = Set(sorted.map(\.screen))

        let actionNames: [String] = sorted.map { $0.kind?.title ?? $0.action }
        let screenNames: [String] = sorted.map { screenTitle($0.screen) }
        let outcomeNames: [String] = sorted.compactMap { UsageLog.Outcome(rawValue: $0.outcome)?.title }
        let recordKinds: [String] = recorded.compactMap { $0.detail }
        let untouched: [String] = UsageLog.Screen.allCases
            .filter { $0 != .other && !touched.contains($0.rawValue) }
            .map { $0.title }

        return UsageReport(
            from: first.at,
            to: last.at,
            days: days,
            total: sorted.count,
            records: recorded.count,
            sessions: sessionList(sorted),
            byAction: tally(actionNames),
            byScreen: tally(screenNames),
            byRecordKind: tally(recordKinds),
            byDay: dayTally(sorted, calendar: calendar),
            outcomes: tally(outcomeNames),
            frictions: frictionList(sorted),
            untouchedScreens: untouched
        )
    }

    static func screenTitle(_ raw: String) -> String {
        UsageLog.Screen(rawValue: raw)?.title ?? raw
    }

    private static func tally(_ names: [String]) -> [Count] {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts
            .map { Count(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    private static func dayTally(_ sorted: [UsageLog.Entry], calendar: Calendar) -> [Count] {
        var counts: [Date: Int] = [:]
        for entry in sorted { counts[calendar.startOfDay(for: entry.at), default: 0] += 1 }
        return counts
            .sorted { $0.key < $1.key }
            .map { Count(name: Fmt.shortDay($0.key), count: $0.value) }
    }

    private static func sessionList(_ sorted: [UsageLog.Entry]) -> [Session] {
        var order: [String] = []
        var grouped: [String: [UsageLog.Entry]] = [:]
        for entry in sorted {
            if grouped[entry.session] == nil { order.append(entry.session) }
            grouped[entry.session, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let items = grouped[id], let first = items.first, let last = items.last else { return nil }
            var screens: [String] = []
            for item in items where screens.last != item.screen {
                screens.append(item.screen)
            }
            return Session(
                id: id,
                startedAt: first.at,
                endedAt: last.at,
                actions: items.count,
                records: items.filter { $0.kind == .record && $0.result == .done }.count,
                screens: screens.map(screenTitle)
            )
        }
    }

    // MARK: Что чинить

    private static func frictionList(_ sorted: [UsageLog.Entry]) -> [Friction] {
        var found: [Friction] = []

        // 1. Отмена сразу после записи. Человек нажал не то — значит,
        //    кнопки стоят слишком близко или подписаны непонятно.
        let misTaps = pairs(sorted, from: .record, to: .undo, within: misTapWindow)
        if !misTaps.isEmpty {
            found.append(Friction(
                id: "mis-tap",
                title: "Отменили сразу после записи",
                detail: "Между записью и «Отменить» меньше \(Int(misTapWindow)) секунд — это промах пальцем, а не решение. Смотри, что стоит рядом с этой кнопкой.",
                count: misTaps.count,
                screens: topScreens(misTaps)
            ))
        }

        // 2. Удаление вскоре после записи: то же самое, замеченное позже.
        let quickDeletes = pairs(sorted, from: .record, to: .delete, within: quickDeleteWindow)
        if !quickDeletes.isEmpty {
            found.append(Friction(
                id: "quick-delete",
                title: "Удалили почти сразу после записи",
                detail: "Записали и через минуту стёрли — обычно значит, что записалось не то или не так, как ожидали.",
                count: quickDeletes.count,
                screens: topScreens(quickDeletes)
            ))
        }

        // 3. Пойманный двойной тап. Защита сработала — но человек жал
        //    дважды, потому что не понял, что первый тап сработал.
        let duplicates = sorted.filter { $0.result == .duplicate }
        if !duplicates.isEmpty {
            found.append(Friction(
                id: "duplicate",
                title: "Жали дважды по одной кнопке",
                detail: "Защита от дубля сработала, но сам факт — про отклик: после тапа не видно, что он прошёл.",
                count: duplicates.count,
                screens: topScreens(duplicates)
            ))
        }

        // 4. Не хватило прав. Кнопка была видна и нажималась — а не должна была.
        let blocked = sorted.filter { $0.result == .blocked }
        if !blocked.isEmpty {
            found.append(Friction(
                id: "blocked",
                title: "Нажали то, что не разрешено",
                detail: "Роль не даёт этого делать, но кнопка была доступна. Правильнее её не показывать вовсе, чем отказывать после тапа.",
                count: blocked.count,
                screens: topScreens(blocked)
            ))
        }

        // 5. Сбои: приложение не сделало того, что обещало.
        let failures = sorted.filter { $0.result == .failed || $0.kind == .failure }
        if !failures.isEmpty {
            found.append(Friction(
                id: "failure",
                title: "Приложение не справилось",
                detail: "Строки со сбоем: " + shortList(failures.compactMap(\.detail)),
                count: failures.count,
                screens: topScreens(failures)
            ))
        }

        // 6. Экран открыли и тут же ушли. Один раз — случайность,
        //    трижды — экран не отвечает на вопрос, с которым в него идут.
        let glances = glancedScreens(sorted)
        if glances.count >= 3 {
            found.append(Friction(
                id: "glance",
                title: "Открывали экран и сразу уходили",
                detail: "Меньше \(Fmt.decimal(glanceWindow)) секунды на экране — прочитать там нечего, а искали что-то другое.",
                count: glances.count,
                screens: topScreens(glances)
            ))
        }

        // 7. Одно и то же подряд: жмут и не понимают, сработало ли.
        let insistent = insistentRuns(sorted)
        if !insistent.isEmpty {
            found.append(Friction(
                id: "insistent",
                title: "Повторяли одно действие подряд",
                detail: "\(insistentTaps) и больше одинаковых действий за полминуты — обычно значит, что результат не виден на экране.",
                count: insistent.count,
                screens: topScreens(insistent)
            ))
        }

        // 8. Прогулку начали и не закончили. Таймер шёл, а записи нет.
        let unfinished = unfinishedStarts(sorted)
        if !unfinished.isEmpty {
            found.append(Friction(
                id: "unfinished",
                title: "Начали и не закончили",
                detail: "Прогулка или занятие остались открытыми — значит, кнопка «закончить» не там, где её ищут.",
                count: unfinished.count,
                screens: topScreens(unfinished)
            ))
        }

        // 9. Сеансы вхолостую: открыл, походил, ничего не записал.
        let idle = sessionList(sorted).filter { $0.isIdle && $0.actions > 2 }
        if idle.count >= 3 {
            found.append(Friction(
                id: "idle-session",
                title: "Заходили и ничего не записали",
                detail: "\(idle.count) сеансов подряд без единой записи — приложение открывали не чтобы записать, а чтобы что-то посмотреть. Стоит понять, что именно.",
                count: idle.count,
                screens: []
            ))
        }

        return found.sorted { $0.count > $1.count }
    }

    /// Пары «сделал — тут же передумал» в пределах одного сеанса.
    private static func pairs(_ sorted: [UsageLog.Entry],
                              from: UsageLog.Action,
                              to: UsageLog.Action,
                              within window: TimeInterval) -> [UsageLog.Entry] {
        var result: [UsageLog.Entry] = []
        for (index, entry) in sorted.enumerated() where entry.kind == to {
            let earlier = sorted[..<index].last {
                $0.kind == from && $0.session == entry.session && $0.result == .done
            }
            guard let earlier, entry.at.timeIntervalSince(earlier.at) <= window else { continue }
            result.append(entry)
        }
        return result
    }

    /// Экраны, на которых не задержались.
    private static func glancedScreens(_ sorted: [UsageLog.Entry]) -> [UsageLog.Entry] {
        let opens = sorted.enumerated().filter { $0.element.kind == .open }
        var result: [UsageLog.Entry] = []
        for (index, entry) in opens {
            guard let next = sorted[(index + 1)...].first(where: { $0.session == entry.session }) else { continue }
            // Ушли на другой экран, ничего на этом не сделав.
            guard next.kind == .open || next.kind == .tab else { continue }
            if next.at.timeIntervalSince(entry.at) < glanceWindow { result.append(entry) }
        }
        return result
    }

    /// Одно и то же действие подряд.
    private static func insistentRuns(_ sorted: [UsageLog.Entry]) -> [UsageLog.Entry] {
        var result: [UsageLog.Entry] = []
        var run: [UsageLog.Entry] = []

        func close() {
            if run.count >= insistentTaps, let first = run.first { result.append(first) }
            run.removeAll()
        }

        for entry in sorted {
            guard entry.kind != .open, entry.kind != .tab else { close(); continue }
            if let previous = run.last,
               previous.action == entry.action,
               previous.detail == entry.detail,
               previous.session == entry.session,
               entry.at.timeIntervalSince(previous.at) <= insistentWindow {
                run.append(entry)
            } else {
                close()
                run = [entry]
            }
        }
        close()
        return result
    }

    /// «Начал» без парного «закончил» в том же сеансе.
    private static func unfinishedStarts(_ sorted: [UsageLog.Entry]) -> [UsageLog.Entry] {
        sorted.enumerated().compactMap { index, entry in
            guard entry.kind == .start, entry.result == .done else { return nil }
            let closed = sorted[(index + 1)...].contains {
                $0.session == entry.session && $0.kind == .finish && $0.detail == entry.detail
            }
            return closed ? nil : entry
        }
    }

    private static func topScreens(_ entries: [UsageLog.Entry]) -> [String] {
        tally(entries.map { screenTitle($0.screen) })
            .prefix(3)
            .map(\.name)
    }

    private static func shortList(_ values: [String]) -> String {
        let unique = tally(values).prefix(3).map(\.name)
        return unique.isEmpty ? "без подробностей" : unique.joined(separator: ", ")
    }

    // MARK: Отчёт словами

    /// Текст для выгрузки и для письма: то же, что на экране, но одним куском.
    var text: String {
        var lines: [String] = []
        lines.append("Того · журнал действий")
        lines.append("с \(Fmt.shortDay(from)) по \(Fmt.shortDay(to)) · \(Fmt.days(days))")
        lines.append("")
        lines.append("Действий: \(total) · записей: \(records) · сеансов: \(sessions.count)")
        if averageSessionLength > 0 {
            lines.append("Сеанс в среднем: \(Fmt.duration(averageSessionLength))")
        }
        lines.append("Записей в день: \(Fmt.decimal((recordsPerDay * 10).rounded() / 10))")

        if !frictions.isEmpty {
            lines.append("")
            lines.append("ЧТО ЧИНИТЬ")
            for item in frictions {
                lines.append("• \(item.title) — \(item.count)")
                lines.append("  \(item.detail)")
                if !item.screens.isEmpty {
                    lines.append("  где: \(item.screens.joined(separator: ", "))")
                }
            }
        }

        lines.append("")
        lines.append("ЧАЩЕ ВСЕГО")
        for item in byAction.prefix(10) { lines.append("• \(item.name) — \(item.count)") }

        if !byRecordKind.isEmpty {
            lines.append("")
            lines.append("ЧТО ЗАПИСЫВАЛИ")
            for item in byRecordKind.prefix(10) { lines.append("• \(item.name) — \(item.count)") }
        }

        lines.append("")
        lines.append("ЭКРАНЫ")
        for item in byScreen.prefix(15) { lines.append("• \(item.name) — \(item.count)") }

        if !untouchedScreens.isEmpty {
            lines.append("")
            lines.append("НЕ ОТКРЫВАЛИ НИ РАЗУ")
            lines.append(untouchedScreens.joined(separator: ", "))
        }

        lines.append("")
        lines.append("ПО ДНЯМ")
        for item in byDay { lines.append("• \(item.name) — \(item.count)") }

        return lines.joined(separator: "\n")
    }
}
