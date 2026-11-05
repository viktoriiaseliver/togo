import Testing
import Foundation
@testable import Togo

/// Ночь в счёте и «нет стула третий день» — вопросы Виктории 29.10.2026.
@Suite("Ночь и стул")
@MainActor
struct NightAndStoolTests {
    private let календарь = Calendar.current

    /// Сутки в полдень по местному времени — от них строятся примеры.
    private var полдень: Date {
        календарь.date(bySettingHour: 12, minute: 0, second: 0,
                       of: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    private func в(_ час: Int, _ минута: Int = 0, днейСпустя: Int = 0) -> Date {
        let день = календарь.date(byAdding: .day, value: днейСпустя, to: полдень)!
        return календарь.date(bySettingHour: час, minute: минута, second: 0, of: день)!
    }

    // MARK: Ночь

    @Test("Ночь 23–7 из промежутка 22:00 → 08:00 вычитается целиком")
    func ночьВычитается() {
        let ночь = NightWindow.standard
        #expect(ночь.awake(from: в(22), to: в(8, днейСпустя: 1)) == 2 * 3600)
    }

    @Test("Днём ночь не мешает")
    func деньБезНочи() {
        #expect(NightWindow.standard.awake(from: в(9), to: в(13)) == 4 * 3600)
    }

    @Test("Четыре бодрствующих часа после 22:30 кончаются в 10:30 утра")
    func прибавлениеЧерезНочь() {
        let конец = NightWindow.standard.adding(awake: 4 * 3600, to: в(22, 30))
        #expect(конец == в(10, 30, днейСпустя: 1))
    }

    @Test("Из середины ночи счёт начинается с её конца")
    func изНочи() {
        let конец = NightWindow.standard.adding(awake: 3600, to: в(2, днейСпустя: 1))
        #expect(конец == в(8, днейСпустя: 1))
    }

    @Test("Равные часы — ночи нет")
    func безНочи() {
        let ночь = NightWindow(startHour: 0, endHour: 0)
        #expect(ночь.awake(from: в(22), to: в(8, днейСпустя: 1)) == 10 * 3600)
    }

    // MARK: Стул

    private func запись(_ kind: LogKind, _ date: Date) -> LogEvent {
        LogEvent(kind: kind, date: date, authorName: "Виктория")
    }

    private func выход(_ исход: OutingOutcome?, _ date: Date) -> LogEvent {
        let e = запись(.outing, date)
        e.outcome = исход
        return e
    }

    @Test("Стула не отмечали никогда — молчим: здесь его не ведут")
    func никогдаНеВели() {
        let ленты = [выход(.urine, в(9)), выход(.urine, в(9, днейСпустя: 3))]
        #expect(StoolSilence.assess(ленты, now: в(12, днейСпустя: 3)) == .норма)
    }

    @Test("Сутки без стула — норма")
    func суткиНорма() {
        let ленты = [запись(.stool, в(9))]
        #expect(StoolSilence.assess(ленты, now: в(12, днейСпустя: 1)) == .норма)
    }

    @Test("Трое суток без стула при тихом дневнике — «не отмечали», а не тревога")
    func тихийДневник() {
        let стул = запись(.stool, в(9))
        #expect(StoolSilence.assess([стул], now: в(12, днейСпустя: 3)) == .неОтмечали(с: стул.date))
    }

    @Test("Трое суток без стула, а выходы с ответом отмечают — тревога")
    func ведутИНетСтула() {
        let стул = запись(.stool, в(9))
        let ленты = [стул,
                     выход(.urine, в(9, днейСпустя: 1)),
                     выход(.urine, в(18, днейСпустя: 1)),
                     выход(.urine, в(9, днейСпустя: 2)),
                     выход(OutingOutcome.none, в(9, днейСпустя: 3))]
        #expect(StoolSilence.assess(ленты, now: в(12, днейСпустя: 3)) == .тревога(с: стул.date))
    }

    @Test("Выходы БЕЗ ответа дневник ведущимся не делают")
    func безОтветаНеДоказательство() {
        let стул = запись(.stool, в(9))
        let ленты = [стул, выход(nil, в(9, днейСпустя: 1)), выход(nil, в(9, днейСпустя: 2))]
        #expect(StoolSilence.assess(ленты, now: в(12, днейСпустя: 3)) == .неОтмечали(с: стул.date))
    }

    @Test("Собака, которая ходит раз в два дня, тревоги на третьи сутки не получает")
    func своиПороги() {
        // Пять стульев через 48 ч — её норма; третьи сутки ей не повод.
        var ленты = (0..<5).map { запись(.stool, в(9, днейСпустя: $0 * 2)) }
        let последний = ленты.last!.date
        ленты += (9...11).map { выход(.urine, в(10, днейСпустя: $0)) }
        // Её пороги — ×1,5 и ×2 от 48 ч: вопрос с 72 ч, тревога с 96 ч.
        #expect(StoolSilence.assess(ленты, now: последний.addingTimeInterval(60 * 3600)) == .норма)
        #expect(StoolSilence.assess(ленты, now: последний.addingTimeInterval(80 * 3600))
                == .неОтмечали(с: последний))
    }
}
