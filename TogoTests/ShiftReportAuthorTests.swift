import Testing
import Foundation
@testable import Togo

/// «Кто закрыл» в итоге смены — автор записи ТОГО ЖЕ пункта, а не
/// ближайшей по минуте записи любого вида.
///
/// До 29.10.2026 `ShiftReport.build` брал ближайшую запись смены
/// без разбора вида: доза в 08:00 закрывалась выходом в 08:02,
/// и итог говорил «дала Аня» за таблетку, которую дал Игорь.
/// Разбор — у `ShiftReport.Пункт`.
@MainActor
@Suite("Итог смены называет автора своей записи")
struct ShiftReportAuthorTests {

    private let день = Calendar.current.startOfDay(for: Date())

    private func в(_ час: Int, _ минута: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: час, minute: минута, second: 0, of: день) ?? день
    }

    private var смена: Shift { Shift(person: "Игорь", from: в(7), to: в(23)) }

    @Test("Доза не достаётся автору соседнего выхода")
    func дозаНеЧужая() {
        let схема = UUID()
        let выход = LogEvent(kind: .outing, date: в(8, 1), authorName: "Аня")
        let доза = LogEvent(kind: .dose, date: в(8, 4), authorName: "Игорь")
        доза.medicationID = схема

        let итог = ShiftReport.build(
            shift: смена,
            plan: [.init(id: "dose", title: "Т4", due: в(8), isDone: true,
                         вид: .dose, связь: схема)],
            events: [выход, доза])

        #expect(итог.items.first?.by == "Игорь",
                "автор дозы взят у ближайшей записи другого вида — выход в 08:01 ближе дозы в 08:04")
    }

    @Test("Автор из самой отметки дозы сильнее ленты")
    func отметкаСильнее() {
        let схема = UUID()
        let доза = LogEvent(kind: .dose, date: в(8), authorName: "Я")
        доза.medicationID = схема

        let итог = ShiftReport.build(
            shift: смена,
            plan: [.init(id: "dose", title: "Т4", due: в(8), isDone: true,
                         вид: .dose, связь: схема, автор: "Мама")],
            events: [доза])

        #expect(итог.items.first?.by == "Мама")
    }

    @Test("Уход узнаётся по делу и в тот же день, а не в окне вокруг часа сна")
    func уходПоДелу() {
        let дело = UUID()
        let другое = UUID()
        let когти = LogEvent(kind: .care, date: в(12), authorName: "Аня")
        когти.careTaskID = дело
        let чужое = LogEvent(kind: .care, date: в(22, 50), authorName: "Игорь")
        чужое.careTaskID = другое
        let ужин = LogEvent(kind: .meal, date: в(22, 55), authorName: "Игорь")

        let итог = ShiftReport.build(
            shift: смена,
            plan: [.init(id: "care", title: "Когти", due: в(23), isDone: true,
                         вид: .care, связь: дело)],
            events: [когти, чужое, ужин])

        #expect(итог.items.first?.by == "Аня")
    }

    @Test("Своей записи нет — автора нет, а не сосед по минуте")
    func безЗаписиБезАвтора() {
        let выход = LogEvent(kind: .outing, date: в(8), authorName: "Аня")

        let итог = ShiftReport.build(
            shift: смена,
            plan: [.init(id: "meal", title: "Еда", due: в(8), isDone: true, вид: .meal)],
            events: [выход])

        #expect(итог.items.first?.isDone == true, "контроль: пункт закрыт и попал в смену")
        #expect(итог.items.first?.by == nil)
    }
}
