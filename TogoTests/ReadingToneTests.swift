import Testing
import Foundation
@testable import Togo

/// Один тон на всё показание «Сегодня». Решение Виктории 22.10.2026,
/// источник — `design_handoff_togo_ios28`, порядок снят с прототипа
/// (`Togo-RU.dc.html:597`).
///
/// Проверяется **порядок**, а не только исходы: состояний пятнадцать,
/// и верными одновременно бывают пять-шесть, так что ценность набора —
/// в парах «верно сразу два, что победит».
@Suite("Показание · тон и очередь состояний")
struct ReadingToneTests {

    @Test("Каждый тон достижим, и их ровно шесть")
    func everyToneReachable() {
        // Первой — проверка, что набору было что проверять: без неё
        // остальные зеленели бы на урезанном перечислении. Ровно так же
        // устроен первый тест `PosterModeTests`.
        #expect(ReadingTone.allCases.count == 6)

        var s = TodayStateRouter.DayState()
        #expect(TodayStateRouter.tone(s) == .normal)

        s = .init(); s.isFasting = true
        #expect(TodayStateRouter.tone(s) == .fasting)

        s = .init(); s.isDoseDue = true
        #expect(TodayStateRouter.tone(s) == .dose)

        s = .init(); s.isAlarm = true
        #expect(TodayStateRouter.tone(s) == .alarm)

        s = .init(); s.isNight = true
        #expect(TodayStateRouter.tone(s) == .night)

        s = .init(); s.isWalking = true
        #expect(TodayStateRouter.tone(s) == .walk)
    }

    @Test("Тревога сильнее дозы, натощак и запаса")
    func alarmWins() {
        var s = TodayStateRouter.DayState()
        s.isAlarm = true
        s.isDoseDue = true
        s.isFasting = true
        s.isStockLow = true
        #expect(TodayStateRouter.top(s) == .alarm)
        #expect(TodayStateRouter.tone(s) == .alarm)
    }

    /// **Это расхождение с `PosterMode`, и тест стоит здесь, чтобы оно
    /// было громким.**
    ///
    /// `PosterModeTests.nightWinsOverDose` утверждает обратное — и это
    /// по-прежнему верно для плаката, виджета и «острова». Два решения
    /// с адресами противоречат друг другу:
    ///
    /// ```
    /// тихие часы, записанное решение   ночь гасит цвет: «свет в лицо»
    /// хендофф, Виктория 22.10.2026     ночь — запасной исход, ниже всех
    /// ```
    ///
    /// Пока оба живы, у каждого свой тип и свой тест. Сольются они
    /// решением Виктории, а не правкой кода: **вопрос в отчёте назван.**
    @Test("Ночь НЕ гасит дозу — в отличие от PosterMode")
    func ночьНеГаситДозу() {
        var s = TodayStateRouter.DayState()
        s.isDoseDue = true
        s.isNight = true
        #expect(TodayStateRouter.top(s) == .dose)
        #expect(TodayStateRouter.tone(s) == .dose)

        // Контроль в ту же команду и подверженный тому же отказу:
        // если бы `isNight` не читался вовсе, ночь не победила бы
        // и там, где она обязана победить, — а она обязана, когда
        // выше неё нет ничего.
        var одна = TodayStateRouter.DayState()
        одна.isNight = true
        #expect(TodayStateRouter.top(одна) == .night)

        // И прямое сравнение с прежним правилом — на тех же входах.
        // Расхождение видно в одной строке, а не выводится из двух
        // наборов.
        #expect(PosterMode.mode(.init(isDoseDue: true, isNight: true)) == .quiet)
    }

    @Test("Выход перебивает всё: человек уже смотрит на таймер")
    func выходПеребиваетВсё() {
        var s = TodayStateRouter.DayState()
        s.isWalking = true
        s.isAlarm = true
        s.isDoseDue = true
        #expect(TodayStateRouter.top(s) == .walk)
        // И очередь при этом ровно одна длиной: во время выхода ни
        // «Дальше», ни пилюли быть не может.
        #expect(TodayStateRouter.second(s) == nil)
        #expect(TodayStateRouter.third(s) == nil)
    }

    @Test("Второе уезжает в «Дальше», третье — пилюлей")
    func второеИТретье() {
        var s = TodayStateRouter.DayState()
        s.isAlarm = true
        s.isDoseDue = true
        s.isFasting = true
        s.isOffline = true

        #expect(TodayStateRouter.top(s) == .alarm)
        #expect(TodayStateRouter.second(s) == .dose)
        #expect(TodayStateRouter.third(s) == .fasting)

        // Четвёртое никуда не уезжает — показывать его негде, и это
        // не потеря: хендофф разрешает пилюлю «≤ 1» и «Дальше» одну.
        #expect(TodayStateRouter.states(s).count == 4)
    }

    @Test("Одно состояние — ни «Дальше», ни пилюли")
    func одноСостояние() {
        var s = TodayStateRouter.DayState()
        s.isDoseDue = true
        #expect(TodayStateRouter.second(s) == nil)
        #expect(TodayStateRouter.third(s) == nil)
    }

    /// Запасные исходы идут **ниже** всех названных состояний, и порядок
    /// между собой у них свой: нет записей → давно не выходили → ночь →
    /// обычно.
    @Test("Запасные исходы: первый день, тишина, ночь, обычно")
    func запасныеИсходы() {
        var s = TodayStateRouter.DayState()
        s.hasNoEntries = true
        s.isSilent = true
        s.isNight = true
        #expect(TodayStateRouter.top(s) == .first)

        s = .init(); s.isSilent = true; s.isNight = true
        #expect(TodayStateRouter.top(s) == .silence)

        s = .init(); s.isNight = true
        #expect(TodayStateRouter.top(s) == .night)

        #expect(TodayStateRouter.top(.init()) == .normal)

        // Запасной исход гасится ЛЮБЫМ названным состоянием — в том
        // числе самым тихим из них, «нет сети».
        s = .init(); s.hasNoEntries = true; s.isOffline = true
        #expect(TodayStateRouter.top(s) == .offline)
    }

    /// Тонов шесть, состояний пятнадцать — и это решение, а не упущение.
    /// Сторож на случай, если кто-то заведёт состоянию свой цвет мимо
    /// правила «не размазывать цвета по экранам».
    @Test("Поездка, ситтер, запас и нет сети цвета НЕ меняют")
    func тихиеСостоянияНеКрасятЭкран() {
        for состояние in [TodayState.episode, .trip, .sitter, .away, .stock, .offline] {
            #expect(состояние.tone == .normal,
                    "\(состояние.rawValue) не должно красить панель")
        }

        // Контроль: те, что красить ОБЯЗАНЫ, — красят. Без него набор
        // зеленел бы и на `tone`, возвращающем `.normal` всегда.
        #expect(TodayState.alarm.tone == .alarm)
        #expect(TodayState.threshold.tone == .alarm)
        #expect(TodayState.dose.tone == .dose)
        #expect(TodayState.fasting.tone == .fasting)
    }

    /// Белая главная кнопка — решение Виктории 22.10.2026 («Кино»
    /// заменяет Graphite целиком). Но белая она в **обычном**
    /// состоянии: у дозы и тревоги цвет свой.
    @Test("Цвет главной кнопки берётся у тона, а не стоит безусловно")
    func главнаяКнопкаБерётЦветУТона() {
        #expect(ReadingTone.dose.tintsPrimaryButton)
        #expect(ReadingTone.alarm.tintsPrimaryButton)

        // Остальные четыре — белая с текстом #111.
        #expect(!ReadingTone.normal.tintsPrimaryButton)
        #expect(!ReadingTone.fasting.tintsPrimaryButton)
        #expect(!ReadingTone.night.tintsPrimaryButton)
        #expect(!ReadingTone.walk.tintsPrimaryButton)
    }

    @Test("Панель красят только три тона, фото приглушает только ночь")
    func панельИФото() {
        #expect(ReadingTone.fasting.paintsPanel)
        #expect(ReadingTone.dose.paintsPanel)
        #expect(ReadingTone.alarm.paintsPanel)
        #expect(!ReadingTone.normal.paintsPanel)
        #expect(!ReadingTone.night.paintsPanel)
        #expect(!ReadingTone.walk.paintsPanel)

        #expect(ReadingTone.night.dimsPhoto)
        #expect(ReadingTone.allCases.filter(\.dimsPhoto).count == 1)
    }
}
