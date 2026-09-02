import Testing
import Foundation
@testable import Togo

/// Журнал действий заводится ради одного: через две недели пользования
/// увидеть, где приложение мешало. Поэтому проверяется не то, что строки
/// пишутся, а то, что из них правильно вычитываются трения.
@Suite("Журнал действий")
struct UsageLogTests {

    private let day = Date(timeIntervalSince1970: 1_772_000_000)

    private func entry(_ action: UsageLog.Action,
                       _ detail: String? = nil,
                       at seconds: Double,
                       session: String = "a1",
                       screen: UsageLog.Screen = .today,
                       outcome: UsageLog.Outcome = .done) -> UsageLog.Entry {
        UsageLog.Entry(
            at: day.addingTimeInterval(seconds),
            session: session,
            screen: screen.rawValue,
            action: action.rawValue,
            outcome: outcome.rawValue,
            detail: detail
        )
    }

    @Test("Пустой журнал не ломает отчёт и честно говорит, что пуст")
    func emptyReport() {
        let report = UsageReport.build([], now: day)
        #expect(report.isEmpty)
        #expect(report.total == 0)
        #expect(report.sessions.isEmpty)
        #expect(report.frictions.isEmpty)
        // Не открытыми считаются все экраны — иначе пустой журнал выглядел бы
        // так, будто человек обошёл приложение целиком.
        #expect(report.untouchedScreens.count == UsageLog.Screen.allCases.count)
    }

    @Test("Сеанс — это группа действий, а не одно действие")
    func sessionsGroup() {
        let report = UsageReport.build([
            entry(.open, at: 0),
            entry(.record, "meal", at: 30),
            entry(.open, at: 40, session: "b2", screen: .feeding),
            entry(.record, "water", at: 90, session: "b2", screen: .feeding),
        ], now: day)

        #expect(report.sessions.count == 2)
        #expect(report.sessions.first?.actions == 2)
        #expect(report.sessions.first?.records == 1)
        #expect(report.sessions.last?.length == 50)
        #expect(report.records == 2)
    }

    @Test("Отмена сразу после записи — это промах пальцем")
    func misTapIsFound() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0),
            entry(.undo, "meal", at: 8),
        ], now: day)

        let friction = report.frictions.first { $0.id == "mis-tap" }
        #expect(friction?.count == 1)
        #expect(friction?.screens == ["Сегодня"])
    }

    @Test("Отмена через полчаса — это решение, а не промах")
    func lateUndoIsNotMisTap() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0),
            entry(.undo, "meal", at: 30 * 60),
        ], now: day)

        #expect(!report.frictions.contains { $0.id == "mis-tap" })
    }

    @Test("Записали и почти сразу стёрли — записалось не то")
    func quickDeleteIsFound() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0),
            entry(.delete, "meal", at: 40),
        ], now: day)

        #expect(report.frictions.contains { $0.id == "quick-delete" })
    }

    @Test("Пойманный двойной тап и отказ по правам попадают в отчёт")
    func outcomesBecomeFrictions() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0, outcome: .duplicate),
            entry(.record, "dose", at: 10, outcome: .blocked),
            entry(.record, "meal", at: 20, outcome: .failed),
        ], now: day)

        #expect(report.frictions.contains { $0.id == "duplicate" })
        #expect(report.frictions.contains { $0.id == "blocked" })
        #expect(report.frictions.contains { $0.id == "failure" })
        // Неудавшаяся запись записью не считается: иначе отчёт врал бы
        // о том, сколько человек занёс в дневник.
        #expect(report.records == 0)
    }

    @Test("Прогулка, которую начали и не закончили")
    func unfinishedWalk() {
        let report = UsageReport.build([
            entry(.start, "walk", at: 0),
            entry(.mark, "urine", at: 300),
        ], now: day)

        #expect(report.frictions.contains { $0.id == "unfinished" })
    }

    @Test("Законченная прогулка трением не считается")
    func finishedWalkIsFine() {
        let report = UsageReport.build([
            entry(.start, "walk", at: 0),
            entry(.finish, "walk", at: 1800),
        ], now: day)

        #expect(!report.frictions.contains { $0.id == "unfinished" })
    }

    @Test("Три одинаковых действия подряд — человек не видит результата")
    func insistentTaps() {
        let report = UsageReport.build([
            entry(.record, "water", at: 0),
            entry(.record, "water", at: 5),
            entry(.record, "water", at: 9),
        ], now: day)

        #expect(report.frictions.contains { $0.id == "insistent" })
    }

    @Test("Экран, открытый и брошенный за секунду, замечается")
    func glancedScreen() {
        var entries: [UsageLog.Entry] = []
        for index in 0..<3 {
            let base = Double(index) * 600
            entries.append(entry(.open, at: base, screen: .history))
            entries.append(entry(.open, at: base + 1, screen: .today))
        }
        let report = UsageReport.build(entries, now: day)
        #expect(report.frictions.contains { $0.id == "glance" })
    }

    @Test("Разрезы считают то, что было, а не то, что казалось")
    func breakdowns() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0),
            entry(.record, "meal", at: 3600),
            entry(.record, "water", at: 7200),
            entry(.open, at: 10, screen: .feeding),
        ], now: day)

        #expect(report.byRecordKind.first?.name == "meal")
        #expect(report.byRecordKind.first?.count == 2)
        #expect(report.byAction.first?.name == UsageLog.Action.record.title)
        #expect(report.byScreen.contains { $0.name == "Кормление" })
        #expect(!report.untouchedScreens.contains("Кормление"))
    }

    @Test("Отчёт словами содержит то, ради чего его открывают")
    func textReport() {
        let report = UsageReport.build([
            entry(.record, "meal", at: 0),
            entry(.undo, "meal", at: 5),
        ], now: day)

        let text = report.text
        #expect(text.contains("ЧТО ЧИНИТЬ"))
        #expect(text.contains("Отменили сразу после записи"))
        #expect(text.contains("ЭКРАНЫ"))
    }

    @Test("Строка журнала переживает запись в файл и чтение обратно")
    func codableRoundTrip() throws {
        let original = entry(.record, "meal", at: 0, outcome: .duplicate)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(UsageLog.Entry.self, from: encoder.encode(original))
        #expect(restored == original)
        #expect(restored.kind == .record)
        #expect(restored.result == .duplicate)
    }
}

/// Минута от полуночи превращается в час по календарю, а не сложением
/// секунд: иначе два раза в год всё расписание уезжает на час.
@Suite("Время суток и перевод часов")
struct DayTimeTests {

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)) ?? Date()
    }

    @Test("В обычный день 480 минут — это восемь утра")
    func ordinaryDay() {
        let at = paris.date(minuteOfDay: 8 * 60, on: day(2026, 6, 15))
        #expect(paris.component(.hour, from: at) == 8)
        #expect(paris.component(.minute, from: at) == 0)
    }

    @Test("В день перевода часов вперёд доза остаётся на своём часе")
    func springForward() {
        // Ночь на 29 марта 2026: в 02:00 стрелки прыгают на 03:00,
        // и в сутках 23 часа. Сложение секунд от полуночи дало бы 09:00.
        let at = paris.date(minuteOfDay: 8 * 60, on: day(2026, 3, 29))
        #expect(paris.component(.hour, from: at) == 8)
    }

    @Test("В день перевода часов назад — тоже")
    func fallBack() {
        // 25 октября 2026: в сутках 25 часов, сложение дало бы 07:00.
        let at = paris.date(minuteOfDay: 8 * 60, on: day(2026, 10, 25))
        #expect(paris.component(.hour, from: at) == 8)
    }

    @Test("Несуществующего часа не бывает: календарь отдаёт ближайший реальный")
    func missingHour() {
        // 02:30 в ночь перевода вперёд не существует вовсе.
        let at = paris.date(minuteOfDay: 2 * 60 + 30, on: day(2026, 3, 29))
        #expect(paris.component(.hour, from: at) == 3)
    }
}
