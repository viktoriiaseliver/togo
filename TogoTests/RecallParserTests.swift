import Testing
import Foundation
import SwiftData
@testable import Togo

/// Дозапись словами: то, что человек правда пишет, а не то,
/// что удобно разбирать.
///
/// Примеры взяты из живой переписки с заказчицей 21.09.2026, когда
/// выяснилось, что две недели семья давала таблетки и кормила, не отмечая.
@Suite("Дозапись словами")
struct RecallParserTests {

    /// 21 сентября 2026 — та самая дата, от которой считаются «вчера»
    /// и даты без года.
    private var сегодня: Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 21; c.hour = 14
        return Calendar.current.date(from: c)!
    }

    private func день(_ d: Int, _ m: Int, _ y: Int = 2026) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    @Test("«13.09.26 был понос» — событие с датой и формой стула")
    func поносСДатой() throws {
        let строки = RecallParser.parse("13.09.26 был понос", today: сегодня)
        guard case .moment(let m) = строки.first else {
            Issue.record("не разобралось: \(строки)"); return
        }
        #expect(m.kind == .stool)
        #expect(m.at == день(13, 9))
        #expect(m.stool == .liquid)
    }

    @Test("Дата без года не уезжает в будущее")
    func датаБезГода() throws {
        // 31.12 в сентябре 2026 — это декабрь 2025, а не будущий.
        let строки = RecallParser.parse("31.12 был понос", today: сегодня)
        guard case .moment(let m) = строки.first else {
            Issue.record("не разобралось"); return
        }
        #expect(m.at == день(31, 12, 2025), "дата без года уехала в будущее")
    }

    @Test("«вчера дали таблетку» — доза со вчерашней датой")
    func вчера() throws {
        let строки = RecallParser.parse("вчера дали таблетку", today: сегодня)
        guard case .moment(let m) = строки.first else {
            Issue.record("не разобралось"); return
        }
        #expect(m.kind == .dose)
        #expect(m.at == день(20, 9))
    }

    @Test("«кормили 3 раза в день с 04.09 по 20.09» — период, а не 17 записей")
    func периодКормления() throws {
        let строки = RecallParser.parse("кормили 3 раза в день с 04.09 по 20.09", today: сегодня)
        guard case .period(let p) = строки.first else {
            Issue.record("период не распознан: \(строки)"); return
        }
        #expect(p.kind == .meal)
        #expect(p.from == день(4, 9))
        #expect(p.to == день(20, 9))
        #expect(p.timesPerDay == 3)
        #expect(p.days == 17, "период покрывает 17 суток включительно")
    }

    @Test("«гуляли каждый день по 4 часа с 04.09 по 20.09» — период с длительностью")
    func периодПрогулок() throws {
        let строки = RecallParser.parse(
            "гуляли примерно каждый день по 4 часа с 04.09 по 20.09", today: сегодня
        )
        guard case .period(let p) = строки.first else {
            Issue.record("период не распознан: \(строки)"); return
        }
        #expect(p.kind == .walk)
        #expect(p.durationSeconds == 4 * 3600)
        #expect(p.days == 17)
    }

    @Test("Две даты без «с … по» периодом не становятся")
    func двеДатыНеПериод() {
        let строки = RecallParser.parse("13.09 и 14.09 был понос", today: сегодня)
        if case .period = строки.first {
            Issue.record("две даты подряд приняты за период — это две записи")
        }
    }

    /// **Главное правило разбора.** Непонятая строка не исчезает
    /// и не угадывается: она возвращается человеку как есть.
    @Test("Непонятое возвращается человеку, а не проглатывается")
    func непонятоеНеМолчит() {
        let строки = RecallParser.parse("что-то было не так", today: сегодня)
        #expect(строки.count == 1)
        guard case .notUnderstood(let текст) = строки.first else {
            Issue.record("строку проглотили или угадали: \(строки)"); return
        }
        #expect(текст == "что-то было не так", "текст обязан вернуться дословно")
    }

    @Test("Вид есть, даты нет — тоже непонятое, а не «сегодня»")
    func безДатыНеСегодня() {
        let строки = RecallParser.parse("был понос", today: сегодня)
        guard case .notUnderstood = строки.first else {
            Issue.record("дату подставили за человека: \(строки)"); return
        }
    }

    @Test("Несколько строк разбираются по отдельности")
    func многострочник() {
        let строки = RecallParser.parse(
            """
            13.09.26 был понос
            кормили 3 раза в день с 04.09 по 20.09
            непонятная строка
            """,
            today: сегодня
        )
        #expect(строки.count == 3)
        if case .moment = строки[0] {} else { Issue.record("первая строка не событие") }
        if case .period = строки[1] {} else { Issue.record("вторая строка не период") }
        if case .notUnderstood = строки[2] {} else { Issue.record("третья строка угадана") }
    }

    @Test("Период нельзя считать как момент — статистика обязана знать")
    func периодНеМомент() {
        #expect(RecordOrigin.period.countsAsMoment == false)
        #expect(RecordOrigin.parsed.countsAsMoment)
        #expect(RecordOrigin.logged.countsAsMoment)
    }

    @Test("Запись по умолчанию — отмеченная в моменте")
    func происхождениеПоУмолчанию() {
        let event = LogEvent(kind: .meal, date: Date(), authorName: "Вика")
        #expect(event.origin == .logged)
        #expect(!event.isRecalled)

        event.origin = .parsed
        #expect(event.isRecalled)
        #expect(event.originRaw == "parsed", "происхождение обязано пережить хранение")
    }
}

/// Разложение периода по дням и запись в дневник.
///
/// Решение заказчицы 21.09.2026: период не остаётся одной непрозрачной
/// строкой — он раскладывается по дням, каждый со своей датой
/// и описанием. Час при этом не подставляется ничем.
@Suite("Дозапись по дням")
@MainActor
struct RecallByDayTests {

    private func контекст() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    private var сегодня: Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 21; c.hour = 14
        return Calendar.current.date(from: c)!
    }

    @Test("Период раскладывается по одному дню на сутки")
    func поДням() throws {
        let строки = RecallParser.parse(
            "гуляли каждый день по 4 часа с 04.09 по 20.09", today: сегодня
        )
        guard case .period(let p) = строки.first else { Issue.record("не период"); return }
        let дни = p.byDay()
        #expect(дни.count == 17)
        #expect(дни.allSatisfy { $0.kind == .walk })
        #expect(дни.allSatisfy { $0.durationSeconds == 4 * 3600 })
    }

    @Test("У дня есть дата и НЕТ выдуманного часа")
    func часНеВыдуман() throws {
        let строки = RecallParser.parse("кормили с 04.09 по 06.09", today: сегодня)
        guard case .period(let p) = строки.first else { Issue.record("не период"); return }
        let calendar = Calendar.current
        for день in p.byDay() {
            #expect(calendar.component(.hour, from: день.day) == 0,
                    "часу неоткуда взяться: он не известен")
            #expect(день.day == calendar.startOfDay(for: день.day))
        }
    }

    @Test("Снятые дни не пишутся, описание доезжает до записи")
    func правкаЧеловеком() throws {
        let (context, dog) = try контекст()
        let строки = RecallParser.parse("кормили с 04.09 по 06.09", today: сегодня)
        guard case .period(let p) = строки.first else { Issue.record("не период"); return }

        var дни = p.byDay()
        дни[1].isExcluded = true                     // во второй день не кормили
        дни[0].note = "полпорции, не доел"           // своими словами

        let итог = RecallWriter.write(дни, for: dog, author: "Вика",
                                      origin: .parsed, existing: [], context: context)
        #expect(итог.written == 2)
        #expect(итог.skipped == 1)

        let записи = dog.events.sorted { $0.date < $1.date }
        #expect(записи.count == 2)
        #expect(записи[0].note == "полпорции, не доел")
        #expect(записи[0].origin == .parsed)
        #expect(записи[0].isRecalled)
        #expect(записи[0].isDayOnly, "час неизвестен — это обязано быть записано")
        #expect(записи[0].enteredAt != nil, "«когда записали» обязано отличаться от «когда было»")
    }

    @Test("Повторный разбор того же письма историю не удваивает")
    func безДублей() throws {
        let (context, dog) = try контекст()
        let строки = RecallParser.parse("кормили с 04.09 по 06.09", today: сегодня)
        guard case .period(let p) = строки.first else { Issue.record("не период"); return }
        let дни = p.byDay()

        _ = RecallWriter.write(дни, for: dog, author: "Вика",
                               origin: .parsed, existing: [], context: context)
        let второй = RecallWriter.write(дни, for: dog, author: "Вика",
                                        origin: .parsed, existing: dog.events, context: context)
        #expect(второй.written == 0)
        #expect(второй.duplicates.count == 3)
        #expect(dog.events.count == 3, "две недели истории удвоились")
    }

    @Test("Выгрузка врачу: пометок у строк нет, в конце одна строка числом")
    func строкаВыгрузки() throws {
        let (context, dog) = try контекст()
        let обычная = LogEvent(kind: .meal, date: Date(), authorName: "Вика")
        обычная.dog = dog
        context.insert(обычная)

        #expect(RecallWriter.footnote(for: [обычная]) == nil,
                "по памяти ничего не вносили — и строки быть не должно")

        let строки = RecallParser.parse("кормили с 04.09 по 06.09", today: сегодня)
        guard case .period(let p) = строки.first else { Issue.record("не период"); return }
        _ = RecallWriter.write(p.byDay(), for: dog, author: "Вика",
                               origin: .parsed, existing: [], context: context)

        let подпись = RecallWriter.footnote(for: dog.events)
        #expect(подпись?.contains("3") == true)
        #expect(подпись?.contains("по памяти") == true)
        #expect(dog.events.allSatisfy { $0.note == nil || !$0.note!.contains("памят") },
                "пометка не должна течь в сами записи — врач читает одну таблицу")
    }
}

/// Статистика и дозапись.
///
/// Дозапись знает день и не знает часа. Всё, что считается по часам,
/// обязано её пропускать — иначе приложение соберёт вывод из данных,
/// которых не было.
@Suite("Ритм и дозапись")
struct RhythmWithRecalledTests {

    private func день(_ d: Int, час: Int = 0) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = d; c.hour = час
        return Calendar.current.date(from: c)!
    }

    private func выход(_ date: Date, dayOnly: Bool) -> LogEvent {
        let e = LogEvent(kind: .walk, date: date, authorName: "Вика")
        e.isDayOnly = dayOnly
        if dayOnly { e.origin = .parsed }
        return e
    }

    @Test("«Обычное время» не собирается из полуночей дозаписи")
    func обычноеВремяНеПолночь() {
        let события = [
            выход(день(18, час: 9), dayOnly: false),
            выход(день(18, час: 19), dayOnly: false),
            выход(день(19, час: 9), dayOnly: false),
            выход(день(19, час: 19), dayOnly: false),
            // Дозапись: день известен, час — нет.
            выход(день(15), dayOnly: true),
            выход(день(16), dayOnly: true),
        ]
        let ритм = WalkRhythmAnalyzer.rhythm(events: события, now: день(20, час: 12))
        #expect(!ритм.usualTimes.contains(0),
                "полночь дозаписи попала в «обычное время» — вывод собран из несуществующих часов")
    }

    @Test("Дни дозаписи в счёт дней входят: человек помнит, что гуляли")
    func дниСчитаются() {
        let точные = [выход(день(18, час: 9), dayOnly: false)]
        let сДозаписью = точные + [выход(день(15), dayOnly: true), выход(день(16), dayOnly: true)]

        let без = WalkRhythmAnalyzer.rhythm(events: точные, now: день(20, час: 12))
        let с = WalkRhythmAnalyzer.rhythm(events: сДозаписью, now: день(20, час: 12))
        #expect(с.days > без.days, "дозаписанные дни обязаны считаться днями")
    }

    /// Приблизительная дозапись ритму не учитель.
    ///
    /// Два теста, а не один, и они делят то, что выглядит одним:
    /// «дозапись» — не ось. Ось — приблизительность, и точная дозапись
    /// по ту же сторону, что обычная запись.
    private func периодВыходов(_ date: Date) -> LogEvent {
        let e = LogEvent(kind: .walk, date: date, authorName: "Вика")
        e.isDayOnly = true
        e.origin = .period
        return e
    }

    @Test("Период ритму не учитель: «примерно четырежды» в медиану не идёт")
    func периодМимоРитма() {
        let точные = [выход(день(18, час: 9), dayOnly: false),
                      выход(день(18, час: 19), dayOnly: false)]
        // Восемнадцать дней «выходили примерно четырежды в день».
        let сПериодами = точные + (1...18).flatMap { d in
            (0..<4).map { _ in периодВыходов(день(d)) }
        }

        let без = WalkRhythmAnalyzer.rhythm(events: точные, now: день(20, час: 12))
        let с = WalkRhythmAnalyzer.rhythm(events: сПериодами, now: день(20, час: 12))

        #expect(с.outingsPerDay == без.outingsPerDay, """
            «обычно \(с.outingsPerDay) выхода в день» собрано из того,
            что человек помнит ПРИБЛИЗИТЕЛЬНО. Макет требует обратного:
            «„Примерно“ — … ритм „Просится“ по ним не учится».
            Правило живёт в `RecordOrigin.countsAsMoment`, и читателя
            у него не было до 08.10 — только три теста.
            """)
        #expect(с.days == без.days, "приблизительные дни вошли в счёт дней ритма")
        #expect(с.isReliable == без.isReliable, """
            приблизительные записи сделали ритм «надёжным»: порог
            `minimumDays` пройден днями, которых никто не измерял.
            """)
    }

    @Test("Точная дозапись ритму учитель — и это другая сторона того же правила")
    func точнаяДозаписьСчитается() {
        // `.parsed` и `.recalled` — момент был, человек его помнит.
        // Разделять их с `.period` и есть предмет `countsAsMoment`.
        let точные = [выход(день(18, час: 9), dayOnly: false)]
        let сДозаписью = точные + [выход(день(15), dayOnly: true),
                                   выход(день(16), dayOnly: true)]

        let без = WalkRhythmAnalyzer.rhythm(events: точные, now: день(20, час: 12))
        let с = WalkRhythmAnalyzer.rhythm(events: сДозаписью, now: день(20, час: 12))

        #expect(с.days > без.days, """
            фильтр по приблизительности выкинул и ТОЧНУЮ дозапись.
            Это другая ось: `isDayOnly` говорит «часа не знаю»,
            `countsAsMoment` — «события не было как момента».
            Снести их в одну — потерять дни, которые человек помнит.
            """)
    }

    @Test("Промежутки «дома» из полуночей не считаются")
    func промежуткиТолькоПоТочным() {
        let только = [выход(день(15), dayOnly: true), выход(день(16), dayOnly: true),
                      выход(день(17), dayOnly: true)]
        let ритм = WalkRhythmAnalyzer.rhythm(events: только, now: день(20, час: 12))
        #expect(ритм.averageIndoors == 0, "среднее «дома» посчитано по выдуманным часам")
        #expect(ритм.longestIndoors == 0)
    }
}
