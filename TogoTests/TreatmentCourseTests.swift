import Testing
import Foundation
import SwiftData
@testable import Togo

/// «Здоровье» — слой-эпизод поверх обычного ухода: приходит с курсом
/// и уходит вместе с ним, ничего не унося из истории.
@Suite("Курс лечения")
@MainActor
struct TreatmentCourseTests {

    private func setup() throws -> (ModelContext, Dog, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 21 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, dog, medication)
    }

    @Test("Курс идёт — вкладка есть")
    func activeWhileOnTreatment() throws {
        let (_, dog, _) = try setup()
        #expect(TreatmentCourse.isActive(dog))
    }

    // Имя до 20.10.2026 было «Курс завершён — вкладка прячется»: тело мерило
    // `isActive`, а имя обещало про вкладку, которая с 08.10 держится правом
    // и не прячется. Сторож по имени врал при верном теле.
    @Test("Курс завершён — схема перестаёт быть активной")
    func finishDeactivatesCourse() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)
        #expect(!TreatmentCourse.isActive(dog))
    }

    @Test("Препараты не удаляются, а помечаются отменёнными")
    func medicationsAreCancelledNotDeleted() throws {
        let (context, dog, medication) = try setup()
        let day = Date()
        TreatmentCourse.finish(dog, at: day, by: "Вика", context: context)

        #expect(dog.medications.count == 1)
        #expect(medication.cancelledAt == day)
        #expect(medication.isPaused)
        #expect(medication.cancelledNote?.isEmpty == false)
    }

    @Test("Отметки прошлых доз остаются, будущие уходят")
    func pastDosesSurvive() throws {
        let (context, dog, medication) = try setup()
        let now = Date()

        let given = DoseRecord(scheduledAt: now.addingTimeInterval(-3600))
        given.givenAt = now.addingTimeInterval(-3500)
        given.medication = medication
        context.insert(given)

        let future = DoseRecord(scheduledAt: now.addingTimeInterval(6 * 3600))
        future.medication = medication
        context.insert(future)
        try context.save()

        TreatmentCourse.finish(dog, at: now, by: "Вика", context: context)

        #expect(medication.doses.count == 1)
        #expect(medication.doses.first?.isGiven == true)
    }

    @Test("Пропущенная доза не считается мусором и остаётся")
    func skippedDoseSurvives() throws {
        let (context, dog, medication) = try setup()
        let now = Date()

        let skipped = DoseRecord(scheduledAt: now.addingTimeInterval(2 * 3600))
        skipped.skippedAt = now
        skipped.skippedBy = "Наталья"
        skipped.medication = medication
        context.insert(skipped)
        try context.save()

        TreatmentCourse.finish(dog, at: now, by: "Вика", context: context)
        #expect(medication.doses.count == 1)
        #expect(medication.doses.first?.isSkipped == true)
    }

    @Test("Курс можно вернуть — препараты оживают")
    func resumeRestoresMedications() throws {
        let (context, dog, medication) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)
        TreatmentCourse.resume(dog, context: context)

        #expect(TreatmentCourse.isActive(dog))
        #expect(medication.cancelledAt == nil)
        #expect(!medication.isPaused)
        #expect(medication.cancelledNote == nil)
    }

    @Test("Перед подтверждением названы препараты, которые уйдут")
    func farewellNamesMedications() throws {
        let (_, dog, _) = try setup()
        let text = TreatmentCourse.farewell(dog)
        #expect(text.contains("Апоквел"))
        #expect(text.contains("истории"))
    }

    @Test("Уже отменённый препарат в прощание не попадает")
    func farewellSkipsCancelled() throws {
        let (context, dog, medication) = try setup()
        medication.cancelledAt = Date()
        try context.save()

        #expect(!TreatmentCourse.farewell(dog).contains("Апоквел"))
        #expect(TreatmentCourse.activeMedications(dog).isEmpty)
    }

    @Test("После завершения курса новых доз на день не заводится")
    func noDosesAfterFinish() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.finish(dog, by: "Вика", context: context)

        let created = DoseScheduler.ensureDoses(for: dog, on: Date(), context: context)
        #expect(created == 0)
    }

    /// **Правка времени приёма не должна оставлять сироту.**
    ///
    /// 21.09.2026 на телефоне красным горело «Доза 21:30 не отмечена»
    /// в 14:05 — за семь часов ДО дозы. По формуле так быть не может:
    /// `escalationStage` для будущей дозы даёт 0. Значит дело в данных,
    /// и вот откуда они берутся: `ensureDoses` заводит отметки по
    /// текущему `medication.times`, а при правке времени **старая
    /// отметка остаётся** — ничья, никем не отмечаемая, и через час
    /// после своего часа она просрочена навсегда.
    ///
    /// Цена высокая не в часах, а в доверии: красный у Того несёт
    /// лекарства, и ложная тревога обесценивает его весь.
    @Test("Правка времени приёма не оставляет просроченную сироту")
    func editingScheduleLeavesNoOrphanDose() throws {
        let (context, dog, medication) = try setup()
        let calendar = Calendar.current
        let день = calendar.startOfDay(for: Date())

        medication.times = [13 * 60]
        try context.save()
        #expect(DoseScheduler.ensureDoses(for: dog, on: день, context: context) == 1)

        // Человек передумал: приём не в 13:00, а в 21:30.
        medication.times = [21 * 60 + 30]
        try context.save()
        DoseScheduler.ensureDoses(for: dog, on: день, context: context)

        let времена = medication.doses
            .filter { calendar.isDate($0.scheduledAt, inSameDayAs: день) }
            .map { calendar.component(.hour, from: $0.scheduledAt) }
            .sorted()
        #expect(
            времена == [21],
            "осталась отметка на час, которого в расписании больше нет: \(времена) — через час она станет «не отмечена» и будет гореть красным вечно"
        )
    }

    /// **Красное «не отмечена» не должно гореть вечно.**
    ///
    /// 21.09.2026, уже ПОСЛЕ починки сироты выше, на телефоне снова
    /// висело «Доза 21:30 не отмечена». Причина другая и лежала в двух
    /// местах сразу:
    ///
    /// 1. Выбор дозы перебирал `dog.medications.flatMap(\.doses)` без
    ///    ограничения по дню. Неотмеченная доза любого прошлого дня даёт
    ///    третью стадию навсегда и выигрывает как самая ранняя.
    /// 2. `Fmt.clock` печатает только часы и минуты. Позавчерашние 21:30
    ///    читаются как сегодняшние — и в 18:25 это выглядит тревогой
    ///    о дозе, до которой ещё три часа.
    ///
    /// Вместе это значило: один раз не отметил — и красный больше
    /// не погаснет никогда.
    @Test("Неотмеченная доза прошлого дня не тревожит сегодня")
    func yesterdaysDoseDoesNotAlarmToday() throws {
        let (context, dog, medication) = try setup()
        let calendar = Calendar.current
        let сейчас = calendar.date(minuteOfDay: 18 * 60 + 25,
                                   on: calendar.startOfDay(for: Date()))
        let вчера = calendar.date(byAdding: .day, value: -1, to: сейчас)!

        // Вчерашняя доза на 21:30, которую никто не отметил.
        let старая = DoseRecord(scheduledAt: calendar.date(
            minuteOfDay: 21 * 60 + 30, on: calendar.startOfDay(for: вчера)))
        старая.medication = medication
        context.insert(старая)
        try context.save()

        #expect(старая.escalationStage(at: сейчас) == 3,
                "сама по себе она просрочена — это верно и не оспаривается")
        #expect(
            DoseScheduler.alarmingDose(among: dog.medications, now: сейчас) == nil,
            "вчерашняя доза подняла тревогу на сегодня: это история и отчёт врачу, а не тревога сейчас"
        )
    }

    /// **Пропуск — это решение, и он обязан гасить тревогу.**
    ///
    /// `escalationStage` обнуляла лестницу для принятой и отменённой
    /// дозы, но не для пропущенной. То есть человек нажимал
    /// «пропустить», запись о решении появлялась — а красное
    /// «не отмечена» продолжало гореть. Лестница нужна ровно там, где
    /// решения ещё нет.
    @Test("Пропущенная доза не считается непринятой")
    func skippedDoseStopsEscalating() throws {
        let (context, dog, medication) = try setup()
        let calendar = Calendar.current
        let день = calendar.startOfDay(for: Date())
        let сейчас = calendar.date(minuteOfDay: 23 * 60, on: день)

        let доза = DoseRecord(scheduledAt: calendar.date(minuteOfDay: 9 * 60, on: день))
        доза.medication = medication
        context.insert(доза)
        try context.save()

        #expect(доза.escalationStage(at: сейчас) == 3, "до пропуска она просрочена")

        доза.skippedAt = сейчас
        доза.skippedBy = "Вика"
        try context.save()

        #expect(доза.escalationStage(at: сейчас) == 0,
                "пропуск не погасил лестницу: решение принято и записано, тревожиться больше не о чем")
        #expect(DoseScheduler.alarmingDose(among: dog.medications, now: сейчас) == nil,
                "баннер остался после пропуска")
    }

    @Test("Завершение не трогает вес и историю собаки")
    func historySurvives() throws {
        let (context, dog, _) = try setup()
        let weight = WeightEntry(kg: 12.4)
        weight.dog = dog
        context.insert(weight)
        let event = LogEvent(kind: .dose, date: Date(), authorName: "Вика")
        event.dog = dog
        context.insert(event)
        try context.save()

        TreatmentCourse.finish(dog, by: "Вика", context: context)

        #expect(dog.weights.count == 1)
        #expect(dog.events.contains { $0.kind == .dose })
    }

    /// **Сутки отсчитываются календарём, опоздание — секундами, и это
    /// две разные величины.** До 25.10.2026 дозы строились здесь
    /// `now.addingTimeInterval(Double(offset) * 86400)`, а проверялось
    /// `summary.days`, которое с `d5b9976` (24.10.2026) считает
    /// КАЛЕНДАРНЫЕ сутки. Триста шестьдесят три дня в году эти два
    /// способа совпадают. Замер 25.10.2026, Europe/Paris, в сутках
    /// 25 часов:
    ///
    /// ```
    /// now − 4 × 86400 секунд     2026-10-21 13:52 GMT+2 → суток 3   ← предмет
    /// now − 4 суток календарём   2026-10-21 12:52 GMT+2 → суток 4   ← контроль
    /// ```
    ///
    /// `summary.days` вернул 3 при ожидании ≥ 4, и код был прав:
    /// по стенным часам от 21-го 13:52 до 25-го 12:52 действительно
    /// неполные четверо суток. Неверен был вход теста.
    ///
    /// > **Починка в одной единице делает ложным замер, построенный
    /// > в другой.** `d5b9976` перевёл показ на календарь и этим снял
    /// > посылку, на которой стоял этот тест с 27.08.2026 (`7c764c1`), —
    /// > а покраснело оно только в воскресенье перевода часов, через
    /// > сутки после починки.
    ///
    /// Опоздание (900 и 7200 секунд) остаётся секундами нарочно:
    /// `onTimeWindow` — это отрезок в 3600 секунд, а не сутки.
    @Test("Итог курса считает дозы и долю вовремя")
    func summaryCountsDoses() throws {
        let (context, dog, medication) = try setup()
        let календарь = Calendar.current
        let now = Date()

        for (offset, lateness) in [(-4, 0.0), (-3, 900.0), (-2, 7200.0)] as [(Int, Double)] {
            let назначено = try #require(календарь.date(byAdding: .day, value: offset, to: now))
            let dose = DoseRecord(scheduledAt: назначено)
            dose.givenAt = dose.scheduledAt.addingTimeInterval(lateness)
            dose.medication = medication
            context.insert(dose)
        }
        try context.save()

        let summary = TreatmentCourse.summary(dog, now: now)
        #expect(summary.dosesGiven == 3)
        #expect(summary.dosesOnTime == 2, "два часа опоздания — уже не вовремя")
        #expect(summary.days >= 4)
    }

    /// Ровно четырнадцать суток через воскресенье перевода часов.
    ///
    /// **Сторож на само расхождение, а не на форму записи.** Форму держит
    /// `КалендарьПротивСекундTests`; здесь — исход на экране, и он
    /// воспроизводится только в конкретном часовом поясе и конкретную
    /// ночь, поэтому пояс и даты названы числом, а не взяты у машины.
    ///
    /// Европа/Париж, ночь с 28 на 29 марта 2026 года: часы переводят
    /// вперёд, в сутках 23 часа. От 15 марта 12:00 до 29 марта 12:00
    /// по стенным часам ровно 14 суток, а в секундах — 13 суток 23 часа.
    /// `Int(span / 86400)` отрезал это до 13, ветка `days >= 14`
    /// не бралась, и «2 недели позади» становилось «13 дней позади».
    ///
    /// Три замера в одной команде: прежняя форма (обязана дать 13),
    /// новая (обязана дать 14) и исход на экране. Без первого тест
    /// зелен и в том случае, если даты выбраны мимо перевода часов.
    @Test("Четырнадцать суток через перевод часов остаются двумя неделями")
    func двеНеделиЧерезПереводЧасов() throws {
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        var начало = DateComponents()
        начало.year = 2026
        начало.month = 3
        начало.day = 15
        начало.hour = 12
        let старт = try #require(календарь.date(from: начало))
        let финиш = try #require(календарь.date(byAdding: .day, value: 14, to: старт))

        #expect(Int(финиш.timeIntervalSince(старт) / 86_400) == 13,
                """
                Прежняя форма обязана дать здесь 13 — на этом стоит тест. \
                Дала другое: значит даты выбраны мимо воскресенья перевода \
                часов, и замер не состоялся.
                """)
        #expect(TreatmentCourse.суток(от: старт, до: финиш, календарь: календарь) == 14,
                "календарь обязан назвать 14 суток там, где секунд 13,96")

        let итог = TreatmentCourse.Summary(days: 14, dosesGiven: 28,
                                           dosesOnTime: 28, skipped: 0)
        #expect(итог.headline == "2 недели позади",
                "ветка «недели» не взялась — человек читает «13 дней» про две недели лечения")
    }

    @Test("Без отметок процента не бывает")
    func noPercentWithoutDoses() throws {
        let (_, dog, _) = try setup()
        let summary = TreatmentCourse.summary(dog)
        #expect(summary.onTimeShare == nil, "иначе экран поздравит со стопроцентным нулём")
        #expect(summary.headline == "Курс закончен")
    }

    @Test("Длинный курс называется неделями")
    func headlineInWeeks() throws {
        let summary = TreatmentCourse.Summary(days: 42, dosesGiven: 82,
                                              dosesOnTime: 77, skipped: 1)
        #expect(summary.headline == "6 недель позади")
    }

    @Test("Короткий курс называется днями")
    func headlineInDays() throws {
        let summary = TreatmentCourse.Summary(days: 5, dosesGiven: 10,
                                              dosesOnTime: 10, skipped: 0)
        #expect(summary.headline == "5 дней позади")
    }

    @Test("Пропуски в итоге видны отдельно")
    func summaryCountsSkips() throws {
        let (context, dog, medication) = try setup()
        let dose = DoseRecord(scheduledAt: Date().addingTimeInterval(-3600))
        dose.skippedAt = Date()
        dose.medication = medication
        context.insert(dose)
        try context.save()

        #expect(TreatmentCourse.summary(dog).skipped == 1)
    }

    @Test("Контрольный приём заводится делом, а не фразой")
    func checkupBecomesTask() throws {
        let (context, dog, _) = try setup()
        let now = Date()

        let task = try #require(TreatmentCourse.scheduleCheckup(for: dog, from: now, context: context))
        #expect(task.kind == .dated)
        #expect(task.category == .medical)
        let expected = Calendar.current.date(byAdding: .day, value: 14, to: now)
        #expect(task.scheduledDate == expected)
        #expect(dog.careTasks.contains { $0.title == TreatmentCourse.checkupTitle })
    }

    @Test("Повторное нажатие не плодит второй приём")
    func checkupIsNotDuplicated() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.scheduleCheckup(for: dog, context: context)
        TreatmentCourse.scheduleCheckup(for: dog, context: context)

        #expect(dog.careTasks.filter { $0.title == TreatmentCourse.checkupTitle }.count == 1)
    }

    @Test("Приём переживает конец курса")
    func checkupSurvivesFinish() throws {
        let (context, dog, _) = try setup()
        TreatmentCourse.scheduleCheckup(for: dog, context: context)
        TreatmentCourse.finish(dog, by: "Вика", context: context)

        #expect(dog.careTasks.contains { $0.title == TreatmentCourse.checkupTitle })
    }
}
