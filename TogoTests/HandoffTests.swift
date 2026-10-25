import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("Запас таблеток")
struct PillSupplyTests {

    @Test("Хватит ровно на столько дней, сколько доз влезает")
    func daysFromDoses() throws {
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 8, packSize: 60, perDay: 2)
        )
        #expect(supply.days == 4)
        #expect(supply.headline == "Таблеток на 4 дня")
    }

    @Test("Пустая пачка означает «не считаем», а не ноль дней")
    func noCountingWithoutTotal() {
        #expect(PillSupplyAdvisor.supply(remaining: 0, packSize: 0, perDay: 2) == nil,
                "навязывать учёт тому, кто покупает коробку в год, незачем")
    }

    @Test("Видно, на сколько дней курса не хватит")
    func shortfallIsNamed() throws {
        let now = Date()
        let ends = Calendar.current.date(byAdding: .day, value: 22, to: now)
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 8, packSize: 60, perDay: 2,
                                     courseEnds: ends, now: now)
        )
        let shortfall = try #require(supply.shortfallDays)
        #expect(shortfall == 18)
    }

    @Test("Предупреждаем за срок доставки, а не когда кончились")
    func warnsBeforeEmpty() throws {
        let three = try #require(PillSupplyAdvisor.supply(remaining: 6, packSize: 60, perDay: 2))
        let ten = try #require(PillSupplyAdvisor.supply(remaining: 20, packSize: 60, perDay: 2))

        // Через `level(_:)`, а не через снятую `needsWarning`: `Bool`
        // не различал ступени, а на экране у них разный цвет. Теперь
        // утверждение не «предупреждаем», а «предупреждаем ВОТ ТАК».
        #expect(PillSupplyAdvisor.level(three) == .urgent, "аптека везёт два-три дня")
        #expect(PillSupplyAdvisor.level(ten) == .ok)
    }

    @Test("Нехватки на курс достаточно для предупреждения")
    func shortfallWarnsEvenWithStock() throws {
        let ends = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        let supply = try #require(
            PillSupplyAdvisor.supply(remaining: 20, packSize: 60, perDay: 2, courseEnds: ends)
        )
        // Запаса больше недели, но до конца курса не хватит: сказать
        // стоит, пугать нечем — значит именно `.low`, а не `.urgent`.
        #expect(PillSupplyAdvisor.level(supply) == .low)
    }

    // MARK: Ступени

    /// Запас на столько-то дней — одной строкой, чтобы пороги читались
    /// числом, а не арифметикой по `remaining`.
    private func запасНа(_ дней: Int, курсДо: Date? = nil) throws -> PillSupply {
        try #require(PillSupplyAdvisor.supply(remaining: Double(дней) * 2,
                                              packSize: 60, perDay: 2,
                                              courseEnds: курсДо))
    }

    /// **Диапазон `.low` не брал ни один тест — замер `togo-02` 07.10.2026,
    /// доказанный подделкой.**
    ///
    /// Вырежи строку `if supply.days <= lowDays { return .low }` — и весь
    /// набор «Запас таблеток» остаётся зелёным: пять тестов щупают три дня
    /// и десять, а оранжевый живёт между ними, с четвёртого по седьмой.
    /// На пяти днях без курса `.low` проваливался бы в `.ok`,
    /// `needsWarning` возвращал бы `false`, и спросить об этом было некому.
    ///
    /// То есть четвёртый цвет системы, заведённый решением Виктории 05.10
    /// («оранжевый ≤ 7, терракот ≤ 3»), не охранял **ничто**.
    ///
    /// Граница находки, названная `togo-02` после замера и важная сама
    /// по себе: **значение токена под сторожем, ступень — нет.**
    /// `StructuralGapsTests` требует `Token.Status.stockLowText == "#FFA15C"`,
    /// то есть покраснеет, если оранжевый поменяют на другой оранжевый,
    /// и промолчит, если оранжевого не станет на экране вовсе. Наш класс
    /// «значение может быть верным, а вызов — бессильным».
    ///
    /// Проверяется **живым путём `level(_:)`**. Прежде рядом жила
    /// `needsWarning(_:)`, через которую ходили тесты выше, — и в её
    /// доке прямо стояло, что из приложения её не зовут. То есть пять
    /// тестов проверяли то, что у человека не исполняется.
    ///
    /// Снята 07.10.2026 вместе с переписыванием тех пяти на `level(_:)`:
    /// она была `level(supply) != .ok`, то есть пересказом, а `Bool`
    /// вдобавок **прятал** различие, которое на экране есть — у `.low`
    /// и `.urgent` разный цвет.
    @Test("Три ступени различимы, и каждая берётся своим числом дней")
    func триСтупениРазличимы() throws {
        #expect(PillSupplyAdvisor.level(try запасНа(10)) == .ok)
        #expect(PillSupplyAdvisor.level(try запасНа(5)) == .low, """
            запас на пять дней обязан быть оранжевым. Если здесь `.ok` — \
            ступени `.low` в коде больше нет, а пороговые тесты этого \
            не видят: они щупают три дня и десять.
            """)
        #expect(PillSupplyAdvisor.level(try запасНа(3)) == .urgent)
    }

    /// Пороги проверяются **с обоих краёв**: проверка, спрашивающая один
    /// край, выполняется и при дефекте на другом — наш класс «вопрос
    /// слабее дефекта, который он ищет».
    @Test("Пороги стоят ровно на семи и трёх днях, а не около")
    func порогиТочные() throws {
        #expect(PillSupplyAdvisor.level(try запасНа(8)) == .ok, "восьмой день уже не оранжевый")
        #expect(PillSupplyAdvisor.level(try запасНа(7)) == .low, "седьмой — ещё оранжевый")
        #expect(PillSupplyAdvisor.level(try запасНа(4)) == .low, "четвёртый — ещё оранжевый")
        #expect(PillSupplyAdvisor.level(try запасНа(3)) == .urgent, "третий — уже терракот")
    }

    /// Порядок проверок внутри `level(_:)`: терракот спрашивается раньше
    /// оранжевого. Поменяй их местами — и три дня покрасятся оранжевым,
    /// потому что `3 <= 7` истинно тоже.
    ///
    /// Это не придирка к стилю: разница между «скоро кончится»
    /// и «пора покупать» — срок доставки из аптеки.
    @Test("Три дня — терракот, а не оранжевый: порядок порогов верен")
    func порядокПороговВерен() throws {
        #expect(PillSupplyAdvisor.level(try запасНа(2)) == .urgent)
        #expect(PillSupplyAdvisor.level(try запасНа(1)) == .urgent)
    }

    /// Обратный край: курс, кончающийся раньше запаса, снимает ступень
    /// целиком — даже когда дней остался один.
    ///
    /// Без этого «оранжевый ≤ 7» читалось бы как безусловное правило,
    /// и человеку говорили бы купить препарат, который он завтра
    /// перестанет давать.
    ///
    /// **Первая редакция этого теста была красной, и дефекта за ней
    /// не стояло — неверно было моё допущение.** Я взял запас на один
    /// день и курс «до завтра», ожидая `.ok`. Замер: `lastDay` якорится
    /// на ПОЛНОЧЬ (`startOfDay(now) + days`), а `courseEnds` приходит
    /// моментом по часам. При запасе на день курс до завтра кончается
    /// **позже**, чем запас, — `courseEndsFirst` ложно, и `.urgent`
    /// верен. Чтобы курс действительно кончился раньше, запас должен
    /// быть длиннее на день с лишним.
    ///
    /// Рядом с нашим замером 05.10 про дни календаря против момента
    /// у полуночи: здесь две величины сравниваются **разными якорями**,
    /// и для сегодняшнего вопроса это безвредно, а для «курс до сегодня»
    /// — не проверялось никем. Называю наблюдением, не находкой:
    /// замера у меня нет.
    @Test("Курс кончается раньше запаса — ступени нет вовсе")
    func курсСнимаетСтупень() throws {
        let завтра = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        #expect(PillSupplyAdvisor.level(try запасНа(5, курсДо: завтра)) == .ok, """
            курс снимает предупреждение целиком. Если здесь `.low` — \
            проверку курса переставили ПОСЛЕ порогов, и она ничего \
            не решает: решение уже принято порогом.
            """)
        #expect(PillSupplyAdvisor.level(try запасНа(2, курсДо: завтра)) == .ok, """
            то же и у терракота: курс снимает ОБЕ ступени, а не только \
            оранжевую.
            """)
    }
}

@Suite("Итог смены")
struct ShiftTests {

    private func item(_ title: String, hour: Int, done: Bool, by: String? = nil) -> ShiftItem {
        let due = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(hour) * 3600)
        return ShiftItem(id: title, title: title, due: due, isDone: done, by: by)
    }

    private var shift: Shift {
        let day = Calendar.current.startOfDay(for: Date())
        return Shift(person: "Игорь",
                     from: day.addingTimeInterval(7 * 3600),
                     to: day.addingTimeInterval(19 * 3600))
    }

    @Test("Считается закрытое из всего")
    func headline() {
        let summary = ShiftSummary(shift: shift, items: [
            item("Утренняя еда", hour: 8, done: true, by: "Игорь"),
            item("Доза", hour: 9, done: true, by: "Игорь"),
            item("Прогулка", hour: 12, done: true, by: "Игорь"),
            item("Прогулка", hour: 15, done: true, by: "Игорь"),
            item("Прогулка", hour: 18, done: true, by: "Игорь"),
            item("Вечерняя еда", hour: 20, done: false),
        ])
        #expect(summary.headline == "5 из 6 закрыто")
        #expect(summary.open.count == 1)
    }

    @Test("Уведомление называет и сделанное, и открытое")
    func notificationNamesBoth() {
        let summary = ShiftSummary(shift: shift, items: [
            item("Доза", hour: 9, done: true, by: "Игорь"),
            item("Вечерняя еда", hour: 20, done: false),
        ])
        let text = summary.notification()
        #expect(text.lowercased().contains("доза"))
        #expect(text.contains("Открыто"))
        #expect(text.contains("вечерняя еда"))
    }

    @Test("Смена без записей не притворяется пустым успехом")
    func emptyShift() {
        let summary = ShiftSummary(shift: shift, items: [])
        #expect(summary.notification() == "Записей за смену нет.")
    }

    @Test("Смена знает, попадает ли час в неё")
    func coverage() {
        let day = Calendar.current.startOfDay(for: Date())
        #expect(shift.covers(day.addingTimeInterval(12 * 3600)))
        #expect(!shift.covers(day.addingTimeInterval(21 * 3600)))
    }
}

@Suite("Смена схемы после врача")
@MainActor
struct ScheduleChangeTests {

    private func setup() throws -> (ModelContext, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60, 20 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, medication)
    }

    private func change(_ startsFrom: ScheduleChange.StartsFrom) -> ScheduleChange {
        ScheduleChange(oldDoseText: "16 мг", oldTimes: [9 * 60, 20 * 60],
                       newDoseText: "16 мг", newTimes: [9 * 60],
                       startsFrom: startsFrom)
    }

    @Test("Расписание описывается словами, а не списком минут")
    func summaryInWords() {
        #expect(ScheduleChange.summary([9 * 60, 20 * 60]) == "дважды в день")
        #expect(ScheduleChange.summary([9 * 60]) == "один раз · утром")
        #expect(ScheduleChange.summary([20 * 60]) == "один раз · вечером")
    }

    @Test("Прошлые отметки не трогаются")
    func pastIsUntouched() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let given = DoseRecord(scheduledAt: now.addingTimeInterval(-5 * 3600))
        given.givenAt = now.addingTimeInterval(-5 * 3600)
        given.medication = medication
        context.insert(given)
        try context.save()

        ScheduleChangeApplier.apply(change(.tomorrowMorning), to: medication,
                                    now: now, context: context)

        #expect(medication.doses.contains { $0.isGiven },
                "история приёмов задним числом не должна становиться неправдой")
    }

    @Test("Лишняя будущая отметка удаляется и её называют заранее")
    func doomedDoseIsNamedAndRemoved() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let evening = DoseRecord(scheduledAt: calendar.startOfDay(for: now).addingTimeInterval(20 * 3600))
        evening.medication = medication
        context.insert(evening)
        try context.save()

        let plan = change(.tonight)
        #expect(plan.doomedDoses(medication.doses, now: now).count == 1)

        let removed = ScheduleChangeApplier.apply(plan, to: medication, now: now, context: context)
        #expect(removed == 1)
        #expect(medication.times == [9 * 60])
    }

    @Test("«С завтрашнего утра» оставляет сегодняшний вечер по старой схеме")
    func tomorrowKeepsTonight() throws {
        let (context, medication) = try setup()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(14 * 3600)

        let evening = DoseRecord(scheduledAt: calendar.startOfDay(for: now).addingTimeInterval(20 * 3600))
        evening.medication = medication
        context.insert(evening)
        try context.save()

        let removed = ScheduleChangeApplier.apply(change(.tomorrowMorning), to: medication,
                                                  now: now, context: context)
        #expect(removed == 0, "вечером ещё старая схема — так и написано на экране")
        #expect(medication.doses.count == 1)
    }
}

@Suite("Сводка врачу")
@MainActor
struct VetSummaryTests {

    private func setup() throws -> (ModelContext, Dog, Medication) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 9)
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "16 мг", times: [9 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()
        return (context, dog, medication)
    }

    @Test("Доля вовремя считается по фактическим отметкам")
    func onTimeShare() throws {
        let (context, _, medication) = try setup()
        let now = Date()

        for (offset, lateness) in [(-5, 0.0), (-4, 600.0), (-3, 7200.0)] as [(Int, Double)] {
            let dose = DoseRecord(scheduledAt: now.addingTimeInterval(Double(offset) * 86400))
            dose.givenAt = dose.scheduledAt.addingTimeInterval(lateness)
            dose.medication = medication
            context.insert(dose)
        }
        try context.save()

        let summary = VetSummaryBuilder.build(
            events: [], doses: medication.doses, weights: [],
            from: now.addingTimeInterval(-30 * 86400), to: now
        )
        #expect(summary.dosesOnTime == 2)
        #expect(summary.dosesShifted == 1)
        let share = try #require(summary.onTimeShare)
        #expect(Int((share * 100).rounded()) == 67)
    }

    @Test("Без доз процента не бывает")
    func noShareWithoutDoses() {
        let summary = VetSummaryBuilder.build(events: [], doses: [], weights: [],
                                              from: Date().addingTimeInterval(-86400), to: Date())
        #expect(summary.onTimeShare == nil)
    }

    @Test("Инциденты группируются и называются одной строкой")
    func incidentsGrouped() throws {
        let (context, dog, _) = try setup()
        let now = Date()
        for _ in 0..<4 {
            let event = LogEvent(kind: .incident, date: now.addingTimeInterval(-3600), authorName: "Вика")
            event.incidentKind = .vomit
            event.dog = dog
            context.insert(event)
        }
        try context.save()

        let summary = VetSummaryBuilder.build(
            events: dog.events, doses: [], weights: [],
            from: now.addingTimeInterval(-86400), to: now
        )
        #expect(summary.incidentTotal == 4)
        #expect(summary.incidentDetail?.contains("все —") == true)
    }

    @Test("Удалённые записи в сводку не попадают")
    func deletedExcluded() throws {
        let (context, dog, _) = try setup()
        let now = Date()
        let event = LogEvent(kind: .incident, date: now.addingTimeInterval(-3600), authorName: "Вика")
        event.incidentKind = .vomit
        event.deletedAt = now
        event.dog = dog
        context.insert(event)
        try context.save()

        let summary = VetSummaryBuilder.build(events: dog.events, doses: [], weights: [],
                                              from: now.addingTimeInterval(-86400), to: now)
        #expect(summary.incidentTotal == 0)
    }

    @Test("Дельта веса считается от первой точки к последней")
    func weightDelta() {
        let now = Date()
        let summary = VetSummaryBuilder.build(
            events: [], doses: [],
            weights: [(now.addingTimeInterval(-30 * 86400), 9.2), (now, 8.8)],
            from: now.addingTimeInterval(-31 * 86400), to: now
        )
        #expect(summary.weightDelta?.contains("0,4") == true)
        #expect(summary.weightDelta?.hasPrefix("−") == true)
    }

    @Test("«Что изменилось» сравнивает с прошлым периодом словами")
    func deltaInWords() {
        let now = Date()
        func summary(incidents: Int) -> VetSummary {
            VetSummary(from: now.addingTimeInterval(-30 * 86400), to: now,
                       dosesOnTime: 0, dosesShifted: 0, dosesSkipped: 0,
                       incidents: incidents > 0 ? [(kind: .vomit, count: incidents)] : [],
                       weights: [])
        }
        let lines = VetSummaryBuilder.delta(current: summary(incidents: 2),
                                            previous: summary(incidents: 9))
        #expect(lines.contains { $0.contains("реже") && $0.contains("2") && $0.contains("9") })
    }
}
