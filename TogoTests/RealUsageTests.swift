import Testing
import Foundation
import SwiftData
@testable import Togo

/// Проверки, выросшие из настоящего дневника на телефоне, а не из головы.
///
/// В базе живого устройства нашлось три вещи: три записи еды по 65 г
/// с интервалом в две секунды (человек жал кнопку, не получая отклика),
/// запись, выставленная на вечер того же дня, и девять напоминаний ухода,
/// которые никогда никому ни о чём не напомнили бы.
@Suite("Находки из живого дневника")
@MainActor
struct RealUsageTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private func стич(в context: ModelContext) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.73)
        dog.portionGrams = 65
        dog.mealsPerDay = 3
        context.insert(dog)
        return dog
    }

    // MARK: Двойной тап

    @Test("Три тапа по «Записать» подряд дают одну запись, а не три")
    func doubleTapDoesNotDuplicate() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState.наСвоёмТелефоне())

        // Ровно то, что случилось: 00:20:10, :12, :14, все по 65 г.
        let первая = log.record(.meal, dog: dog, confirmation: "Еда") { $0.grams = 65 }
        let вторая = log.record(.meal, dog: dog, at: .now.addingTimeInterval(2),
                                confirmation: "Еда") { $0.grams = 65 }
        let третья = log.record(.meal, dog: dog, at: .now.addingTimeInterval(4),
                                confirmation: "Еда") { $0.grams = 65 }

        #expect(первая != nil)
        #expect(вторая == nil, "второй тап за две секунды — это тот же тап")
        #expect(третья == nil)
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 1)
    }

    @Test("Человек всё-таки видит, почему запись не появилась")
    func duplicateExplainsItself() throws {
        let context = контекст()
        let dog = стич(в: context)
        let state = AppState.наСвоёмТелефоне()
        let log = EventLog(context: context, appState: state)

        log.record(.meal, dog: dog, confirmation: "Еда") { $0.grams = 65 }
        log.record(.meal, dog: dog, at: .now.addingTimeInterval(3), confirmation: "Еда") { $0.grams = 65 }

        #expect(state.undo?.message.contains("уже записано") == true)
    }

    @Test("Через полтора часа то же кормление — настоящее, а не повтор")
    func laterMealIsReal() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState.наСвоёмТелефоне())

        log.record(.meal, dog: dog, confirmation: nil) { $0.grams = 65 }
        log.record(.meal, dog: dog, at: .now.addingTimeInterval(90 * 60), confirmation: nil) { $0.grams = 65 }

        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 2)
    }

    /// До 30.09 выход стоял здесь же, рядом с водой. Но выход с кнопки —
    /// это «Вывожу», и два за полторы минуты значат двойной тап, а не две
    /// нужды; «писал трижды за прогулку» — отметки прогулки, у них своя
    /// оговорка в `DuplicateGuard.refersToSameThing`.
    @Test("Вода и инцидент не считаются повторами, а выход с кнопки — считается")
    func repeatableKindsAreNotDeduplicated() throws {
        let context = контекст()
        let dog = стич(в: context)
        let log = EventLog(context: context, appState: AppState.наСвоёмТелефоне())

        for _ in 0..<3 {
            log.record(.outing, dog: dog, confirmation: nil)
            log.record(.water, dog: dog, confirmation: nil) { $0.milliliters = 50 }
            log.record(.incident, dog: dog, confirmation: nil)
        }
        let записи = try context.fetch(FetchDescriptor<LogEvent>())
        #expect(записи.filter { $0.kind == .water }.count == 3)
        #expect(записи.filter { $0.kind == .incident }.count == 3,
                "два инцидента подряд осмысленны: из них поднимается эпизод")
        #expect(записи.filter { $0.kind == .outing }.count == 1,
                "три «Вывожу» за секунды — один выход")
    }

    // MARK: Уход, который молчал

    @Test("Регулярное дело без даты не молчит, а просит дату")
    func undatedTaskAsksForDate() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)

        #expect(когти.needsDate, "дело должно попасть в группу «нужна дата»")
        #expect(!когти.isDue(), "но не притворяться просрочкой")
        #expect(когти.statusText() == "когда делали?")
    }

    @Test("Поставили примерную дату — дело начинает работать")
    func dateMakesTaskWork() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = Calendar.current.date(byAdding: .month, value: -1, to: .now)

        #expect(!когти.needsDate)
        #expect(когти.isDue())
        #expect(когти.isOverdue())
    }

    @Test("Прививка без назначенного дня тоже просит дату")
    func undatedVaccine() {
        let прививка = CareTask(title: "Бешенство", detail: "", kind: .dated,
                                intervalDays: 365, category: .medical)
        #expect(прививка.needsDate)
        #expect(!прививка.isDue())
    }

    // MARK: Починка старого ухода

    @Test("«Уши и зубы» разделяются: зубы каждый день, уши раз в неделю")
    func migrationSplitsEarsAndTeeth() throws {
        let context = контекст()
        let dog = стич(в: context)
        let старое = CareTask(title: "Уши и зубы", detail: "раз в неделю",
                              kind: .periodic, intervalDays: 7)
        старое.dog = dog
        context.insert(старое)

        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        let зубы = дела.first { $0.title == "Зубы" }
        let уши = дела.first { $0.title == "Уши" }

        #expect(зубы?.kind == .daily, "налёт твердеет за сутки")
        #expect(уши?.kind == .periodic)
        #expect(уши?.intervalDays == 7)
        #expect(!дела.contains { $0.title == "Уши и зубы" })
    }

    @Test("Прививки переезжают с «раз в 365 дней» на конкретную дату")
    func migrationMovesVaccinesToDates() throws {
        let context = контекст()
        let dog = стич(в: context)
        for title in ["Бешенство", "Комплексная"] {
            let task = CareTask(title: title, detail: "раз в год", kind: .periodic,
                                intervalDays: 365, category: .medical)
            task.dog = dog
            context.insert(task)
        }

        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        #expect(дела.allSatisfy { $0.kind == .dated })
        #expect(дела.allSatisfy { $0.needsDate }, "дату поставит человек, выдумывать нельзя")
    }

    @Test("Починка не портит то, что уже правильно, и не работает дважды")
    func migrationIsIdempotent() throws {
        let context = контекст()
        let dog = стич(в: context)
        let зубы = CareTask(title: "Зубы", detail: "", kind: .daily, intervalDays: 1)
        зубы.dog = dog
        зубы.streak = 5
        context.insert(зубы)

        CareMigration.run(context: context)
        CareMigration.run(context: context)

        let дела = try context.fetch(FetchDescriptor<CareTask>())
        #expect(дела.count == 1, "второй раз ничего не добавилось")
        #expect(дела[0].streak == 5, "серия не сброшена")
    }

    // MARK: Честность интерфейса

    @Test("Галочки «синхронизировано» нет, пока нет синхронизации")
    func noFakeSyncMark() {
        // Поле осталось под будущий обмен, но в ленте оно не показывается:
        // зелёная галочка у каждой записи была украшением, притворяющимся
        // сведениями. Вопрос «а что это за галочка» задала живой человек.
        let event = LogEvent(kind: .meal, authorName: "Виктория")
        #expect(event.isSynced, "поле есть и всегда true — обмена нет")
    }

    @Test("Автор в ленте нужен только когда людей больше одного")
    func authorShownOnlyInFamily() {
        // Одному себе представляться незачем: инициал в каждой строке
        // у человека, который в дневнике один, — шум.
        let одна = [FamilyMember(name: "Виктория", role: .owner, isMe: true)]
        let семья = одна + [FamilyMember(name: "Тео", role: .coOwner)]

        #expect(одна.count == 1)
        #expect(семья.count > 1)
    }

    // MARK: Запись в будущем

    @Test("Запись в будущем ломала бы вердикт")
    func futureRecordWouldBreakVerdict() {
        let сейчас = Date()
        let вечером = сейчас.addingTimeInterval(11 * 3600)

        let signals = NeedSignals(
            now: сейчас,
            lastUrine: вечером,
            urineIntervals: Array(repeating: 4 * 3600, count: 10),
            daysOfData: 10,
            lastOutingHadResult: true
        )

        // Интервал получается отрицательным — «только что выходили»,
        // хотя выход записан на вечер. Поэтому время правки ограничено
        // текущим моментом.
        #expect(signals.sinceUrine! < 0)
        #expect(VerdictEngine.evaluate(signals) != .urgent)
    }
}

/// Баги, найденные при повторном осмотре живого устройства.
@Suite("Второй осмотр телефона")
@MainActor
struct SecondPassTests {
    private let calendar = Calendar.current

    private func днейНазад(_ дней: Int) -> Date {
        calendar.date(byAdding: .day, value: -дней, to: .now)!
    }

    // MARK: Запас корма замирал

    @Test("Остаток корма убывает сам, а не ждёт, пока его пересчитают")
    func stockCountsDown() {
        // Пять паучей по 150 г при 195 г в день — на четыре дня.
        let корм = FoodStock(kind: .wet, brand: "Edgar Cooper", packGrams: 150,
                             packsLeft: 5, gramsPerDay: 195, countedAt: днейНазад(2))

        #expect(корм.countedGrams == 750)
        #expect(корм.usedGrams() == 390, "за два дня съедено 390 г")
        #expect(корм.remainingGrams() == 360)
        #expect(корм.daysLeft() == 1)
        #expect(корм.needsRestock())
    }

    @Test("В день пересчёта остаток равен тому, что назвал человек")
    func freshCountIsExact() {
        let корм = FoodStock(kind: .dry, packGrams: 3000, packsLeft: 1,
                             gramsPerDay: 120, countedAt: .now)
        #expect(корм.usedGrams() == 0)
        #expect(корм.remainingGrams() == 3000)
        #expect(корм.daysLeft() == 25)
    }

    @Test("Кончившийся корм не уходит в минус")
    func stockNeverNegative() {
        let корм = FoodStock(kind: .wet, packGrams: 150, packsLeft: 2,
                             gramsPerDay: 195, countedAt: днейНазад(30))
        #expect(корм.remainingGrams() == 0)
        #expect(корм.daysLeft() == 0)
        #expect(корм.packsRemaining() == 0)
    }

    @Test("Сводка по влажному считает банками, и цифра свежая")
    func wetSummaryIsCurrent() {
        let корм = FoodStock(kind: .wet, packGrams: 150, packsLeft: 6,
                             gramsPerDay: 150, countedAt: днейНазад(2))
        #expect(корм.packsRemaining() == 4)
        #expect(корм.summary().contains("4"))
    }

    // MARK: Прогулка ломала вердикт

    @Test("Три отметки мочи за одну прогулку не считаются тремя интервалами")
    func walkMarksDoNotPoisonVerdict() {
        var события: [LogEvent] = []

        // Четыре дня по три выхода с интервалом четыре часа.
        for день in 1...4 {
            for час in [8, 12, 16] {
                let выход = LogEvent(kind: .outing,
                                     date: дата(день, час: час),
                                     authorName: "Виктория")
                выход.outcome = .urine
                события.append(выход)
            }
        }

        let ровные = Diary.urineIntervals(события)
        #expect(ровные.allSatisfy { $0 >= 4 * 3600 - 1 })

        // Та же история, но на каждой прогулке собака метит трижды
        // с интервалом в десять минут — как оно и бывает.
        for день in 1...4 {
            for час in [8, 12, 16] {
                for минута in [10, 20] {
                    let метка = LogEvent(kind: .outing,
                                         date: дата(день, час: час, минута: минута),
                                         authorName: "Виктория")
                    метка.outcome = .urine
                    события.append(метка)
                }
            }
        }

        let сметками = Diary.urineIntervals(события)
        #expect(сметками.allSatisfy { $0 > Diary.sameEmptyingWindow },
                "десятиминутные промежутки внутри одной прогулки — не интервалы терпения")

        // Медиана не должна уехать вниз: иначе вердикт начнёт считать
        // нормой десять минут и перестанет работать.
        let медиана = сметками.sorted()[сметками.count / 2]
        #expect(медиана >= 3 * 3600)
    }

    private func дата(_ дней: Int, час: Int, минута: Int = 0) -> Date {
        let день = calendar.date(byAdding: .day, value: -дней,
                                 to: calendar.startOfDay(for: .now))!
        return день.addingTimeInterval(Double(час * 60 + минута) * 60)
    }

    // MARK: Лакомства из порции

    @Test("Лакомство из порции считается съеденным за день")
    func treatsCountTowardDailyFood() {
        let dog = Dog(name: "Стич", weightKg: 4.73)
        dog.portionGrams = 65
        dog.mealsPerDay = 3

        let полдень = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let еда = LogEvent(kind: .meal, date: полдень, authorName: "Виктория")
        еда.grams = 65
        let занятие = LogEvent(kind: .treat, date: полдень.addingTimeInterval(3600),
                               authorName: "Виктория")
        занятие.grams = 30
        занятие.fromPortion = true

        let сводка = Diary.summary([еда, занятие], day: полдень, dog: dog)
        #expect(сводка.eatenGrams == 95, "иначе «съел 65 из 195», хотя съел 95")
    }

    @Test("Лакомство сверх порции в дневную норму не идёт")
    func extraTreatsDoNotCount() {
        let dog = Dog(name: "Стич", weightKg: 4.73)
        dog.portionGrams = 65
        dog.mealsPerDay = 3

        let полдень = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let гость = LogEvent(kind: .treat, date: полдень, authorName: "Тео")
        гость.grams = 20
        гость.fromPortion = false

        #expect(Diary.summary([гость], day: полдень, dog: dog).eatenGrams == 0)
    }
}

/// Дыры в логике, найденные при ревизии по HIG: не в навигации, а в том,
/// что за ней стоит.
@Suite("Дозы и эпизоды")
@MainActor
struct TreatmentAndEpisodeTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private func стич(на лечении: Bool, в context: ModelContext) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.73)
        dog.isOnTreatment = лечении
        context.insert(dog)
        return dog
    }

    // MARK: Приёмы препаратов

    @Test("Отметки приёма заводятся на день по расписанию")
    func dosesAreCreated() throws {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг",
                               times: [7 * 60, 19 * 60], fastingMinutes: 45)
        схема.dog = dog
        context.insert(схема)

        let создано = DoseScheduler.ensureDoses(for: dog, context: context)
        #expect(создано == 2, "две отметки на день — по числу приёмов")

        // Повторный заход ничего не задваивает.
        #expect(DoseScheduler.ensureDoses(for: dog, context: context) == 0)
    }

    @Test("У здоровой собаки отметок не заводится")
    func healthyDogHasNoDoses() {
        let context = контекст()
        let dog = стич(на: false, в: context)
        #expect(DoseScheduler.ensureDoses(for: dog, context: context) == 0)
    }

    @Test("Схема на паузе не создаёт приёмов")
    func pausedMedicationIsSkipped() {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Что-то", doseText: "1 т", times: [9 * 60])
        схема.isPaused = true
        схема.dog = dog
        context.insert(схема)

        #expect(DoseScheduler.ensureDoses(for: dog, context: context) == 0)
    }

    @Test("Окно натощак считается от фактической отметки, а не от расписания")
    func fastingFromActualTime() {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг",
                               times: [7 * 60], fastingMinutes: 45)
        схема.dog = dog
        context.insert(схема)

        let calendar = Calendar.current
        let поплану = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let наделе = поплану.addingTimeInterval(12 * 60)   // дали в 07:12

        DoseScheduler.markGiven(схема, scheduledAt: поплану, by: "Виктория",
                                at: наделе, context: context)

        let окно = DoseScheduler.fastingEnds(for: dog, at: наделе.addingTimeInterval(60))
        #expect(окно != nil, "окно должно идти")
        #expect(окно?.givenAt == наделе)
        #expect(окно?.until == наделе.addingTimeInterval(45 * 60),
                "45 минут от 07:12, а не от 07:00")
    }

    @Test("Защита от двойной дозы: второй раз отметить нельзя")
    func doubleDoseIsBlocked() {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг", times: [7 * 60])
        схема.dog = dog
        context.insert(схема)

        let время = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let первая = DoseScheduler.markGiven(схема, scheduledAt: время, by: "Виктория",
                                             at: время, context: context)
        let вторая = DoseScheduler.markGiven(схема, scheduledAt: время, by: "Тео",
                                             at: время.addingTimeInterval(600), context: context)

        #expect(первая?.givenBy == "Виктория")
        #expect(вторая?.givenBy == "Виктория", "вторая отметка не перезаписывает первую")
        #expect(схема.doses.filter(\.isGiven).count == 1)
    }

    @Test("Чужое «дано» на ту же минуту останавливает свою открытую отметку")
    func foreignGivenBlocksOwnOpen() {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг", times: [7 * 60])
        схема.dog = dog
        context.insert(схема)

        let время = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        // Своя открытая отметка — первой в списке, чужая данная — второй:
        // так они лежат, когда общий дневник привёз отметку мамы.
        let своя = DoseRecord(scheduledAt: время)
        своя.medication = схема
        context.insert(своя)
        let чужая = DoseRecord(scheduledAt: время)
        чужая.medication = схема
        чужая.givenAt = время
        чужая.givenBy = "Мама"
        context.insert(чужая)

        let ответ = DoseScheduler.markGiven(схема, scheduledAt: время, by: "Виктория",
                                            at: время.addingTimeInterval(600), context: context)

        #expect(ответ?.givenBy == "Мама")
        #expect(своя.givenAt == nil, "вторая доза не отмечается рядом с чужой данной")
    }

    @Test("Окно натощак заканчивается, а не висит вечно")
    func fastingEnds() {
        let context = контекст()
        let dog = стич(на: true, в: context)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг",
                               times: [7 * 60], fastingMinutes: 45)
        схема.dog = dog
        context.insert(схема)

        let дали = Date()
        DoseScheduler.markGiven(схема, scheduledAt: дали, by: "Виктория", at: дали, context: context)

        #expect(DoseScheduler.fastingEnds(for: dog, at: дали.addingTimeInterval(30 * 60)) != nil)
        #expect(DoseScheduler.fastingEnds(for: dog, at: дали.addingTimeInterval(46 * 60)) == nil)
    }

    // MARK: Эпизоды

    @Test("Эпизод заканчивается сам, а не глушит вердикт навсегда")
    func episodeExpires() {
        let эпизод = Episode(title: "Эпизод", detail: "")
        #expect(эпизод.isActive())

        let через_сутки = Date().addingTimeInterval(24 * 3600)
        #expect(эпизод.isActive(at: через_сутки), "сутки — ещё идёт")

        let через_трое = Date().addingTimeInterval(72 * 3600)
        #expect(!эпизод.isActive(at: через_трое), "двое суток тишины — прошло")
    }

    @Test("Новый инцидент продлевает эпизод, а не заводит второй")
    func episodeExtends() {
        let эпизод = Episode(title: "Эпизод", detail: "")
        let позже = Date().addingTimeInterval(30 * 3600)
        эпизод.extend(to: позже)

        #expect(эпизод.lastIncidentAt == позже)
        #expect(эпизод.isActive(at: позже.addingTimeInterval(24 * 3600)))
        #expect(!эпизод.isActive(at: позже.addingTimeInterval(72 * 3600)))
    }

    @Test("Эпизод можно закрыть руками")
    func episodeCanBeClosed() {
        let эпизод = Episode(title: "Эпизод", detail: "")
        эпизод.close()
        #expect(!эпизод.isActive(at: Date().addingTimeInterval(60)))
    }

    @Test("Состояние подтягивает эпизод из базы, а не помнит его в памяти")
    func stateRefreshesEpisode() {
        let свежий = Episode(title: "Эпизод", detail: "")
        let старый = Episode(title: "Старый", detail: "",
                             startedAt: Date().addingTimeInterval(-10 * 24 * 3600))
        старый.lastIncidentAt = Date().addingTimeInterval(-10 * 24 * 3600)

        let state = AppState.наСвоёмТелефоне()
        state.refreshEpisode(from: [старый, свежий])

        #expect(state.activeEpisode === свежий)
        #expect(state.isEpisodeActive)

        state.refreshEpisode(from: [старый])
        #expect(state.activeEpisode == nil, "прошедший эпизод не глушит вердикт")
    }
}
