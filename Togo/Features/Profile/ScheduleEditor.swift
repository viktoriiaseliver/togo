import SwiftUI

/// Режим дня и питания. Один компонент — и в онбординге, и в профиле:
/// человек настраивает это один раз, а меняет там, где привык.
///
/// Работает с черновиком, а не с моделью: в онбординге собаки ещё нет,
/// а в профиле правку не хочется писать в базу на каждое касание степпера.
struct ScheduleDraft: Equatable {
    /// С какого конца человек считает норму. Оба способа встречаются
    /// одинаково часто: на упаковке пишут дневную норму, а отмеряют
    /// обычно порцию за раз.
    enum NormEntry: String, CaseIterable {
        case perServing
        case perDay

        var title: String {
            switch self {
            case .perServing: "Считаю за раз"
            case .perDay: "Знаю дневную норму"
            }
        }
    }

    /// Только способ ввода: какой шаговик человек видит. На хранение
    /// не влияет — число всё равно одно.
    var normEntry: NormEntry = .perServing
    var mealsPerDay: Int = 2
    /// Сколько собака съедает за сутки. Одно число, как и в модели.
    var dailyGrams: Int = 120
    var wakeMinuteOfDay: Int = 7 * 60
    var sleepMinuteOfDay: Int = 23 * 60
    var mealTimes: [Int] = []
    /// Времена расставлены вручную — тогда приложение их не пересчитывает.
    var isManual: Bool = false

    /// Порция за раз: норма, поделённая на число кормлений.
    var servingGrams: Int {
        guard mealsPerDay > 0 else { return dailyGrams }
        return max(5, Int((Double(dailyGrams) / Double(mealsPerDay) / 5).rounded()) * 5)
    }

    var awakeMinutes: Int {
        let span = sleepMinuteOfDay - wakeMinuteOfDay
        return span > 0 ? span : span + 24 * 60
    }

    /// Раскладка по суткам целиком: считает и ночной перерыв тоже.
    var plan: MealSchedule.Plan {
        MealSchedule.plan(mealsPerDay: mealsPerDay,
                          wake: wakeMinuteOfDay,
                          sleep: sleepMinuteOfDay)
    }

    var evenMealTimes: [Int] { plan.times }

    var effectiveMealTimes: [Int] {
        isManual && mealTimes.count == mealsPerDay ? mealTimes.sorted() : evenMealTimes
    }

    /// Что получилось на самом деле — с учётом ручных правок.
    var effectivePlan: MealSchedule.Plan {
        let times = effectiveMealTimes
        return MealSchedule.Plan(
            times: times,
            dayInterval: MealSchedule.dayInterval(times),
            nightGap: MealSchedule.nightGap(times),
            isCompressed: plan.isCompressed
        )
    }

    static func from(_ dog: Dog) -> ScheduleDraft {
        var draft = ScheduleDraft()
        draft.mealsPerDay = dog.mealsPerDay
        draft.dailyGrams = dog.dailyGrams
        draft.wakeMinuteOfDay = dog.wakeMinuteOfDay
        draft.sleepMinuteOfDay = dog.sleepMinuteOfDay
        draft.mealTimes = dog.mealTimes
        draft.isManual = dog.mealTimes.sorted() != dog.evenMealTimes()
        return draft
    }

    func apply(to dog: Dog) {
        dog.mealsPerDay = max(1, mealsPerDay)
        dog.setDailyGrams(dailyGrams)
        dog.syncSingleFoodShare()
        dog.wakeMinuteOfDay = wakeMinuteOfDay
        dog.sleepMinuteOfDay = sleepMinuteOfDay
        dog.mealTimes = effectiveMealTimes
    }
}

/// Figma: `ScheduleEditor`. Родительский блок из четырёх дочерних карточек;
/// наружу отдаёт только черновик.
struct ScheduleEditor: View {
    @Binding var draft: ScheduleDraft
    /// В онбординге пояснений больше: человек видит это впервые.
    var isVerbose: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Spacing.stack) {
            dayCard
            mealsCard
            timesCard
            if isVerbose { explainerCard }
        }
    }

    // MARK: День

    private var dayCard: some View {
        TGCard {
            TGSectionHeader(title: "день собаки",
                            subtitle: "из этого окна раскладываются кормления и выходы")
            TimePickerRow(title: "Встаёт", minuteOfDay: $draft.wakeMinuteOfDay)
            TGDivider()
            TimePickerRow(title: "Ложится", minuteOfDay: $draft.sleepMinuteOfDay)
            TGDivider()
            HStack {
                Text("Бодрствует").textStyle(AppFont.body)
                Spacer(minLength: Token.Space.s8)
                Text(Fmt.duration(Double(draft.awakeMinutes) * 60))
                    .textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
            }
            .frame(minHeight: Token.Size.tapTarget)
        }
    }

    // MARK: Сколько раз и по сколько

    private var mealsCard: some View {
        TGCard {
            TGSectionHeader(title: "еда")
            Stepper(value: $draft.mealsPerDay, in: 1...5) {
                HStack {
                    Text("Сколько раз в день").textStyle(AppFont.body)
                    Spacer(minLength: Token.Space.s8)
                    Text("\(draft.mealsPerDay)").textStyle(AppFont.numeric(17))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            .onChange(of: draft.mealsPerDay) { _, _ in
                // Изменили число кормлений — ручная раскладка больше не годится.
                draft.isManual = false
            }

            TGDivider()
            TGChipGroup(items: ScheduleDraft.NormEntry.allCases, title: \.title,
                        isSelected: { $0 == draft.normEntry },
                        minimumWidth: 150) { draft.normEntry = $0 }
                .padding(.vertical, Token.Space.s8)

            // Оба шаговика правят одно и то же число — просто с разных
            // концов. Раньше это были два разных поля, и они расходились.
            TGDivider()
            if draft.normEntry == .perServing {
                amountRow(title: "Грамм за раз", grams: draft.servingGrams,
                          step: 5, range: 5...600) { draft.dailyGrams = $0 * max(1, draft.mealsPerDay) }
                TGDivider()
                totalRow(title: "Выходит в день", grams: draft.dailyGrams)
            } else {
                amountRow(title: "Норма в день", grams: draft.dailyGrams,
                          step: 10, range: 10...2000) { draft.dailyGrams = $0 }
                TGDivider()
                totalRow(title: "Значит за раз", grams: draft.servingGrams)
            }
            TGExplainer(text: "Порция — это норма, делённая на кормления. Добавишь кормление — дневная еда не изменится, изменится только порция. Норму называет врач или упаковка, приложение её не выдумывает. У влажного корма граммы другие: он на три четверти вода.")
        }
    }

    /// Шаговик с граммами. Значение приходит посчитанным, а наружу
    /// отдаётся то, что человек накрутил, — правит его всегда `dailyGrams`.
    private func amountRow(title: String, grams: Int, step: Int,
                           range: ClosedRange<Int>,
                           set: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { grams }, set: set), in: range, step: step) {
            HStack {
                Text(title).textStyle(AppFont.body)
                Spacer(minLength: Token.Space.s8)
                Text("\(grams) г").textStyle(AppFont.numeric(17))
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    /// Вторая половина той же арифметики — её показывают, но не правят.
    private func totalRow(title: String, grams: Int) -> some View {
        HStack {
            Text(title).textStyle(AppFont.bodyEmphasis)
            Spacer(minLength: Token.Space.s8)
            Text("\(grams) г").textStyle(AppFont.numeric(20))
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    // MARK: Во сколько

    private var timesCard: some View {
        TGCard {
            HStack {
                TGSectionHeader(
                    title: "во сколько кормить",
                    subtitle: draft.isManual ? "расставлено вручную" : scheduleSubtitle
                )
                if draft.isManual {
                    Button("Разложить ровно") {
                        draft.isManual = false
                        draft.mealTimes = draft.evenMealTimes
                        Haptics.tap()
                    }
                    .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
                }
            }

            ForEach(Array(draft.effectiveMealTimes.enumerated()), id: \.offset) { index, minute in
                TimePickerRow(
                    title: mealName(index),
                    minuteOfDay: Binding(
                        get: { minute },
                        set: { setMealTime($0, at: index) }
                    )
                )
                if index != draft.effectiveMealTimes.count - 1 { TGDivider() }
            }

            TGDivider()
            rhythmRow
        }
    }

    private var scheduleSubtitle: String {
        guard let interval = draft.effectivePlan.dayInterval else { return "одно кормление" }
        return "ровно через \(Fmt.duration(Double(interval) * 60))"
    }

    /// Ночь — тоже промежуток между кормлениями, и обычно самый длинный.
    /// Показываем его рядом с дневным: иначе человек его просто не видит.
    @ViewBuilder
    private var rhythmRow: some View {
        let plan = draft.effectivePlan
        if plan.times.count > 1 {
            HStack(spacing: 0) {
                TGStat(value: plan.dayInterval.map { Fmt.duration(Double($0) * 60) } ?? "—",
                       caption: "днём между едой", size: 17)
                TGStat(value: Fmt.duration(Double(plan.nightGap) * 60),
                       caption: "ночной перерыв", size: 17)
            }

            if plan.hasLongNight {
                TGBanner(
                    tone: .waiting,
                    title: "Ночь длиннее \(Fmt.duration(Double(MealSchedule.longNightThreshold) * 60))",
                    subtitle: "Долгий перерыв натощак у части собак даёт утреннюю рвоту желчью. Сдвинь последнее кормление позже или добавь ещё одно. Это наблюдение, а не назначение: сверь с врачом.",
                    systemImage: "moon"
                )
            } else if let overhang = plan.nightOverhang, overhang <= 60 {
                TGExplainer(text: "Промежутки ровные и днём, и ночью — собаке так спокойнее всего.")
            }

            if plan.isCompressed {
                TGExplainer(text: "Ровный шаг по суткам не влезает в окно бодрствования: кормления разложены поровну между первым и последним, а ночь выходит длиннее. Выровнять можно только одним — вставать раньше или ложиться позже.")
            }
        }
    }

    private func mealName(_ index: Int) -> String {
        let count = draft.effectiveMealTimes.count
        if count == 1 { return "Кормление" }
        if index == 0 { return "Первое" }
        if index == count - 1 { return "Последнее" }
        return "\(index + 1)-е"
    }

    private func setMealTime(_ minute: Int, at index: Int) {
        var times = draft.effectiveMealTimes
        guard times.indices.contains(index) else { return }
        times[index] = minute
        draft.mealTimes = times
        draft.isManual = true
    }

    private var explainerCard: some View {
        TGCard {
            Text("Это можно поменять когда угодно").textStyle(AppFont.cardTitle)
            Text("«Настройки → собака → Питание и режим». Приложение сравнит это с тем, как ты кормишь на самом деле, и скажет, если Стич переедает.")
                .textStyle(AppFont.caption)
        }
    }
}

/// Figma: `TimePickerRow`. Строка «подпись — время» на системном пикере:
/// своих колёс времени в приложении нет.
struct TimePickerRow: View {
    let title: String
    @Binding var minuteOfDay: Int

    private var date: Date {
        Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                              second: 0, of: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { date },
                set: { newValue in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.compact)
        .textStyle(AppFont.body)
        .frame(minHeight: Token.Size.tapTarget)
    }
}
