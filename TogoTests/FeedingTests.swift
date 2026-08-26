import Testing
import Foundation
@testable import Togo

@Suite("Питание · сколько, сколько раз и во сколько")
@MainActor
struct FeedingTests {
    private let calendar = Calendar.current

    private func дата(_ дней: Int, час: Int, минута: Int = 0) -> Date {
        let день = calendar.date(byAdding: .day, value: -дней, to: calendar.startOfDay(for: .now))!
        return день.addingTimeInterval(Double(час * 60 + минута) * 60)
    }

    private func еда(_ дней: Int, час: Int, минута: Int = 0, граммы: Int) -> LogEvent {
        let event = LogEvent(kind: .meal, date: дата(дней, час: час, минута: минута), authorName: "Виктория")
        event.grams = граммы
        return event
    }

    private func стич() -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        dog.mealsPerDay = 2
        dog.mealTimes = [7 * 60 + 30, 18 * 60 + 30]
        return dog
    }

    @Test("Меньше трёх полных дней — выводов не делаем")
    func notEnoughData() {
        let events = [еда(1, час: 8, граммы: 60), еда(2, час: 8, граммы: 60)]
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .notEnoughData(days: 2))
        #expect(report.suggestedPortionGrams == nil)
    }

    @Test("Ест по норме — менять нечего")
    func onNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 60))
            events.append(еда(день, час: 18, минута: 30, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .onNorm)
        #expect(report.averageGramsPerDay == 120)
        #expect(report.suggestedPortionGrams == nil)
    }

    @Test("Переедание видно и меряется в процентах")
    func overNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 80))
            events.append(еда(день, час: 18, минута: 30, граммы: 80))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .overNorm)
        #expect(report.deviationPercent == 33)
    }

    @Test("Недоедание тоже видно")
    func underNorm() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, минута: 30, граммы: 40))
            events.append(еда(день, час: 18, минута: 30, граммы: 40))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.status == .underNorm)
        #expect(report.deviationPercent < 0)
    }

    @Test("Меньше грамм за раз — меньше во всех кормлениях сразу")
    func portionAppliesToEveryMeal() {
        var events: [LogEvent] = []
        for день in 1...7 {
            events.append(еда(день, час: 7, граммы: 90))
            events.append(еда(день, час: 19, граммы: 90))
        }
        let dog = стич()
        let report = FeedingAnalyzer.report(events: events, dog: dog)

        // Норма 120 г делится на два кормления — по 60 г, а не «уменьшить ужин».
        #expect(report.suggestedPortionGrams == 60)
        #expect(report.suggestedPortionGrams! * dog.mealsPerDay == dog.dailyGrams)
    }

    @Test("Предложенная порция округляется до пяти граммов")
    func portionRoundsToFive() {
        let dog = стич()
        dog.portionGrams = 47
        dog.mealsPerDay = 3
        var events: [LogEvent] = []
        for день in 1...5 {
            for час in [7, 13, 19] { events.append(еда(день, час: час, граммы: 70)) }
        }
        let report = FeedingAnalyzer.report(events: events, dog: dog)
        #expect(report.suggestedPortionGrams! % 5 == 0)
    }

    @Test("Дни без записей в среднее не попадают")
    func emptyDaysAreNotZeroes() {
        var events: [LogEvent] = []
        for день in [1, 2, 3, 8, 9] {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.averageGramsPerDay == 120)
        #expect(report.status == .onNorm)
    }

    @Test("Время кормления берётся из наблюдений, а не из расписания")
    func observedTimes() {
        var events: [LogEvent] = []
        // Кормит около восьми и около семи вечера — плюс-минус двадцать минут.
        for день in 1...7 {
            events.append(еда(день, час: 8, минута: день % 3 * 10, граммы: 60))
            events.append(еда(день, час: 19, минута: день % 2 * 15, граммы: 60))
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.observedMealTimes.count == 2)
        #expect(abs(report.observedMealTimes[0] - 8 * 60) <= 30)
        #expect(abs(report.observedMealTimes[1] - 19 * 60) <= 30)
    }

    @Test("Случайный ночной перекус расписанием не становится")
    func rareMealIsNotSchedule() {
        var events: [LogEvent] = []
        for день in 1...9 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        events.append(еда(4, час: 2, граммы: 10))
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.observedMealTimes.count == 2)
    }

    @Test("Три кормления раскладываются равномерно между первым и последним")
    func threeMealsSpread() {
        let dog = стич()
        dog.mealsPerDay = 3
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 40))
            events.append(еда(день, час: 20, граммы: 40))
        }
        let report = FeedingAnalyzer.report(events: events, dog: dog)
        #expect(report.suggestedMealTimes.count == 3)
        let intervals = zip(report.suggestedMealTimes, report.suggestedMealTimes.dropFirst()).map { $1 - $0 }
        #expect(Set(intervals).count == 1, "интервалы должны быть одинаковыми")
    }

    @Test("Задержка еда → стул считается по медиане")
    func stoolLag() {
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 60))
            let stool = LogEvent(kind: .stool, date: дата(день, час: 9, минута: 30), authorName: "Виктория")
            stool.stoolForm = .sausage
            events.append(stool)
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.stoolLagMinutes == 90)
        #expect(!report.suggestedOutingTimes.isEmpty)
    }

    @Test("Выходы предлагаются после каждого кормления и утром до еды")
    func outingsFollowMeals() {
        var events: [LogEvent] = []
        for день in 1...6 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
            for час in [9, 20] {
                let stool = LogEvent(kind: .stool, date: дата(день, час: час), authorName: "Виктория")
                stool.stoolForm = .sausage
                events.append(stool)
            }
        }
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.suggestedOutingTimes.count >= 3)
        // Утренний выход стоит до первого кормления.
        #expect(report.suggestedOutingTimes.first! < report.suggestedMealTimes.first!)
    }

    @Test("Стич на лечении: кормление внутри окна натощак показывается как конфликт")
    func fastingConflict() {
        // Доза в 07:00, натощак 45 минут → окно 07:00–07:45.
        let conflicts = FeedingAnalyzer.conflicts(
            mealTimes: [7 * 60 + 30, 19 * 60],
            fastingWindows: [(start: 7 * 60, end: 7 * 60 + 45)]
        )
        #expect(conflicts.count == 1)
        #expect(conflicts[0].contains("07:30"))
    }

    @Test("Окно натощак через полночь считается правильно")
    func fastingWindowWrapsMidnight() {
        let conflicts = FeedingAnalyzer.conflicts(
            mealTimes: [23 * 60 + 30, 12 * 60],
            fastingWindows: [(start: 23 * 60, end: 30)]
        )
        #expect(conflicts.count == 1)
    }

    @Test("Сегодняшний день считается отдельно и показывает остаток")
    func todayRemaining() {
        var events: [LogEvent] = []
        for день in 1...5 {
            events.append(еда(день, час: 8, граммы: 60))
            events.append(еда(день, час: 19, граммы: 60))
        }
        events.append(еда(0, час: 8, граммы: 60))
        let report = FeedingAnalyzer.report(events: events, dog: стич())
        #expect(report.todayGrams == 60)
        #expect(report.todayMeals == 1)
        #expect(report.remainingGramsToday == 60)
    }

    @Test("Пустой дневник не роняет отчёт")
    func emptyDiary() {
        let report = FeedingAnalyzer.report(events: [], dog: стич())
        #expect(report.status == .notEnoughData(days: 0))
        #expect(report.todayGrams == 0)
        #expect(report.observedMealTimes.isEmpty)
        #expect(report.conflicts.isEmpty)
    }

    @Test("Без собаки отчёт тоже собирается")
    func noDog() {
        let report = FeedingAnalyzer.report(events: [], dog: nil)
        #expect(report.normGramsPerDay == 0)
        #expect(report.suggestedPortionGrams == nil)
    }
}

@Suite("Режим дня")
@MainActor
struct ScheduleTests {
    private func стич() -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        dog.mealsPerDay = 2
        dog.wakeMinuteOfDay = 7 * 60
        dog.sleepMinuteOfDay = 23 * 60
        return dog
    }

    @Test("Два кормления встают ровно через двенадцать часов")
    func twoMealsSplitTheDay() {
        let dog = стич()   // встаёт в 7:00, ложится в 23:00
        let plan = dog.mealPlan()

        #expect(plan.times == [7 * 60 + 30, 19 * 60 + 30])
        #expect(plan.dayInterval == 12 * 60)
        #expect(plan.nightGap == 12 * 60, "ночь ровно такая же, как день")
        #expect(!plan.hasLongNight)
        #expect(!plan.isCompressed)
    }

    @Test("Ранний подъём двигает всё расписание")
    func earlyRiser() {
        let dog = стич()
        dog.wakeMinuteOfDay = 5 * 60
        dog.sleepMinuteOfDay = 21 * 60

        let times = dog.evenMealTimes()
        #expect(times[0] == 5 * 60 + 30)
        #expect(times.allSatisfy { $0 < 21 * 60 })
    }

    @Test("Три кормления сжимаются в бодрствование, и это видно")
    func threeMealsCompressed() {
        let dog = стич()
        dog.mealsPerDay = 3
        let plan = dog.mealPlan()

        // Идеальный шаг 8 ч дал бы последнее кормление в 23:30 — после отбоя.
        #expect(plan.isCompressed)
        #expect(plan.times.count == 3)
        #expect(plan.times.last! <= MealSchedule.latestMeal(wake: 7 * 60, sleep: 23 * 60))

        let intervals = zip(plan.times, plan.times.dropFirst()).map { $1 - $0 }
        #expect(Set(intervals).count == 1, "между первым и последним — поровну")
    }

    @Test("Одно кормление — одно время, без деления на ноль")
    func singleMeal() {
        let dog = стич()
        dog.mealsPerDay = 1
        #expect(dog.evenMealTimes().count == 1)
    }

    @Test("Ночная смена: отбой после полуночи считается правильно")
    func nightShift() {
        let dog = стич()
        dog.wakeMinuteOfDay = 10 * 60
        dog.sleepMinuteOfDay = 2 * 60

        #expect(dog.awakeMinutes == 16 * 60)
        let plan = dog.mealPlan()
        #expect(plan.times.allSatisfy { (0..<(24 * 60)).contains($0) })
        #expect(plan.nightGap > 0 && plan.nightGap < 24 * 60)
    }

    @Test("Черновик и модель говорят одно и то же")
    func draftMatchesDog() {
        let dog = стич()
        var draft = ScheduleDraft.from(dog)
        draft.mealsPerDay = 3
        draft.portionGrams = 45
        draft.apply(to: dog)

        #expect(dog.mealsPerDay == 3)
        #expect(dog.portionGrams == 45)
        #expect(dog.dailyGrams == 135)
        #expect(dog.mealTimes == draft.evenMealTimes)
    }

    @Test("Ручная раскладка не пересчитывается")
    func manualTimesStay() {
        var draft = ScheduleDraft()
        draft.mealsPerDay = 2
        draft.mealTimes = [6 * 60, 20 * 60]
        draft.isManual = true

        #expect(draft.effectiveMealTimes == [6 * 60, 20 * 60])
    }

    @Test("Сменил число кормлений — предлагаем ровное расписание заново")
    func suggestionFollowsWindow() {
        let dog = стич()
        dog.mealsPerDay = 3
        dog.wakeMinuteOfDay = 6 * 60
        dog.sleepMinuteOfDay = 22 * 60

        let suggested = FeedingAnalyzer.suggestedMealTimes(
            observed: [8 * 60, 19 * 60],
            normMeals: 3,
            days: [],
            awakeWindow: (wake: dog.wakeMinuteOfDay, sleep: dog.sleepMinuteOfDay)
        )
        #expect(suggested.count == 3)
        #expect(suggested[0] == 6 * 60 + 30)
        #expect(MealSchedule.nightGap(suggested) < 24 * 60)
    }

    @Test("Если человек уже кормит столько раз, сколько собирался, ритм не ломаем")
    func keepsExistingRhythm() {
        let suggested = FeedingAnalyzer.suggestedMealTimes(
            observed: [8 * 60, 19 * 60],
            normMeals: 2,
            days: [],
            awakeWindow: (wake: 7 * 60, sleep: 23 * 60)
        )
        #expect(suggested == [8 * 60, 19 * 60])
    }
}


@Suite("Раскладка кормлений по суткам")
struct MealScheduleTests {
    @Test("Ночь считается как промежуток по кругу суток")
    func nightGapWrapsMidnight() {
        #expect(MealSchedule.nightGap([7 * 60 + 30, 19 * 60 + 30]) == 12 * 60)
        #expect(MealSchedule.nightGap([8 * 60, 22 * 60]) == 10 * 60)
        #expect(MealSchedule.nightGap([9 * 60]) == 24 * 60, "одно кормление — ровно сутки")
    }

    @Test("Дневной промежуток берётся самый короткий")
    func dayIntervalIsShortest() {
        #expect(MealSchedule.dayInterval([8 * 60, 13 * 60, 21 * 60]) == 5 * 60)
        #expect(MealSchedule.dayInterval([8 * 60]) == nil)
    }

    @Test("Четыре кормления не выходят за окно бодрствования")
    func fourMealsStayAwake() {
        let plan = MealSchedule.plan(mealsPerDay: 4, wake: 7 * 60, sleep: 23 * 60)
        let latest = MealSchedule.latestMeal(wake: 7 * 60, sleep: 23 * 60)

        #expect(plan.times.count == 4)
        #expect(plan.times.first! == 7 * 60 + 30)
        #expect(plan.times.last! == latest)
        #expect(plan.isCompressed)
    }

    @Test("Ранний подъём и поздний отбой дают ровные сутки на трёх кормлениях")
    func longDayFitsIdealStep() {
        // Бодрствует 18 часов: идеальный шаг восемь часов влезает целиком.
        let plan = MealSchedule.plan(mealsPerDay: 3, wake: 5 * 60, sleep: 23 * 60)

        #expect(!plan.isCompressed)
        #expect(plan.dayInterval == 8 * 60)
        #expect(plan.nightGap == 8 * 60, "ночь такая же, как день")
    }

    @Test("Одно кормление в день не роняет расчёт")
    func singleMeal() {
        let plan = MealSchedule.plan(mealsPerDay: 1, wake: 7 * 60, sleep: 23 * 60)
        #expect(plan.times == [7 * 60 + 30])
        #expect(plan.dayInterval == nil)
        #expect(plan.nightGap == 24 * 60)
        #expect(plan.hasLongNight)
    }

    @Test("Долгая ночь помечается")
    func longNightFlagged() {
        // Короткий день: встаёт в 9, ложится в 20 — ночь получается длинной.
        let plan = MealSchedule.plan(mealsPerDay: 2, wake: 9 * 60, sleep: 20 * 60)
        #expect(plan.nightGap > MealSchedule.longNightThreshold)
        #expect(plan.hasLongNight)
    }

    @Test("Последнее кормление всегда с запасом до сна")
    func lastMealLeavesTimeBeforeSleep() {
        for meals in 1...5 {
            let plan = MealSchedule.plan(mealsPerDay: meals, wake: 7 * 60, sleep: 23 * 60)
            let gapToSleep = MealSchedule.forward(from: plan.times.last!, to: 23 * 60)
            #expect(gapToSleep >= MealSchedule.beforeSleep,
                    "\(meals) кормлений: нужно успеть погулять перед сном")
        }
    }

    @Test("Сумма всех промежутков — ровно сутки")
    func gapsAddUpToDay() {
        for meals in 2...5 {
            let plan = MealSchedule.plan(mealsPerDay: meals, wake: 6 * 60, sleep: 22 * 60)
            let gaps = zip(plan.times, plan.times.dropFirst())
                .map { MealSchedule.forward(from: $0, to: $1) }
            #expect(gaps.reduce(0, +) + plan.nightGap == MealSchedule.minutesInDay)
        }
    }
}

@Suite("Запас корма и цикл")
@MainActor
struct BagAndHeatTests {
    private let calendar = Calendar.current

    private func днейНазад(_ дней: Int) -> Date {
        calendar.date(byAdding: .day, value: -дней, to: .now)!
    }

    @Test("Сухой корм считается мешками")
    func dryStockMath() {
        // Мешок 3 кг при 120 г в день — двадцать пять дней.
        let мешок = FoodStock(kind: .dry, packGrams: 3000, packsLeft: 1, gramsPerDay: 120)

        #expect(мешок.remainingGrams() == 3000)
        #expect(мешок.daysLeft() == 25)
        #expect(!мешок.needsRestock())
    }

    @Test("Влажный считается банками, и это осмысленная цифра")
    func wetStockMath() {
        // Двенадцать банок по 400 г, съедает 800 г в день — две банки в день.
        let банки = FoodStock(kind: .wet, packGrams: 400, packsLeft: 12, gramsPerDay: 800)

        #expect(банки.daysLeft() == 6)
        #expect(банки.packsPerDay == 2)
        #expect(банки.needsRestock(), "меньше недели — пора покупать")
    }

    @Test("Початый мешок считается дробным")
    func partialPack() {
        let мешок = FoodStock(kind: .dry, packGrams: 6000, packsLeft: 0.5, gramsPerDay: 300)
        #expect(мешок.remainingGrams() == 3000)
        #expect(мешок.daysLeft() == 10)
    }

    @Test("Сколько упаковок купить на месяц — с учётом остатка")
    func packsNeeded() {
        // Съедает 100 г в день, банки по 300 г, осталось 5 банок.
        // На 30 дней нужно 3000 г, есть 1500 — не хватает 1500, это 5 банок.
        let банки = FoodStock(kind: .wet, packGrams: 300, packsLeft: 5, gramsPerDay: 100)
        #expect(банки.packsNeeded(forDays: 30) == 5)
    }

    @Test("Если запаса хватает, покупать нечего")
    func nothingToBuy() {
        let мешок = FoodStock(kind: .dry, packGrams: 12000, packsLeft: 1, gramsPerDay: 100)
        #expect(мешок.packsNeeded(forDays: 30) == 0)
    }

    @Test("Пустой запас не уходит в минус и не делит на ноль")
    func emptyStock() {
        let пусто = FoodStock(kind: .dry, packGrams: 3000, packsLeft: 0, gramsPerDay: 120)
        #expect(пусто.remainingGrams() == 0)
        #expect(пусто.daysLeft() == 0)

        let безнормы = FoodStock(kind: .wet, packGrams: 400, packsLeft: 10, gramsPerDay: 0)
        #expect(безнормы.daysLeft() == nil)
        #expect(безнормы.runsOutOn() == nil)
        #expect(безнормы.packsNeeded(forDays: 30) == 0)
    }

    @Test("Фасовки у сухого и влажного разные")
    func packSizesDiffer() {
        #expect(FoodKind.wet.commonPackSizes.contains(100))
        #expect(FoodKind.wet.commonPackSizes.contains(500))
        #expect(FoodKind.wet.commonPackSizes.allSatisfy { $0 <= 500 })
        #expect(FoodKind.dry.commonPackSizes.contains(3000))
        #expect(FoodKind.dry.commonPackSizes.contains(15000))
    }

    @Test("Про влажный корм приложение обязано предупредить")
    func wetCaution() {
        #expect(FoodKind.wet.caution != nil, "граммы сухого и влажного не равны")
        #expect(FoodKind.dry.caution == nil)
    }

    @Test("Смешанное кормление: закончится то, что закончится раньше")
    func mixedFeeding() {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        let сухой = FoodStock(kind: .dry, brand: "Acana", packGrams: 3000, packsLeft: 1, gramsPerDay: 60)
        let влажный = FoodStock(kind: .wet, brand: "Паучи", packGrams: 100, packsLeft: 6, gramsPerDay: 60)
        сухой.dog = dog
        влажный.dog = dog

        let план = FoodPlanner.plan([сухой, влажный])
        #expect(план.totalGramsPerDay == 120)
        #expect(план.whatRunsOutFirst == "Паучи", "их хватит на 10 дней против пятидесяти")
        #expect(план.needsRestock == false)
    }

    @Test("Норму можно задать с любого конца")
    func normFromEitherEnd() {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        dog.mealsPerDay = 2
        #expect(dog.dailyGrams == 120)
        #expect(!dog.usesDailyNorm)

        // Врач назвал дневную норму — она главнее, а порция считается из неё.
        dog.dailyNormGrams = 150
        #expect(dog.dailyGrams == 150)
        #expect(dog.usesDailyNorm)
        #expect(dog.derivedPortionGrams == 75)
    }

    @Test("Порция из дневной нормы округляется до пяти граммов")
    func derivedPortionRounds() {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.mealsPerDay = 3
        dog.dailyNormGrams = 200
        #expect(dog.derivedPortionGrams % 5 == 0)
        #expect(dog.derivedPortionGrams == 65)
    }

    @Test("Одной записи о течке мало для среднего — и приложение это признаёт")
    func heatSingleRecord() {
        let forecast = HeatCycle.forecast([HeatRecord(startedAt: днейНазад(30))])

        #expect(forecast.averageIntervalDays == nil)
        #expect(forecast.isEstimate, "ориентир, а не расчёт")
        #expect(forecast.daysUntilNext == HeatCycle.typicalIntervalDays - 30)
    }

    @Test("По двум записям считается её собственный промежуток")
    func heatAverage() {
        let records = [
            HeatRecord(startedAt: днейНазад(400)),
            HeatRecord(startedAt: днейНазад(200)),
        ]
        let forecast = HeatCycle.forecast(records)

        #expect(forecast.averageIntervalDays == 200)
        #expect(!forecast.isEstimate)
        #expect(forecast.daysUntilNext == 0)
    }

    @Test("Без записей ничего не выдумываем")
    func heatEmpty() {
        let forecast = HeatCycle.forecast([])
        #expect(forecast.lastStart == nil)
        #expect(forecast.expectedNext == nil)
        #expect(forecast.daysUntilNext == nil)
    }

    @Test("Цикл нужен только нестерилизованной девочке")
    func heatTrackingApplies() {
        let девочка = Dog(name: "Ася", weightKg: 12)
        девочка.sex = .female
        #expect(девочка.tracksHeat)

        девочка.isNeutered = true
        #expect(!девочка.tracksHeat)

        let стич = Dog(name: "Стич", weightKg: 4.1)
        стич.sex = .male
        #expect(!стич.tracksHeat)
    }

    @Test("Идущая течка знает свой день")
    func ongoingHeat() {
        let запись = HeatRecord(startedAt: днейНазад(5))
        #expect(запись.isOngoing)
        #expect(запись.dayNumber() == 6)
        #expect(запись.dayCount == nil)

        запись.endedAt = Date()
        #expect(!запись.isOngoing)
        #expect(запись.dayCount == 6)
    }
}
