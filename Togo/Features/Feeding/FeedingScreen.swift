import SwiftUI
import SwiftData
import Charts

/// Питание и режим · сколько, сколько раз и во сколько.
///
/// Экран отвечает на один вопрос: расходится ли то, что записано, с нормой,
/// которую назвал врач. Своей нормы приложение не выдумывает и целей
/// по проценту не ставит.
///
/// # Редизайн iOS 28, кадр 13 «Питание и режим»
///
/// Собрано по кадру `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/13.png`,
/// решение Виктории 22.10.2026. На кадре **четыре блока**, и порядок
/// у них не случайный — он отвечает на вопросы в том порядке, в каком
/// их задают:
///
/// ```
/// 1  плашка «Кормить можно» / «Сейчас кормить нельзя»   можно ли ПРЯМО СЕЙЧАС
/// 2  «НОРМА ВРАЧА ÷ КОРМЛЕНИЯ»: 130 ÷ 2 = 65 г,         сколько класть
///    строка среднего, столбики за две недели
/// 3  «ЧАСЫ»: план и факт, ночной перерыв                во сколько
/// 4  «ЗАПАС КОРМА»: что есть и на сколько хватит        когда покупать
/// ```
///
/// **Было девять карточек, стало четыре блока** — и это не укладка,
/// а ответ на то, ради чего сюда заходят. Прежде «сколько класть»
/// складывалось из трёх карточек подряд («сегодня», «сколько», «норма
/// и отклонение»), а само число `130 ÷ 2 = 65` нигде не стояло целиком:
/// человек читал три строки и считал в уме то, что кадр печатает одной
/// строкой.
///
/// **Расхождения с кадром названы, а не обойдены:**
///
/// - **Шапка-фото подэкрана (`backdropSub` = 360) не сделана.** На кадре
///   под шапкой фотография, круглая кнопка «назад» и «…», заголовок
///   «Питание» 36 pt поверх фото, а над ним подпись «НОРМА И ЧАСЫ».
///   У нас стоит `posterHeader` — синяя полоса с заголовком и подписью
///   ПОД ним. Компонента подэкранной шапки с фоном в дизайн-системе
///   нет вовсе (`BackgroundStore` фото уже выбирает, показывать его
///   нечем), а заводить его экраном значит завести сорок первую копию.
///   Это работа дизайн-системы, не этого экрана.
/// - **Плашка «Кормить можно» на кадре синяя** (`action-subtle`).
///   У `TGBanner` четыре тона, синего среди них нет; взят `.done` —
///   ближайший по смыслу («можно»), а не по цвету. Свой прямоугольник
///   с `Token.Action.subtle` здесь не строится: экран, пересобравший
///   компонент, — это ровно тот дефект, из-за которого главная кнопка
///   приложения давала 1,68:1 при зелёном тесте.
/// - **Строки «ЧАСЫ» и «ЗАПАС КОРМА» на кадре со значком в круге 40 pt
///   и шевроном.** Такой строки (значок + заголовок + подпись +
///   значение) в дизайн-системе нет: `TGListRow` без подписи,
///   `TGIconRow` без значения. Строка собрана здесь, и это **вторая
///   копия, ждущая своего автора**, — названа в отчёте.
/// - **Карточка «сегодня» (съел · кормлений · осталось) оставлена**
///   внутри блока нормы, хотя на кадре её нет: это содержание,
///   а не украшение, и выкидывать его ради геометрии нельзя.
struct FeedingScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    /// Системный кегль. Читается, а не задаётся: сюда он приезжает
    /// от настройки **процесса**, и на этом же месте его подменяет
    /// аргумент запуска `-UIPreferredContentSizeCategoryName`.
    @Environment(\.dynamicTypeSize) private var размерТекста
    @Query private var allStocks: [FoodStock]
    @State private var now = Date()

    private var stocks: [FoodStock] {
        guard let dog else { return [] }
        return allStocks.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

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
    ///
    /// Окно **двустороннее**. Раньше здесь была только половина — от
    /// дозы вперёд, — и расписание «кормить в 20:55, таблетка в 21:00»
    /// считалось безупречным, хотя таблетка при этом уходит в полный
    /// желудок. См. `FeedingGate`.
    private var fastingWindows: [(start: Int, end: Int)] {
        guard let dog, dog.isOnTreatment else { return [] }
        let сутки = 24 * 60
        return dog.medications
            .filter { !$0.isPaused && ($0.fastingMinutes > 0 || $0.fastingBefore > 0) }
            .flatMap { medication in
                medication.times.map { time in
                    let начало = (time - medication.fastingBefore + сутки) % сутки
                    return (start: начало,
                            end: (time + medication.fastingMinutes) % сутки)
                }
            }
    }

    /// Почему кормить нельзя прямо сейчас. `nil` — можно.
    private var fastingBlock: FeedingGate.Block? {
        guard let dog, dog.isOnTreatment else { return nil }
        return FeedingGate.block(for: dog.medications, now: now)
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Питание", надпись: "норма и часы", отступы: false)
            if dog == nil {
                EmptyStateCard(
                    subject: .feeding,
                    title: "Собаки пока нет",
                    message: "Добавь собаку — и приложение начнёт считать, сколько она ест и во сколько.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                окноНатощак
                нормаКарточка
                statusCard
                if !report.conflicts.isEmpty { conflictsCard }
                часыКарточка
                запасКарточка
                if report.stoolLagMinutes != nil { outingsCard }
            }
        }
        .navigationTitle("Питание")
        .cinemaScreen()
        .usageScreen(.feeding)
        .task {
            now = Date()
            rebuildReport()
        }
        .onChange(of: dog?.events.count) { _, _ in rebuildReport() }
        .onChange(of: dog?.dailyNormGrams) { _, _ in rebuildReport() }
        .onChange(of: dog?.mealsPerDay) { _, _ in rebuildReport() }
    }

    // MARK: 1 · Можно ли кормить прямо сейчас

    /// Плашка стоит первой и показывается **в обе стороны**: и «нельзя»,
    /// и «можно».
    ///
    /// До редизайна её не было вовсе, пока окно не закрыто, — то есть
    /// человек, зашедший проверить «не рано ли», не получал ответа
    /// и уходил его искать. Отсутствие запрета и разрешение выглядят
    /// одинаково только для того, кто знает, что запрет бывает.
    ///
    /// Показывается только у собаки на лечении: где схем нет, окна
    /// натощак не бывает по устройству, и «кормить можно» было бы
    /// ответом на незаданный вопрос.
    @ViewBuilder
    private var окноНатощак: some View {
        if let dog, dog.isOnTreatment {
            if let блок = fastingBlock {
                fastingCard(блок)
            } else {
                TGBanner(tone: .done, title: "Кормить можно",
                         subtitle: "окно натощак закрыто",
                         systemImage: "fork.knife")
            }
        }
    }

    /// «Сейчас кормить нельзя» — с причиной и со временем, когда можно.
    ///
    /// Причина названа словами, а не значком: запрет без причины человек
    /// выполнит один раз, а на второй обойдёт — особенно когда собака
    /// просит еду и выглядит голодной.
    private func fastingCard(_ block: FeedingGate.Block) -> some View {
        TGBanner(
            tone: .alarm,
            title: "Сейчас кормить нельзя",
            subtitle: .готовая({
                switch block {
                case .before(let лекарство, let доза):
                    return "\(лекарство) дают натощак в \(Fmt.clock(доза)) — "
                         + "к этому времени желудок должен быть пустым. "
                         + "Покормить можно после приёма."
                case .after(let лекарство, let дано, let до):
                    return "\(лекарство) дали в \(Fmt.clock(дано)). "
                         + "Еда сейчас помешает всасыванию — можно с \(Fmt.clock(до))."
                }
            }()),
            systemImage: "fork.knife.circle"
        )
    }

    // MARK: 2 · Сколько

    /// Норма, делённая на кормления, — одной строкой, как на кадре.
    ///
    /// **Здесь было три карточки подряд, и ни одна не печатала частное.**
    /// «Норма в день 130 г», «Кормлений 2», «Значит за раз 65 г» —
    /// три строки, из которых человек собирал арифметику сам. Кадр
    /// печатает её целиком: `130 ÷ 2 = 65 г`.
    @ViewBuilder
    private var нормаКарточка: some View {
        if let dog {
            TGCard {
                if dog.dailyGrams > 0 {
                    TGSectionHeader(title: "норма врача ÷ кормления")

                    // **Обрезанное ЧИСЛО опаснее обрезанного слова.**
                    // Кадр 25.10.2026 (`до-правки/03-питание-ax5.png`,
                    // `AccessibilityXXXL`): «120 ÷ 2 = 60 г» вышло
                    // как **«120… = 60 г»**. Делитель съело многоточие,
                    // и формула стала утверждать, что из ста двадцати
                    // граммов выходит шестьдесят неизвестно как.
                    // Слово человек достроит по огрызку, число —
                    // подставит, а это норма еды, которую назначил врач.
                    //
                    // Виноват не кегль сам по себе, а `lineLimit(1)`
                    // на обеих половинах: ужимать `hero` ниже половины
                    // некуда, и `minimumScaleFactor` упирается,
                    // после чего остаётся только резать.
                    //
                    // На доступных размерах формула разворачивается
                    // столбцом и переносится СВОБОДНО — без
                    // `lineLimit`. Из двух исходов, «целая формула
                    // в две строки» и «половина формулы в одну»,
                    // выбран первый: ужимать текст человеку, который
                    // нарочно попросил крупный, значит отнимать
                    // ровно то, зачем он его включил.
                    Group {
                        if размерТекста.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(verbatim: "\(dog.dailyGrams) ÷ \(dog.mealsPerDay)")
                                    .textStyle(AppFont.hero)
                                    .wraps()
                                Text("= \(dog.servingGrams) г")
                                    .textStyle(AppFont.cardTitle)
                                    .wraps()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                                Text(verbatim: "\(dog.dailyGrams) ÷ \(dog.mealsPerDay)")
                                    .textStyle(AppFont.hero)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                Text("= \(dog.servingGrams) г")
                                    .textStyle(AppFont.cardTitle)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Норма \(dog.dailyGrams) грамм на \(dog.mealsPerDay) кормлений — \(dog.servingGrams) грамм за раз"))
                } else {
                    нормаНеЗаписана
                }

                if report.averageGramsPerDay > 0 {
                    Text("В среднем \(Int(report.averageGramsPerDay)) г в день за две недели.")
                        .textStyle(AppFont.caption)
                        .wraps()
                }

                // Один столбик — это не «две недели».
                //
                // **Правка по кадру приёмки 23.10.2026.** На засеянных
                // данных `report.days` отдал ОДИН день, `BarMark`
                // с `unit: .day` растянул его во всю ширину карточки,
                // и блок, обещающий две недели, показывал одну широкую
                // плашку. Прежняя вёрстка делала ровно то же — просто
                // под заголовком «Две недели», и выглядело это графиком
                // без данных, а не данными без графика.
                if report.days.count > 1 {
                    столбикиДвухНедель
                    TGExplainer(text: "Дни без записей в среднее не попадают: пустой день — это «дневник не вели», а не «не ел».")
                }

                TGDivider()

                // «Что сейчас» — на кадре этого нет, и оно остаётся:
                // девять из десяти заходов сюда именно за этим.
                // **Три числа в строку на доступных размерах не живут.**
                // Это долг, названный 28.09.2026 в самом компоненте
                // (`TGRows.swift`, «ряду из трёх чисел нужна другая
                // раскладка — столбцом»), и кадр 25.10 показал его цену:
                // «из 2 кормлени / й» — перенос посреди слова, а «60 г»
                // и «осталось» разъезжаются по разным уровням.
                //
                // Чинится здесь, у места вызова, а не в `TGStat`:
                // раскладку ряда знает ряд, а не его клетка. Остальные
                // одиннадцать мест с тем же рядом — отдельная работа
                // и отдельный замер; переносить правило без проверки
                // устройства тут нельзя, рядов из двух чисел это
                // не касается.
                стрелкаЧиселСегодня

                if let next = nextMealTime {
                    Text("Следующее кормление примерно в \(Fmt.clock(minuteOfDay: next)).")
                        .textStyle(AppFont.caption)
                        .wraps()
                }

                TGLink(title: dog.dailyGrams > 0 ? "Поменять норму и режим" : "Записать норму и режим",
                       systemImage: "slider.horizontal.3") {
                    ScheduleScreen(dog: dog)
                }
                TGExplainer(text: "Норму называет врач или упаковка — приложение её не выдумывает. Для влажного корма граммы другие: он на три четверти вода.")
            }
        }
    }

    /// Ряд «съел · кормлений · осталось» — столбцом на доступных размерах.
    @ViewBuilder
    private var стрелкаЧиселСегодня: some View {
        if размерТекста.isAccessibilitySize {
            VStack(spacing: Token.Space.s10) { числаСегодня }
        } else {
            HStack(spacing: 0) { числаСегодня }
        }
    }

    /// Дети у обеих раскладок — буквально одни и те же. Разойдись они,
    /// и ветка, которую реже видят, отстанет молча.
    @ViewBuilder
    private var числаСегодня: some View {
        TGStat(value: "\(report.todayGrams) г",
               caption: report.normGramsPerDay > 0 ? "из \(report.normGramsPerDay)" : "съел")
        TGStat(value: "\(report.todayMeals)",
               caption: report.normMealsPerDay > 0
                   ? .готовая(String(localized: "из \(report.normMealsPerDay) кормлений"))
                   : "кормлений")
        // **«Осталось 0 г» читается как «уже наелся».**
        // `remainingGramsToday` это `max(0, норма − съеденное)`,
        // то есть при ненаписанной норме он ноль **по устройству** —
        // и ноль тут отвечал про отсутствие нормы, а читался про
        // собаку. Две соседние подписи этого же ряда ось уже знали
        // (`норма > 0`), третья не знала.
        TGStat(value: report.normGramsPerDay > 0
                   ? "\(report.remainingGramsToday) г"
                   : Self.нечегоСказать,
               caption: "осталось")
    }

    /// Нормы нет — и экран говорит это словами, а не числом.
    ///
    /// **Выбран прочерк с объяснением, а не скрытие блока и не ноль.**
    /// Цена ошибки в каждую сторону считалась так:
    ///
    /// ```
    /// показать 120 (как было)   человек читает умолчание как
    ///                           назначение врача и кормит по нему;
    ///                           от нормы считается порция, и ошибка
    ///                           уезжает в каждое кормление
    /// показать 0                «врач назначил ноль» — такое же
    ///                           утверждение, только абсурдное, и
    ///                           «осталось 0 г» читается как «наелся»
    /// спрятать блок             экран, куда заходят за вопросом
    ///                           «сколько класть», молчит о нём вовсе;
    ///                           отсутствие блока и отсутствие нормы
    ///                           неотличимы, и человек не узнает,
    ///                           что надо что-то ввести
    /// прочерк с дорогой         человек видит, что числа нет, почему
    ///                           его нет и где оно берётся. Цена —
    ///                           лишняя строка на экране
    /// ```
    ///
    /// Четвёртое дешевле трёх: три первых молчат о том, что действие
    /// за человеком, и только оно это говорит. Заголовок при этом
    /// **меняется**: «норма врача» над прочерком была бы той же ложью
    /// в мягкой форме — она утверждает, что врач тут при чём.
    private var нормаНеЗаписана: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: "норму ещё не записали",
                            subtitle: "её называет врач или упаковка")

            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(verbatim: Self.нечегоСказать)
                    .textStyle(AppFont.hero)
                Text("г в день")
                    .textStyle(AppFont.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Норма не записана. Приложение её не подставляет"))

            TGExplainer(text: "Пока нормы нет, приложение не считает ни порцию, ни перерасход — от неё считается всё остальное. Подставить своё число оно не может: получилось бы назначение, которого никто не делал.")
        }
    }

    /// Столбики за две недели — без осей, как на кадре.
    ///
    /// Оси сняты нарочно: на кадре их нет, а `tgChartAxes` рисует сетку
    /// и подписи дат. Это не упрощение графика — у блока другая работа:
    /// он показывает ровность, а не значения. Точные числа человек
    /// читает строкой выше.
    private var столбикиДвухНедель: some View {
        Chart {
            ForEach(report.days) { day in
                BarMark(
                    x: .value("День", day.date, unit: .day),
                    y: .value("Граммы", day.grams)
                )
                // Цвет — это тоже утверждение, и при ненаписанной норме
                // оно выходило само собой: `норма == 0` делала «больше
                // нормы» истинным для **каждого** дня, и две недели
                // окрашивались тревожным. Сравнение есть только тогда,
                // когда есть с чем сравнивать.
                .foregroundStyle(report.normGramsPerDay > 0 && day.grams > report.normGramsPerDay
                                 ? Token.Status.waitingText
                                 : Token.Ink.link)
                .cornerRadius(2)
            }
            if report.normGramsPerDay > 0 {
                RuleMark(y: .value("Норма", report.normGramsPerDay))
                    .foregroundStyle(Token.Ink.silhouette)
                    .lineStyle(StrokeStyle(lineWidth: Token.Size.hairline, dash: [4, 3]))
            }
        }
        .frame(height: Self.высотаСтолбиков)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel(Text("Сколько ел последние две недели"))
        // Озвучка не называет нормы, которой нет: «при норме 0 г»
        // звучит как назначение, а не как её отсутствие.
        .accessibilityValue(report.normGramsPerDay > 0
            ? Text("В среднем \(Int(report.averageGramsPerDay)) г в день при норме \(report.normGramsPerDay) г")
            : Text("В среднем \(Int(report.averageGramsPerDay)) г в день, норма не записана"))
    }

    /// На кадре столбики занимают около восьмой части экрана. Своя
    /// ступень высоты для графика в токенах не заведена.
    private static let высотаСтолбиков: CGFloat = 96

    private var nextMealTime: Int? {
        let minute = FeedingAnalyzer.minuteOfDay(now)
        let schedule = report.suggestedMealTimes.isEmpty ? (dog?.mealTimes ?? []) : report.suggestedMealTimes
        return schedule.sorted().first { $0 > minute } ?? schedule.sorted().first
    }

    // MARK: Норма и отклонение

    /// Отклонение от нормы — словами и только когда есть что сказать.
    ///
    /// `.onNorm` сюда не доезжает нарочно: «менять нечего» уже сказано
    /// строкой среднего в блоке нормы, и плашка повторяла бы её
    /// подтверждающей зеленью на ровном месте.
    @ViewBuilder
    private var statusCard: some View {
        switch report.status {
        case .notEnoughData(let days):
            // **Причина молчания называется та, которая есть.**
            // `FeedingAnalyzer.status` отдаёт `notEnoughData` по ДВУМ
            // разным причинам — мало полных дней ИЛИ нормы нет вовсе
            // (`norm > 0` в его же `guard`), — а карточка объясняла
            // всегда первой. У собаки без нормы человек читал «нужно
            // хотя бы три дня», отмечал три дня и не получал ничего:
            // объяснение было придумано к верному замеру и наследовало
            // его достоверность. Про отсутствие нормы говорит блок
            // выше, и второй причины тут быть не должно.
            if report.normGramsPerDay > 0 {
                TGCard {
                    Text(verbatim: report.status.title).textStyle(AppFont.cardTitle)
                    Text("Полных дней с записями: \(days), нужно хотя бы \(FeedingAnalyzer.minimumCompleteDays) — иначе среднее врёт. Продолжай отмечать еду, дальше приложение посчитает само.")
                        .textStyle(AppFont.caption)
                        .wraps()
                }
            }
        case .onNorm:
            EmptyView()
        case .overNorm:
            TGBanner(tone: .waiting, title: .готовая(report.status.title),
                     subtitle: "В среднем \(Int(report.averageGramsPerDay)) г в день — на \(report.deviationPercent)% больше нормы. Это не срочно, но за две недели складывается в лишний вес.",
                     systemImage: "arrow.up.right")
        case .underNorm:
            TGBanner(tone: .waiting, title: .готовая(report.status.title),
                     subtitle: "В среднем \(Int(report.averageGramsPerDay)) г в день — на \(abs(report.deviationPercent))% меньше нормы. Бодр и вес держится — не беда; вес падает — к врачу.",
                     systemImage: "arrow.down.right")
        }
    }

    private var conflictsCard: some View {
        TGCard {
            TGBanner(tone: .alarm, title: "Расписание спорит с лечением",
                     subtitle: "Приложение показывает конфликт, но само ничего не двигает: это решается с врачом.",
                     systemImage: "exclamationmark.triangle")
            ForEach(report.conflicts, id: \.self) { line in
                Text(verbatim: "• " + line).textStyle(AppFont.caption).wraps()
            }
        }
    }

    // MARK: 3 · Часы

    /// План и факт одной строкой, ночной перерыв — второй.
    @ViewBuilder
    private var часыКарточка: some View {
        if let dog {
            // **Промежутки — у поставленных часов, а не у идеальных.**
            // Строка выше печатает `dog.mealTimes`; строка ночи печатала
            // `plan(mealsPerDay:wake:sleep:)`, то есть другое расписание.
            // На кадре отзыва 27.10 21:55 это выглядело так:
            // «09:30, 15:30 и 21:30 · план» (ночь 12 ч, днём 6 ч)
            // и прямо под ним «Ночь 13 ч · днём между едой 5 ч 30 мин».
            // Разбор — `MealSchedule.plan(times:)`.
            //
            // Идеальная раскладка остаётся там, где её и спрашивают, —
            // в редакторе режима (`ScheduleEditor`): он предлагает часы,
            // а эта карточка о них отчитывается.
            let план = dog.mealTimes.isEmpty
                ? MealSchedule.plan(mealsPerDay: dog.mealsPerDay,
                                    wake: dog.wakeMinuteOfDay,
                                    sleep: dog.sleepMinuteOfDay)
                : MealSchedule.plan(times: dog.mealTimes)
            TGCard(spacing: Token.Space.s8) {
                TGSectionHeader(title: "часы",
                                subtitle: "слева — как поставили, справа — как выходит")

                режимСтрока(symbol: "clock",
                            title: часыСтрокой(dog.mealTimes),
                            subtitle: "план",
                            value: report.observedMealTimes.isEmpty
                                ? Self.нечегоСказать
                                : часыСтрокой(report.observedMealTimes))

                TGDivider()

                // **Значения у этой строки нет, и это правка по кадру
                // приёмки 23.10.2026.** Первая редакция ставила сюда
                // дневной интервал — и на двух кормлениях он совпал
                // с ночным перерывом до цифры: строка читалась
                // «Ночь 12 ч … 12 ч», два числа разных величин под одним
                // видом. Это наш класс «две величины одного имени»,
                // и лечится он не разными цветами, а осью, названной
                // В ТОЙ ЖЕ СТРОКЕ. На кадре 13 у этой строки значения
                // тоже нет.
                режимСтрока(symbol: "moon.zzz",
                            title: String(localized: "Ночь \(Fmt.duration(Double(план.nightGap) * 60))"),
                            subtitle: .готовая(план.hasLongNight
                                ? String(localized: "утром возможна рвота желчью")
                                : дневнойИнтервал(план)),
                            subtitleTone: план.hasLongNight
                                ? Token.Status.stockLowText
                                : Token.Ink.secondary,
                            value: "")

                if report.observedMealTimes.isEmpty {
                    TGExplainer(text: "Записей о еде пока нет. Отметь пару кормлений — и приложение увидит его режим само.")
                } else if !report.suggestedMealTimes.isEmpty,
                          report.suggestedMealTimes.sorted() != dog.mealTimes.sorted() {
                    // Кнопка остаётся: это единственный вход
                    // в `applySchedule()`. Убери её — и предложенное
                    // расписание станет числом, которое некуда применить.
                    TGButton(title: "Поставить это расписание",
                             variant: .secondary, size: .medium) {
                        applySchedule()
                    }
                }

                TGLink(title: "Настроить режим вручную", systemImage: "clock") {
                    ScheduleScreen(dog: dog)
                }
                TGExplainer(text: "Ровный интервал между кормлениями важнее точного часа: собака привыкает к промежутку, а не к цифре на часах. Ночь считается так же, как день.")
            }
        }
    }

    /// «днём между едой 12 ч» — число вместе с осью, в одной строке.
    ///
    /// Ось называется рядом с числом нарочно: у нас записано, чем стоит
    /// её отрыв — две величины одного имени прочлись как одна и дали
    /// «разницу в семь раз», которой нет.
    private func дневнойИнтервал(_ план: MealSchedule.Plan) -> String {
        guard let интервал = план.dayInterval else {
            return String(localized: "ночной перерыв")
        }
        return String(localized: "днём между едой \(Fmt.duration(Double(интервал) * 60))")
    }

    /// «8:30 и 19:30» — часы человеческим перечислением, а не массивом.
    ///
    /// Союз берёт системный список, а не наш литерал: «и», «and», «et»,
    /// «және», «і» — и запятые перед ними в каждом языке свои.
    /// Склеенный руками союз пришлось бы переводить строкой из одной
    /// буквы, а такой ключ не переводится, он угадывается.
    private func часыСтрокой(_ минуты: [Int]) -> String {
        let части = минуты.sorted().map { Fmt.clock(minuteOfDay: $0) }
        guard !части.isEmpty else { return Self.нечегоСказать }
        return части.formatted(.list(type: .and))
    }

    // MARK: 4 · Запас корма

    private var plan: FoodPlan {
        FoodPlanner.plan(stocks, from: now)
    }

    @ViewBuilder
    private var запасКарточка: some View {
        if let dog {
            TGCard {
                TGSectionHeader(
                    title: "запас корма",
                    subtitle: (stocks.isEmpty ? nil : planSubtitle).map { LocalizedStringKey.готовая($0) }
                )

                if stocks.isEmpty {
                    TGExplainer(text: "Впиши, чем кормишь и в какой фасовке — приложение посчитает, на сколько хватит, и напомнит за неделю до конца.")
                } else {
                    ForEach(stocks) { stock in
                        StockRow(stock: stock, now: now)
                        if stock.id != stocks.last?.id { TGDivider() }
                    }
                    if plan.needsRestock {
                        TGBanner(tone: .waiting, title: "Пора покупать",
                                 subtitle: .готовая(restockText(dog)),
                                 systemImage: "cart")
                    }
                }

                TGLink(title: stocks.isEmpty ? "Записать корм" : "Чем кормим",
                       systemImage: "shippingbox") { FoodStockScreen(dog: dog) }
            }
        }
    }

    private var planSubtitle: String? {
        guard let out = plan.firstRunOut, let what = plan.whatRunsOutFirst else { return nil }
        return String(localized: "\(what) закончится \(Fmt.shortDay(out))")
    }

    private func restockText(_ dog: Dog) -> String {
        let нужно = stocks
            .filter { $0.needsRestock(at: now) }
            .map { stock -> String in
                let packs = stock.packsNeeded(forDays: FoodPlanner.planningDays, at: now)
                let unit = stock.kind.unitName(count: Double(packs))
                let name = stock.brand.isEmpty ? stock.kind.title.lowercased() : stock.brand
                return String(localized: "\(name): \(packs) \(unit) на месяц")
            }
        return нужно.joined(separator: " · ")
    }

    // MARK: Выходы

    private var outingsCard: some View {
        TGCard {
            TGSectionHeader(title: "когда выводить")
            if let lag = report.stoolLagMinutes {
                Text("После еды до стула у него в среднем \(Fmt.duration(Double(lag) * 60)).")
                    .textStyle(AppFont.body)
                    .wraps()
            }
            HStack(spacing: Token.Space.s8) {
                ForEach(report.suggestedOutingTimes, id: \.self) { time in
                    Text(verbatim: Fmt.clock(minuteOfDay: time))
                        .textStyle(AppFont.numeric(15))
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
                        .background(Token.Surface.sunken,
                                    in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                }
            }
            TGExplainer(text: "Это ориентиры из его же записей, а не расписание. Просится раньше — выводи раньше: вердикт и эти часы не спорят с человеком.")
        }
    }

    // MARK: Строка блока «ЧАСЫ»

    /// Тире вместо числа. Не «0»: ноль здесь был бы утверждением
    /// о режиме, выведенным из отсутствия записи.
    private static let нечегоСказать = "—"

    /// Строка кадра 13: значок в круге, заголовок, подпись, значение.
    ///
    /// Собрана здесь, а не взята у дизайн-системы, потому что такой
    /// строки там нет: `TGListRow` не несёт подписи, `TGIconRow`
    /// не несёт значения. **Это вторая копия в проекте**, и третьей
    /// быть не должно — общий компонент назван в отчёте.
    private func режимСтрока(symbol: String,
                             title: String,
                             subtitle: LocalizedStringKey,
                             subtitleTone: Color = Token.Ink.secondary,
                             value: String) -> some View {
        HStack(spacing: Token.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: Token.Size.iconMd, weight: Token.FontWeight.medium))
                .foregroundStyle(Token.Ink.primary)
                .frame(width: Token.Size.avatarMd, height: Token.Size.avatarMd)
                .background(Token.Surface.raised, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(verbatim: title).textStyle(AppFont.bodyEmphasis).wraps()
                Text(subtitle).textStyle(AppFont.caption.color(subtitleTone)).wraps()
            }
            Spacer(minLength: Token.Space.s8)
            if !value.isEmpty {
                Text(verbatim: value)
                    .textStyle(AppFont.numeric(15))
                    .multilineTextAlignment(.trailing)
                    .wraps()
            }
        }
        .frame(minHeight: Token.Size.rowMin)
        .accessibilityElement(children: .combine)
    }

    // MARK: Действия

    private func applySchedule() {
        guard let dog else { return }
        dog.mealTimes = report.suggestedMealTimes
        // Через `setMealsPerDay`, а не присваиванием: дневная норма должна
        // остаться прежней, а порция — пересчитаться. Прямое присваивание
        // молча меняло то, сколько собака ест за сутки.
        let былоКормлений = dog.mealsPerDay
        let былиЧасы = dog.mealTimes
        dog.setMealsPerDay(report.suggestedMealTimes.count)
        dog.syncSingleFoodShare()
        guard context.persist(otherwise: {
            dog.mealsPerDay = былоКормлений
            dog.mealTimes = былиЧасы
        }) else {
            Haptics.warning()
            return
        }
        Haptics.success()
    }
}
