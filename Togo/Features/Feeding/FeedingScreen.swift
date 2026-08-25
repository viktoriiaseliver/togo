import SwiftUI
import SwiftData
import Charts

/// Питание и режим · сколько, сколько раз и во сколько.
///
/// Экран отвечает на один вопрос: расходится ли то, что записано, с нормой,
/// которую назвал врач. Своей нормы приложение не выдумывает и целей
/// по проценту не ставит.
struct FeedingScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Query private var allStocks: [FoodStock]
    @State private var now = Date()

    private var stocks: [FoodStock] {
        guard let dog else { return [] }
        return allStocks.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }
    @State private var isApplyingPortion = false

    /// Отчёт считается один раз и лежит в состоянии.
    ///
    /// Раньше это было вычисляемое свойство: SwiftUI дёргал его по четыре
    /// раза за перерисовку, и каждый раз он проходил две недели записей.
    /// На годовом дневнике это уже заметно пальцами.
    @State private var report: FeedingReport = .empty

    private func rebuildReport() {
        report = FeedingAnalyzer.report(
            events: dog?.events ?? [],
            dog: dog,
            now: now,
            fastingWindows: fastingWindows
        )
    }

    /// Окна натощак берутся из активных схем: у собаки на лечении
    /// расписание кормления обязано с ними считаться.
    private var fastingWindows: [(start: Int, end: Int)] {
        guard let dog, dog.isOnTreatment else { return [] }
        return dog.medications
            .filter { $0.fastingMinutes > 0 && !$0.isPaused }
            .flatMap { medication in
                medication.times.map { start in
                    (start: start, end: (start + medication.fastingMinutes) % (24 * 60))
                }
            }
    }

    var body: some View {
        TGScreen {
            if dog == nil {
                EmptyStateCard(
                    systemImage: "fork.knife",
                    title: "Собаки пока нет",
                    message: "Добавь собаку — и приложение начнёт считать, сколько она ест и во сколько.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                todayCard
                stockCard
                statusCard
                chartCard
                scheduleCard
                if report.stoolLagMinutes != nil { outingsCard }
                if !report.conflicts.isEmpty { conflictsCard }
                portionCard
            }
        }
        .navigationTitle("Питание")
        .navigationBarTitleDisplayMode(.large)
        .task {
            now = Date()
            rebuildReport()
        }
        .onChange(of: dog?.events.count) { _, _ in rebuildReport() }
        .onChange(of: dog?.portionGrams) { _, _ in rebuildReport() }
        .onChange(of: dog?.mealsPerDay) { _, _ in rebuildReport() }
    }

    // MARK: Сегодня

    private var todayCard: some View {
        TGCard {
            TGSectionHeader(title: "сегодня")
            HStack(spacing: 0) {
                TGStat(value: "\(report.todayGrams) г",
                       caption: report.normGramsPerDay > 0 ? "из \(report.normGramsPerDay)" : "съел")
                TGStat(value: "\(report.todayMeals)",
                       caption: report.normMealsPerDay > 0 ? "из \(report.normMealsPerDay) кормлений" : "кормлений")
                TGStat(value: "\(report.remainingGramsToday) г", caption: "осталось")
            }
            if let next = nextMealTime {
                TGDivider()
                Text("Следующее кормление примерно в \(Fmt.clock(minuteOfDay: next)).")
                    .textStyle(AppFont.caption)
            }
        }
    }

    private var nextMealTime: Int? {
        let minute = FeedingAnalyzer.minuteOfDay(now)
        let schedule = report.suggestedMealTimes.isEmpty ? (dog?.mealTimes ?? []) : report.suggestedMealTimes
        return schedule.sorted().first { $0 > minute } ?? schedule.sorted().first
    }

    // MARK: Запас корма

    private var plan: FoodPlan {
        FoodPlanner.plan(stocks, from: now)
    }

    @ViewBuilder
    private var stockCard: some View {
        if let dog {
            TGCard {
                TGSectionHeader(
                    title: "запас корма",
                    subtitle: stocks.isEmpty ? nil : planSubtitle
                )

                if stocks.isEmpty {
                    TGExplainer(text: "Впиши, чем кормишь и в какой фасовке — приложение посчитает, на сколько хватит, и напомнит за неделю до конца. Сухой считается мешками, влажный — банками.")
                } else {
                    ForEach(stocks) { stock in
                        StockRow(stock: stock, now: now)
                        if stock.id != stocks.last?.id { TGDivider() }
                    }
                    if plan.needsRestock {
                        TGBanner(tone: .waiting, title: "Пора покупать",
                                 subtitle: restockText(dog),
                                 systemImage: "cart")
                    }
                }

                NavigationLink { FoodStockScreen(dog: dog) } label: {
                    TGListRow(title: stocks.isEmpty ? "Записать корм" : "Поправить запас",
                              systemImage: "shippingbox")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planSubtitle: String? {
        guard let out = plan.firstRunOut, let what = plan.whatRunsOutFirst else { return nil }
        return "\(what) закончится \(Fmt.shortDay(out))"
    }

    private func restockText(_ dog: Dog) -> String {
        let нужно = stocks
            .filter(\.needsRestock)
            .map { stock -> String in
                let packs = stock.packsNeeded(forDays: FoodPlanner.planningDays)
                let unit = stock.kind.unitName(count: Double(packs))
                let name = stock.brand.isEmpty ? stock.kind.title.lowercased() : stock.brand
                return "\(name): \(packs) \(unit) на месяц"
            }
        return нужно.joined(separator: " · ")
    }

    // MARK: Норма и отклонение

    private var statusCard: some View {
        Group {
            switch report.status {
            case .notEnoughData(let days):
                TGCard {
                    Text(report.status.title).textStyle(AppFont.cardTitle)
                    Text("Полных дней с записями: \(days). Нужно хотя бы \(FeedingAnalyzer.minimumCompleteDays), иначе среднее врёт. Просто продолжай отмечать еду — считать приложение начнёт само.")
                        .textStyle(AppFont.caption)
                }
            case .onNorm:
                TGBanner(tone: .done, title: report.status.title,
                         subtitle: "В среднем \(Int(report.averageGramsPerDay)) г в день при норме \(report.normGramsPerDay) г. Менять нечего.",
                         systemImage: "checkmark.seal")
            case .overNorm:
                TGBanner(tone: .waiting, title: report.status.title,
                         subtitle: "В среднем \(Int(report.averageGramsPerDay)) г в день — на \(report.deviationPercent)% больше нормы. Это не срочно, но за две недели складывается в лишний вес.",
                         systemImage: "arrow.up.right")
            case .underNorm:
                TGBanner(tone: .waiting, title: report.status.title,
                         subtitle: "В среднем \(Int(report.averageGramsPerDay)) г в день — на \(abs(report.deviationPercent))% меньше нормы. Если он при этом бодр и вес держится, это не беда; если вес падает — к врачу.",
                         systemImage: "arrow.down.right")
            }
        }
    }

    // MARK: График

    private var chartCard: some View {
        TGCard {
            Text("Две недели").textStyle(AppFont.cardTitle)
            Chart {
                ForEach(report.days) { day in
                    BarMark(
                        x: .value("День", day.date, unit: .day),
                        y: .value("Граммы", day.grams)
                    )
                    .foregroundStyle(day.grams > report.normGramsPerDay ? Token.Status.waitingText : Token.Ink.silhouette)
                    .cornerRadius(2)
                }
                if report.normGramsPerDay > 0 {
                    RuleMark(y: .value("Норма", report.normGramsPerDay))
                        .foregroundStyle(Token.Action.done)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("норма \(report.normGramsPerDay) г")
                                .textStyle(AppFont.micro.color(Token.Action.done))
                        }
                }
            }
            .frame(height: 150)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Token.Surface.hairline)
                    AxisValueLabel().foregroundStyle(Token.Ink.faint)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Token.Ink.faint)
                }
            }
            TGExplainer(text: "Дни без записей в среднее не попадают: пустой день — это «дневник не вели», а не «не ел».")
        }
    }

    // MARK: Расписание

    private var scheduleCard: some View {
        TGCard {
            TGSectionHeader(title: "во сколько ест",
                            subtitle: "слева — по наблюдениям, справа — что предлагаем")
            if report.observedMealTimes.isEmpty {
                TGExplainer(text: "Записей о еде пока нет. Отметь пару кормлений — и приложение увидит его режим само.")
            } else {
                ForEach(Array(zip(paddedObserved, paddedSuggested)).indices, id: \.self) { index in
                    HStack {
                        Text(paddedObserved[index].map { Fmt.clock(minuteOfDay: $0) } ?? "—")
                            .textStyle(AppFont.numeric(17))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Token.Ink.faint)
                            .accessibilityHidden(true)
                        Spacer()
                        Text(paddedSuggested[index].map { Fmt.clock(minuteOfDay: $0) } ?? "—")
                            .textStyle(AppFont.numeric(17).color(Token.Action.done))
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGButton(title: "Поставить это расписание", variant: .secondary, size: .medium,
                         isEnabled: !report.suggestedMealTimes.isEmpty) {
                    applySchedule()
                }
                if let dog {
                    NavigationLink { ScheduleScreen(dog: dog) } label: {
                        TGListRow(title: "Настроить режим вручную", systemImage: "clock")
                    }
                    .buttonStyle(.plain)
                }
            }
            if let dog {
                TGDivider()
                let plan = MealSchedule.plan(mealsPerDay: dog.mealsPerDay,
                                             wake: dog.wakeMinuteOfDay,
                                             sleep: dog.sleepMinuteOfDay)
                HStack(spacing: 0) {
                    TGStat(value: plan.dayInterval.map { Fmt.duration(Double($0) * 60) } ?? "—",
                           caption: "днём между едой", size: 17)
                    TGStat(value: Fmt.duration(Double(plan.nightGap) * 60),
                           caption: "ночной перерыв", size: 17)
                }
                if plan.hasLongNight {
                    TGExplainer(text: "Ночной перерыв длинный. У части собак это даёт утреннюю рвоту желчью — если такое бывает, сдвинь последнее кормление позже или добавь ещё одно.")
                }
            }
            TGExplainer(text: "Ровный интервал между кормлениями важнее точного часа: собака привыкает к промежутку, а не к цифре на часах. Ночь считается так же, как день.")
        }
    }

    private var paddedObserved: [Int?] {
        pad(report.observedMealTimes, to: max(report.observedMealTimes.count, report.suggestedMealTimes.count))
    }

    private var paddedSuggested: [Int?] {
        pad(report.suggestedMealTimes, to: max(report.observedMealTimes.count, report.suggestedMealTimes.count))
    }

    private func pad(_ values: [Int], to count: Int) -> [Int?] {
        values.map(Optional.init) + Array(repeating: nil, count: max(0, count - values.count))
    }

    // MARK: Выходы

    private var outingsCard: some View {
        TGCard {
            TGSectionHeader(title: "когда выводить")
            if let lag = report.stoolLagMinutes {
                Text("После еды до стула у него в среднем \(Fmt.duration(Double(lag) * 60)).")
                    .textStyle(AppFont.body)
            }
            HStack(spacing: Token.Space.s8) {
                ForEach(report.suggestedOutingTimes, id: \.self) { time in
                    Text(Fmt.clock(minuteOfDay: time))
                        .textStyle(AppFont.numeric(15))
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
                        .background(Token.Surface.sunken,
                                    in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                }
            }
            TGExplainer(text: "Это ориентиры из его же записей, а не расписание. Просится раньше — выводи раньше: вердикт и эти часы не спорят с человеком.")
        }
    }

    // MARK: Конфликты

    private var conflictsCard: some View {
        TGCard {
            TGBanner(tone: .alarm, title: "Расписание спорит с лечением",
                     subtitle: "Приложение показывает конфликт, но само ничего не двигает: это решается с врачом.",
                     systemImage: "exclamationmark.triangle")
            ForEach(report.conflicts, id: \.self) { line in
                Text("• " + line).textStyle(AppFont.caption)
            }
        }
    }

    // MARK: Порция

    private var portionCard: some View {
        TGCard {
            TGSectionHeader(title: "порция",
                            subtitle: "порция одна на все кормления — уменьшив её, уменьшаешь весь день")
            if let dog {
                Stepper(value: Binding(get: { dog.portionGrams }, set: { setPortion($0, on: dog) }),
                        in: 5...600, step: 5) {
                    HStack {
                        Text("Грамм за раз").textStyle(AppFont.body)
                        Spacer()
                        Text("\(dog.portionGrams) г").textStyle(AppFont.numeric(17))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                HStack {
                    Text("Выходит в день").textStyle(AppFont.body)
                    Spacer()
                    Text("\(dog.dailyGrams) г").textStyle(AppFont.numeric(17))
                }
                .frame(minHeight: Token.Size.tapTarget)

                if let suggested = report.suggestedPortionGrams, suggested != dog.portionGrams {
                    TGBanner(tone: .waiting,
                             title: "Предлагаем \(suggested) г за раз",
                             subtitle: "Это ровно норма, разделённая на \(dog.mealsPerDay) кормления. Меняется сразу для всех приёмов — отдельных порций у приложения нет.",
                             systemImage: "equal.circle")
                    TGButton(title: "Поставить \(suggested) г", variant: .secondary, size: .medium) {
                        setPortion(suggested, on: dog)
                    }
                }
                TGExplainer(text: "Дозировки и норму сверяй с врачом. Приложение только считает то, что вы сами записали.")
            }
        }
    }

    private func setPortion(_ grams: Int, on dog: Dog) {
        dog.portionGrams = grams
        Haptics.tap()
    }

    private func applySchedule() {
        guard let dog else { return }
        dog.mealTimes = report.suggestedMealTimes
        dog.mealsPerDay = max(1, report.suggestedMealTimes.count)
        Haptics.success()
    }
}



