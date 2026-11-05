import Testing
import Foundation
@testable import Togo

/// `ToiletClock` — откуда герой «Сегодня» считает время с 29.10.2026.
///
/// Каждое правило из головы `ToiletClock.swift` — отдельным тестом:
/// таблица там читается как замер, и без теста она им не является.
@Suite("Последний туалет")
@MainActor
struct ToiletClockTests {
    /// Полдень по местному календарю: счёт стула идёт по дням, и
    /// полночь в часовом поясе стенда не должна разрезать пример.
    private let сейчас = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0,
                                               of: Date(timeIntervalSince1970: 1_800_000_000))!

    private func запись(_ kind: LogKind, минутНазад: Int) -> LogEvent {
        LogEvent(kind: kind, date: сейчас.addingTimeInterval(-Double(минутНазад) * 60),
                 authorName: "Виктория")
    }

    private func выход(_ исход: OutingOutcome?, минутНазад: Int) -> LogEvent {
        let e = запись(.outing, минутНазад: минутНазад)
        e.outcome = исход
        return e
    }

    @Test("Выход «не сходил» счёт не сбрасывает — туалет остаётся прежним")
    func неСходилНеТуалет() {
        let пописал = выход(.urine, минутНазад: 300)
        let пусто = выход(OutingOutcome.none, минутНазад: 30)
        let момент = ToiletClock.last([пописал, пусто], male: false, now: сейчас)
        #expect(момент?.когда == пописал.date)
        #expect(момент?.где == .улица)
    }

    @Test("Лужа в доме — туалет, и он дома")
    func лужаДомаТуалет() {
        let лужа = запись(.incident, минутНазад: 20)
        лужа.incidentKind = .puddle
        let момент = ToiletClock.last([выход(.urine, минутНазад: 200), лужа], male: false, now: сейчас)
        #expect(момент == .init(когда: лужа.date, где: .дом))
    }

    @Test("Рвота туалетом не считается")
    func рвотаНеТуалет() {
        let рвота = запись(.incident, минутНазад: 10)
        рвота.incidentKind = .vomit
        #expect(ToiletClock.last([рвота], male: false, now: сейчас) == nil)
    }

    @Test("Выход без ответа: у кобеля туалет, у суки — неизвестно")
    func кобельБезОтвета() {
        let безОтвета = выход(nil, минутНазад: 40)
        #expect(ToiletClock.last([безОтвета], male: true, now: сейчас)?.когда == безОтвета.date)
        #expect(ToiletClock.last([безОтвета], male: false, now: сейчас) == nil)
    }

    @Test("Прогулка кобеля считается мочой с КОНЦА прогулки")
    func прогулкаКобеляОтКонца() {
        let прогулка = запись(.walk, минутНазад: 90)
        прогулка.durationSeconds = 30 * 60
        let момент = ToiletClock.last([прогулка], male: true, now: сейчас)
        #expect(момент?.когда == прогулка.date.addingTimeInterval(30 * 60))
        #expect(ToiletClock.last([прогулка], male: false, now: сейчас) == nil)
    }

    @Test("Явное «не сходил» у кобеля — не туалет")
    func кобельНеСходил() {
        #expect(ToiletClock.last([выход(OutingOutcome.none, минутНазад: 5)], male: true, now: сейчас) == nil)
    }

    @Test("Запись из будущего не берётся")
    func будущееНеБерётся() {
        #expect(ToiletClock.last([выход(.urine, минутНазад: -30)], male: false, now: сейчас) == nil)
    }

    @Test("Стул за день: выход «стул» рядом с записью стула — один стул")
    func стулНеДвоится() {
        let ответ = выход(.both, минутНазад: 60)
        let форма = запись(.stool, минутНазад: 55)
        // Пять минут назад, а не десять, и это арифметика, а не вкус:
        // окно склейки `Diary.sameEmptyingWindow` = 45 минут, и граница
        // ВКЛЮЧАЮЩАЯ (`<=`). При «десяти» этот выход стоял от `формы`
        // ровно в 45 минутах (55 − 10) — то есть ТОЧНО на границе, —
        // склеивался с ней и в счёт не шёл. Тест говорил «вечерний
        // стул отдельный», а строил его на самом краю окна; ответ 2
        // был верным ответом продукта на неверную посылку теста.
        let вечерний = выход(.stool, минутНазад: 5)   // 55 − 5 = 50 мин > 45
        let кучка = запись(.incident, минутНазад: 30)
        кучка.incidentKind = .stoolIndoors
        // Кучка дома — ДРУГОЙ стул, даже рядом с выходом: склеивается
        // только ответ «как сходил» с формой для врача.
        #expect(ToiletClock.stoolCount([ответ, форма, вечерний, кучка], on: сейчас) == 3)
    }

    /// Граница окна склейки — включающая, и это держится тестом,
    /// а не памятью: на ней споткнулся тест выше.
    @Test("Выход «стул» ровно в окне склейки — тот же стул, за окном — другой")
    func границаОкнаСклейки() {
        let форма = запись(.stool, минутНазад: 50)
        // 50 − 5 = 45 минут: ровно окно. `<=` значит «тот же стул».
        let наГранице = выход(.stool, минутНазад: 5)
        #expect(ToiletClock.stoolCount([форма, наГранице], on: сейчас) == 1, """
            выход ровно в 45 минутах от записи стула обязан склеиться: \
            граница окна включающая (`abs(…) <= sameEmptyingWindow`).
            """)

        // На минуту дальше окна — уже другой стул.
        let заГраницей = выход(.stool, минутНазад: 4)   // 50 − 4 = 46 мин
        #expect(ToiletClock.stoolCount([форма, заГраницей], on: сейчас) == 2, """
            выход в 46 минутах — отдельное опорожнение, а не то же самое.
            """)
    }

    @Test("Туалет дома эпизода не поднимает, рвота — поднимает")
    func лужиНеЭпизод() {
        #expect(!IncidentKind.puddle.raisesEpisode)
        #expect(!IncidentKind.stoolIndoors.raisesEpisode)
        #expect(IncidentKind.vomit.raisesEpisode)
        #expect(IncidentKind.other.raisesEpisode)
    }
}
