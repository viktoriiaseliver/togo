import Testing
import Foundation
@testable import Togo

/// Виджет считает «сколько прошло» от туалета, тем же правилом, что герой
/// «Сегодня», — и считает ЖИВО, от момента записи ленты.
///
/// **Повод — два дефекта 29.10.2026 сразу.** Малая плитка считала
/// «С прогулки» от начала последней прогулки (`signals.lastWalk`), а не
/// от туалета и не от конца выхода; локскрин печатал интервал,
/// посчитанный в момент публикации снимка, и при закрытом приложении
/// не двигался. Первое проверяется правилом якоря, второе — тем, что
/// строка на двух разных `now` разная.
@Suite("Якорь счёта: от туалета, и живой")
struct ToiletAnchorTests {

    private static let сейчас = Date(timeIntervalSince1970: 1_761_000_000)
    private static func часовНазад(_ ч: Double) -> Date { сейчас.addingTimeInterval(-ч * 3600) }

    // MARK: - Правило

    @Test("Свежий туалет — якорь, даже если выход был позже")
    func свежийТуалет() {
        let якорь = ToiletAnchor.якорь(туалет: Self.часовНазад(3), дома: false,
                                       выход: Self.часовНазад(1), now: Self.сейчас)
        // Выход без результата час назад не сбрасывает счёт — ради этого
        // решение и принималось.
        #expect(якорь == ToiletAnchor.Якорь(когда: Self.часовНазад(3), откуда: .улица))
    }

    @Test("Туалет дома называется домом")
    func туалетДома() {
        let якорь = ToiletAnchor.якорь(туалет: Self.часовНазад(2), дома: true,
                                       выход: nil, now: Self.сейчас)
        #expect(якорь?.откуда == .дом)
    }

    @Test("Туалет за потолком при свежем выходе — счёт от выхода")
    func устаревшийТуалет() {
        let якорь = ToiletAnchor.якорь(туалет: Self.часовНазад(30), дома: false,
                                       выход: Self.часовНазад(2), now: Self.сейчас)
        #expect(якорь == ToiletAnchor.Якорь(когда: Self.часовНазад(2), откуда: .выход))
    }

    @Test("Туалета нет — запасной выход; нет и выхода — пусто")
    func безТуалета() {
        #expect(ToiletAnchor.якорь(туалет: nil, дома: false, выход: Self.часовНазад(4),
                                   now: Self.сейчас)?.откуда == .выход)
        #expect(ToiletAnchor.якорь(туалет: nil, дома: false, выход: nil, now: Self.сейчас) == nil)
    }

    @Test("За потолком тишины называется дата, а не число")
    func тишина() {
        let давний = ToiletAnchor.Якорь(когда: Self.часовНазад(30), откуда: .улица)
        #expect(ToiletAnchor.тишина(давний, now: Self.сейчас) == Self.часовНазад(30))
        let свежий = ToiletAnchor.Якорь(когда: Self.часовНазад(3), откуда: .улица)
        #expect(ToiletAnchor.тишина(свежий, now: Self.сейчас) == nil)
    }

    // MARK: - Снимок → строка

    private static var снимок: WidgetSnapshot {
        var s = WidgetSnapshot.empty
        s.dogName = "Стич"
        s.lastToiletAt = часовНазад(2)
        s.lastToiletAtHome = false
        s.lastOutingEndedAt = часовНазад(2)
        // Застывшее число прежнего пути — нарочно другое, чтобы было
        // видно, что строка его больше не печатает.
        s.sinceUrineSeconds = 7 * 3600
        return s
    }

    @Test("Строка локскрина идёт вместе с часами, а не стоит")
    func строкаЖивая() {
        let теперь = SnapshotText.sinceText(Self.снимок, now: Self.сейчас)
        let черезЧас = SnapshotText.sinceText(Self.снимок, now: Self.сейчас.addingTimeInterval(3600))
        #expect(теперь != черезЧас, "строка не изменилась за час — виджет снова стоит")
        #expect(теперь == String(localized: "сходил \(Fmt.duration(2 * 3600)) назад"))
        #expect(!теперь.contains(Fmt.duration(7 * 3600)),
                "строка напечатала интервал из момента публикации, а не от часов")

        let инлайн = SnapshotText.inlineText(Self.снимок, now: Self.сейчас.addingTimeInterval(3600))
        #expect(инлайн.hasPrefix(Fmt.duration(3 * 3600)))
    }

    @Test("Старый снимок без полей туалета читается прежней дорогой")
    func старыйСнимок() {
        var s = WidgetSnapshot.empty
        s.lastWalkAt = Self.часовНазад(2)
        // Снимок версии до 29.10 знает только `lastWalkAt` — он и есть якорь.
        #expect(SnapshotText.якорь(s, now: Self.сейчас)?.откуда == .выход)

        // Совсем пустой — прежняя `sinceText`, со своим правилом тишины.
        #expect(SnapshotText.sinceText(WidgetSnapshot.empty, now: Self.сейчас)
                == SnapshotText.sinceText(WidgetSnapshot.empty))
    }

    @Test("Снимок, записанный прежней версией, декодируется")
    func обратнаяСовместимость() throws {
        // Ровно то, что лежит в группе приложений после обновления:
        // JSON без трёх новых полей.
        var прежний = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(WidgetSnapshot.empty)) as? [String: Any] ?? [:]
        for поле in ["lastToiletAt", "lastToiletAtHome", "lastOutingEndedAt"] {
            прежний.removeValue(forKey: поле)
        }
        let данные = try JSONSerialization.data(withJSONObject: прежний)
        let снимок = try JSONDecoder().decode(WidgetSnapshot.self, from: данные)
        #expect(снимок.lastToiletAt == nil && снимок.lastOutingEndedAt == nil)
    }
}
