import Testing
import Foundation
import SwiftData
@testable import Togo

/// Напоминания ставятся вперёд и говорят то же, что экран.
///
/// Заведено 29.10.2026 вместе с горизонтом доз, сводкой по дням, тихими
/// часами в планировщике и «Можно кормить» по `FeedingGate`. Очередь
/// уведомлений в модульном прогоне не существует, поэтому проверяется
/// то, что идёт В очередь: чистые функции `ReminderScheduler`, через
/// которые проходит каждый запрос. Сама постановка (`add`) здесь
/// не мерится — это граница, а не упущение: шов ровно тот же,
/// что у `планПартии` и `fastingEndText`.
///
/// Календарь прибит к одному поясу: доза на 21:00 обязана быть 21:00
/// у всякого, кто гонит прогон, а не у того, у кого пояс совпал.
@Suite("Напоминания вперёд")
@MainActor
struct НапоминанияВпередTests {

    private static let календарь: Calendar = {
        var к = Calendar(identifier: .gregorian)
        к.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return к
    }()

    /// 29.10.2026 в заданный час — день без перевода часов.
    private func момент(день: Int = 29, _ час: Int, _ минута: Int = 0) throws -> Date {
        try #require(Self.календарь.date(from: DateComponents(
            year: 2026, month: 10, day: день, hour: час, minute: минута)))
    }

    private func собака(часы: [Int], натощак: Int = 0) throws -> (ModelContext, Dog, Medication) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.isOnTreatment = true
        context.insert(dog)
        let схема = Medication(name: "Эутирокс", doseText: "50 мкг",
                               times: часы, fastingMinutes: натощак)
        схема.dog = dog
        context.insert(схема)
        try context.save()
        return (context, dog, схема)
    }

    // MARK: Тихие часы

    @Test("Тихие часы через полночь: вечер уезжает на утро следующего дня, ночь — на утро того же")
    func тихиеЧасыЧерезПолночь() throws {
        let к = Self.календарь
        let вечер = try момент(23, 40)
        let утроЗавтра = try момент(день: 30, 7)
        let ночь = try момент(5, 30)
        let утро = try момент(7)
        let полдень = try момент(12)
        #expect(ReminderScheduler.внеТихихЧасов(вечер, начало: 23, конец: 7, calendar: к) == утроЗавтра)
        #expect(ReminderScheduler.внеТихихЧасов(ночь, начало: 23, конец: 7, calendar: к) == утро)
        // Контроль: вне тихих часов момент не трогается.
        #expect(ReminderScheduler.внеТихихЧасов(полдень, начало: 23, конец: 7, calendar: к) == полдень)
        #expect(ReminderScheduler.внеТихихЧасов(утро, начало: 23, конец: 7, calendar: к) == утро,
                "07:00 — уже не тихий час: конец не входит в окно")
    }

    @Test("Начало, равное концу, — тихих часов нет вовсе")
    func равныеГраницы() throws {
        let поздно = try момент(23, 30)
        #expect(!Settings.тихийЛиЧас(23, начало: 23, конец: 23))
        #expect(ReminderScheduler.внеТихихЧасов(поздно, начало: 23, конец: 23,
                                                calendar: Self.календарь) == поздно)
    }

    // MARK: Горизонт доз

    @Test("Доза ставится на сегодня и ещё два дня, а не только на заведённые отметки")
    func горизонтТриДня() throws {
        let (_, dog, _) = try собака(часы: [9 * 60, 21 * 60])
        // Отметок нет ни одной: `ensureDoses` никто не звал — ровно
        // случай человека, не открывшего «Сегодня».
        let сейчас = try момент(10)
        let последняя = try момент(день: 31, 22)
        let ступени = ReminderScheduler.ступениДоз(dog: dog, now: сейчас,
                                                   calendar: Self.календарь)
        // Сегодня: 09:00 уже прошла целиком (t+60 = 10:00 не позже «сейчас»),
        // 21:00 — три ступени. Завтра и послезавтра — по шесть.
        #expect(ступени.count == 3 + 6 + 6, "ступеней \(ступени.count): \(ступени.map(\.id))")
        #expect(ступени.map(\.когда) == ступени.map(\.когда).sorted(),
                "ступени не по времени — обрезка с хвоста выбросила бы не те")
        #expect(ступени.last?.когда == последняя)
    }

    @Test("Запрос на завтра и будущая отметка — один и тот же идентификатор")
    func идентификаторСовпадаетСОтметкой() throws {
        let (_, dog, схема) = try собака(часы: [9 * 60])
        let завтра = try момент(день: 30, 9)
        let сейчас = try момент(10)
        let ступени = ReminderScheduler.ступениДоз(dog: dog, now: сейчас,
                                                   calendar: Self.календарь)
        let ожидаемый = "dose-\(DoseRecord.устойчивыйID(medication: схема.id, scheduledAt: завтра).uuidString)-t-10"
        #expect(ступени.contains { $0.id == ожидаемый }, """
            запроса \(ожидаемый) нет. Без совпадения пересборка после \
            `ensureDoses` поставила бы второй запрос на ту же дозу, \
            а `cancelDose(отметка)` не снял бы первый.
            """)
    }

    @Test("Отмеченная доза не звонит, пауза и выключенное лечение снимают всё")
    func неждущееНеСтавится() throws {
        let (context, dog, схема) = try собака(часы: [21 * 60])
        let сегодня = try момент(21)
        let отметка = DoseRecord(scheduledAt: сегодня)
        отметка.id = DoseRecord.устойчивыйID(medication: схема.id, scheduledAt: сегодня)
        отметка.givenAt = сегодня
        отметка.medication = схема
        context.insert(отметка)
        try context.save()

        let сейчас = try момент(10)
        #expect(ReminderScheduler.ступениДоз(dog: dog, now: сейчас, calendar: Self.календарь).count == 6,
                "данная сегодня доза всё ещё ставит напоминания")

        схема.isPaused = true
        #expect(ReminderScheduler.ступениДоз(dog: dog, now: сейчас, calendar: Self.календарь).isEmpty)
        схема.isPaused = false
        dog.isOnTreatment = false
        #expect(ReminderScheduler.ступениДоз(dog: dog, now: сейчас, calendar: Self.календарь).isEmpty)
    }

    @Test("Доза в тихие часы не сдвигается: 23:00 остаётся 23:00")
    func дозаНеГлушится() throws {
        let (_, dog, _) = try собака(часы: [23 * 60])
        let сейчас = try момент(10)
        let заДесять = try момент(22, 50)
        let ступени = ReminderScheduler.ступениДоз(dog: dog, now: сейчас,
                                                   calendar: Self.календарь)
        #expect(ступени.first?.когда == заДесять)
    }

    // MARK: «Можно кормить»

    @Test("«Можно кормить» молчит, когда в тот момент экран скажет «не кормить»")
    func можноКормитьПоПравилуЭкрана() throws {
        let (context, dog, утро) = try собака(часы: [7 * 60], натощак: 60)
        let дали = try момент(7)
        let отметка = DoseRecord(scheduledAt: дали)
        отметка.givenAt = дали
        отметка.medication = утро
        context.insert(отметка)
        // Второй препарат с окном ДО дозы 08:30 — оно открыто с 07:30.
        let второй = Medication(name: "Второй", doseText: "1", times: [8 * 60 + 30])
        второй.fastingBeforeMinutes = 60
        второй.dog = dog
        context.insert(второй)
        try context.save()

        // В 08:00 окно «после» первого кончается, а окно «до» второго
        // уже идёт: экран говорит «не кормить до 08:30». Прежний расчёт
        // (`fastingEnds`) звонил бы «Можно кормить» в 08:00.
        let сейчас = try момент(7, 30)
        let конецОкна = try момент(8)
        #expect(ReminderScheduler.моментМожноКормить(
            лекарства: dog.medications, now: сейчас,
            начало: 23, конец: 7, calendar: Self.календарь) == nil)

        // Контроль: без второго препарата момент есть, и это 08:00.
        второй.isPaused = true
        #expect(ReminderScheduler.моментМожноКормить(
            лекарства: dog.medications, now: сейчас,
            начало: 23, конец: 7, calendar: Self.календарь) == конецОкна)
    }

    @Test("Конец окна в тихие часы уезжает на их конец")
    func можноКормитьПослеТихихЧасов() throws {
        let (context, dog, схема) = try собака(часы: [22 * 60 + 30], натощак: 60)
        let дали = try момент(22, 30)
        let отметка = DoseRecord(scheduledAt: дали)
        отметка.givenAt = дали
        отметка.medication = схема
        context.insert(отметка)
        try context.save()

        let сейчас = try момент(22, 45)
        let утро = try момент(день: 30, 7)
        #expect(ReminderScheduler.моментМожноКормить(
            лекарства: dog.medications, now: сейчас,
            начало: 23, конец: 7, calendar: Self.календарь) == утро)
    }

    // MARK: Сводка

    @Test("Сводка называется днём, когда придёт")
    func идентификаторСводки() throws {
        let утро = try момент(8)
        #expect(ReminderScheduler.idСводки(утро, calendar: Self.календарь) == "brief-20261029")
    }
}
