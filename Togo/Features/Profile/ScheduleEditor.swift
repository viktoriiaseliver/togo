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
            case .perServing: String(localized: "Считаю за раз")
            case .perDay: String(localized: "Знаю дневную норму")
            }
        }

        /// С какого конца ОТКРЫВАТЬ записанную норму, чтобы ни одно
        /// из двух чисел на экране не врало.
        ///
        /// **Умолчанием стоял `.perServing` всегда, и это молча меняло
        /// норму врача** (замер 28.10.2026). Шаговик «Грамм за раз»
        /// показывает `servingGrams` — норму, делённую на кормления
        /// И ОКРУГЛЁННУЮ до пяти граммов, — а пишет обратно
        /// `показанное × кормления`. Пара «показать» и «записать»
        /// не обратна себе, и у большинства норм два соседних числа
        /// на экране просто не сходятся:
        ///
        /// ```
        /// норма 220 г, 3 кормления   «Грамм за раз 75» · «Выходит в день 220»
        ///                            75 × 3 = 225 — ни одно из трёх
        ///                            не равно другому
        /// одно касание вверх и вниз  75 → 80 → 75, а норма 220 → 225
        ///                            ← НОРМА ВРАЧА ИЗМЕНИЛАСЬ, и человек
        ///                              этого не просил
        /// сколько норм из 5…600 г    3 кормления: 556 из 596 (93 %)
        /// расходятся с показанной    2 кормления: 536 (89 %)
        /// порцией
        /// ```
        ///
        /// Красная линия проекта: «Не подставлять там, где подстановка
        /// станет утверждением человека… норма с бланка». Поэтому
        /// `.perServing` открывается только тогда, когда норма ровно
        /// раскладывается на порции по пять граммов; иначе —
        /// `.perDay`, где правится само записанное число, а порция
        /// стоит отдельной строкой «Значит за раз» и честно названа
        /// производной.
        ///
        /// Порцию считает `Dog.servingGrams(dailyGrams:mealsPerDay:)`,
        /// а не своя строка: здесь жила **третья** копия той же формулы
        /// округления (замер 28.10.2026), и именно она решает, какой
        /// шаговик встанет над нормой врача.
        static func для(норма: Int, кормлений: Int) -> NormEntry {
            guard норма > 0, кормлений > 0 else { return .perServing }
            let порция = Dog.servingGrams(dailyGrams: норма, mealsPerDay: кормлений)
            return порция * кормлений == норма ? .perServing : .perDay
        }
    }

    /// Только способ ввода: какой шаговик человек видит. На хранение
    /// не влияет — число всё равно одно.
    ///
    /// Умолчание здесь — для пустого черновика (онбординг, собаки ещё
    /// нет). У существующей собаки его задаёт `NormEntry.для(норма:)`
    /// в `from(_:)`, и это не вкус, а защита записанного числа.
    var normEntry: NormEntry = .perServing
    var mealsPerDay: Int = 2
    /// Сколько собака съедает за сутки. Одно число, как и в модели.
    ///
    /// **Ноль — это «норму никто не называл», и умолчанием стоит именно
    /// он** (правка 25.10.2026, прежде здесь было 120).
    ///
    /// Сто двадцать граммов были умолчанием черновика, а не чьим-то
    /// словом, и уезжали в базу насквозь: `OnboardingFlow.saveDog()`
    /// зовёт `apply(to:)`, тот — `dog.setDailyGrams(120)`. Шаг «Режим
    /// дня» граммов **не спрашивает вовсе** (`ModeStep`), то есть число
    /// человек не видел ни разу, — а экран питания ставил его под
    /// заголовок «НОРМА ВРАЧА» и абзацем ниже обещал, что приложение
    /// норму не выдумывает.
    ///
    /// Красная линия проекта: «Не подставлять там, где подстановка
    /// станет утверждением человека. Время забора, вес у рецепта,
    /// норма с бланка, предел прибора — пустые намеренно».
    ///
    /// Подсказка при этом **не запрещена** — запрещена подстановка без
    /// подтверждения. Поэтому стартовое число живёт ниже, в
    /// `сКакогоЧислаНачинать`, и попадает в черновик только по нажатию
    /// человека.
    var dailyGrams: Int = 0
    var wakeMinuteOfDay: Int = 7 * 60
    var sleepMinuteOfDay: Int = 23 * 60
    var mealTimes: [Int] = []
    /// Времена расставлены вручную — тогда приложение их не пересчитывает.
    var isManual: Bool = false

    /// С какого числа начинает шаговик, когда человек нажал «записать
    /// норму». Это **подсказка, которую он подтверждает касанием**,
    /// а не подстановка: до нажатия в черновике ноль, и в базу уезжает
    /// ноль.
    static let сКакогоЧислаНачинать = 120

    /// Норму назвали. Ноль значит «не назвали» — ровно как в модели
    /// и как в `FeedingAnalyzer.status`.
    var нормаНазвана: Bool { dailyGrams > 0 }

    /// Порция за раз: норма, поделённая на число кормлений.
    ///
    /// Нормы нет — порции нет. Пол `max(5, …)` отвечал «5 г» там, где
    /// ответа нет вовсе, и пятёрка выглядела данными человека.
    ///
    /// Считает модель, а не черновик: иначе шаговик в редакторе
    /// и число в профиле округляли бы каждый по-своему. Разбор —
    /// у `Dog.servingGrams(dailyGrams:mealsPerDay:)`.
    var servingGrams: Int {
        Dog.servingGrams(dailyGrams: dailyGrams, mealsPerDay: mealsPerDay)
    }

    var awakeMinutes: Int {
        MealSchedule.awakeMinutes(wake: wakeMinuteOfDay, sleep: sleepMinuteOfDay)
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

    /// Часы РАЗОШЛИСЬ с ровной раскладкой — вот что значит «вручную»
    /// для того, кто смотрит на экран.
    ///
    /// `isManual` отвечает на другой вопрос: «трогал ли человек пикер».
    /// Два разных вопроса, и до 28.10.2026 на второй отвечали первым.
    /// Замер по кадру отзыва 27.10 21:54: человек выставил рукой ровно
    /// то же, что предлагали, — и получил подпись «расставлено вручную»
    /// и кнопку «Разложить ровно», которая не меняет НИЧЕГО. Её слово:
    /// «когда настроила и так ровно — предлагает настроить ровно».
    var часыРазошлисьСРовными: Bool {
        effectiveMealTimes != evenMealTimes
    }

    /// Что получилось на самом деле — с учётом ручных правок.
    ///
    /// **`isCompressed` берётся у ТЕХ часов, что на экране, а не
    /// у идеальной раскладки** (правка 28.10.2026 по тому же кадру).
    /// Прежде флаг приезжал из `plan`, то есть из раскладки, которой
    /// на экране нет, и пояснение «кормления разложены поровну между
    /// первым и последним, а ночь выходит длиннее» печаталось над
    /// часами, расставленными рукой:
    ///
    /// ```
    /// её часы 09:30 · 15:30 · 21:30   днём 6 ч, ночью 12 ч, сжатия НЕТ
    /// plan.isCompressed (идеальная)   true  ← печаталось
    /// plan(times:).isCompressed       false ← правда
    /// ```
    ///
    /// И совет в конце того же абзаца («вставать раньше или ложиться
    /// позже») звал выравнивать то, что уже выровнено рукой.
    var effectivePlan: MealSchedule.Plan {
        часыРазошлисьСРовными ? MealSchedule.plan(times: effectiveMealTimes) : plan
    }

    static func from(_ dog: Dog) -> ScheduleDraft {
        var draft = ScheduleDraft()
        draft.mealsPerDay = dog.mealsPerDay
        draft.dailyGrams = dog.dailyGrams
        draft.wakeMinuteOfDay = dog.wakeMinuteOfDay
        draft.sleepMinuteOfDay = dog.sleepMinuteOfDay
        draft.mealTimes = dog.mealTimes
        draft.isManual = dog.mealTimes.sorted() != dog.evenMealTimes()
        // Конец, с которого открыть норму, — не умолчание, а замер
        // записанного числа. Разбор у `NormEntry.для(норма:кормлений:)`.
        draft.normEntry = .для(норма: dog.dailyGrams, кормлений: dog.mealsPerDay)
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

/// Что правка режима питания трогает — и чем это вернуть при отказе
/// записи.
///
/// **Обратная сторона `apply(to:)`, и лежит рядом с ним нарочно.**
/// `ModelContext.persist(otherwise:)` требует вернуть **ровно те поля,
/// что трогали** (`rollback()` у SwiftData значений не возвращает —
/// разбор там же), то есть список полей написан в проекте дважды:
/// один раз правкой, второй — возвратом. Копий возврата было две,
/// и они разошлись (замер 28.10.2026):
///
/// ```
/// ScheduleScreen.сохранить       семь полей, включая расход корма
///                                у `stocks[0]` — и прямо названо,
///                                что седьмое лежит в ДРУГОМ объекте
/// FeedingScreen.applySchedule    два: mealsPerDay и mealTimes
/// ```
///
/// А трогает `applySchedule` пять: `setMealsPerDay` внутри зовёт
/// `setDailyGrams`, и тот пишет `dailyNormGrams` и `portionGrams`;
/// `syncSingleFoodShare()` пишет `gramsPerDay` единственного запаса.
/// То есть при отказе записи норма врача и обратный отсчёт корма
/// оставались от **непринятой** правки, а экран при этом честно
/// говорил «не сохранилось».
///
/// Поля, которых правка не касалась, возвращаются теми же значениями
/// — это пустая запись, а не лишнее действие; взамен список
/// перестаёт зависеть от того, какую из двух дорог читает автор.
struct ПитаниеСнимок {
    private let dailyNormGrams: Int?
    private let portionGrams: Int
    private let mealsPerDay: Int
    private let wakeMinuteOfDay: Int
    private let sleepMinuteOfDay: Int
    private let mealTimes: [Int]
    /// Расход единственного корма. `nil` — запасов не один, и
    /// `syncSingleFoodShare()` до него не доходит.
    private let gramsPerDay: Int?

    init(_ dog: Dog) {
        dailyNormGrams = dog.dailyNormGrams
        portionGrams = dog.portionGrams
        mealsPerDay = dog.mealsPerDay
        wakeMinuteOfDay = dog.wakeMinuteOfDay
        sleepMinuteOfDay = dog.sleepMinuteOfDay
        mealTimes = dog.mealTimes
        gramsPerDay = dog.stocks.count == 1 ? dog.stocks[0].gramsPerDay : nil
    }

    func вернуть(в dog: Dog) {
        dog.dailyNormGrams = dailyNormGrams
        dog.portionGrams = portionGrams
        dog.mealsPerDay = mealsPerDay
        dog.wakeMinuteOfDay = wakeMinuteOfDay
        dog.sleepMinuteOfDay = sleepMinuteOfDay
        dog.mealTimes = mealTimes
        if let gramsPerDay, dog.stocks.count == 1 {
            dog.stocks[0].gramsPerDay = gramsPerDay
        }
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
            // Сброс ручной раскладки — в сеттере, то есть ТОЛЬКО от нажатия.
            // Здесь стоял `onChange(of: mealsPerDay)`, а он срабатывал
            // и при загрузке: черновик открывается с числом по умолчанию,
            // `ScheduleScreen.task` подставляет сохранённое — число
            // «меняется», ручные часы снимались, и «Сохранить» затирал их
            // ровной раскладкой. Отзыв 27.10: «Сбрасывается когда захожу
            // настроить», кадр: сохранено 15:30 и 21:30, открыто 15:00 и 20:30.
            Stepper(value: Binding(get: { draft.mealsPerDay },
                                   set: { draft.mealsPerDay = $0; draft.isManual = false }),
                    in: 1...5) {
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
                // И конец, с которого показывают норму, пересчитывается
                // вместе с делителем: норма 240 на трёх кормлениях
                // раскладывается ровно (80 × 3), на пяти — уже нет
                // (50 × 5 = 250). Оставь `.perServing` — и запись врача
                // поедет на десять граммов от одного касания.
                draft.normEntry = .для(норма: draft.dailyGrams,
                                       кормлений: draft.mealsPerDay)
            }

            // Выбор конца, с которого считают, появляется вместе
            // с числом: пока нормы нет, он переключает то, чего нет,
            // то есть выглядит действием и не делает ничего.
            if draft.нормаНазвана {
                TGDivider()
                TGChipGroup(items: ScheduleDraft.NormEntry.allCases, title: \.title,
                            isSelected: { $0 == draft.normEntry },
                            minimumWidth: 150) { выбор in
                    draft.normEntry = выбор
                    // «Считаю за раз» — это утверждение человека о том,
                    // КАКОЕ число у него настоящее. Принимаем его целиком:
                    // норма становится произведением показанной порции.
                    // Иначе экран показывал бы порцию из одного числа,
                    // а дневную строку — из другого, и они не сходились бы
                    // между собой (замер: 93 % норм при трёх кормлениях).
                    if выбор == .perServing {
                        draft.dailyGrams = draft.servingGrams * max(1, draft.mealsPerDay)
                    }
                }
                .padding(.vertical, Token.Space.s8)
            }

            // Оба шаговика правят одно и то же число — просто с разных
            // концов. Раньше это были два разных поля, и они расходились.
            TGDivider()
            if !draft.нормаНазвана {
                // **Пока нормы нет, шаговиков нет вовсе, и это не
                // украшение пустоты.** При нуле они показывали «5 г
                // за раз» и «выходит в день 0 г» — два числа, которые
                // не сходятся между собой, и оба выдуманные. Прочерк
                // говорит ровно то, что есть: числа нет.
                нетНормыСтрока
                TGButton(title: "Записать норму", variant: .secondary, size: .medium) {
                    draft.dailyGrams = ScheduleDraft.сКакогоЧислаНачинать
                    Haptics.tap()
                }
                TGExplainer(text: "Пока норма не записана, приложение не считает ни порцию, ни перерасход: от неё считается всё остальное. Нажми — и шаговик встанет на сто двадцать граммов, откуда удобно докрутить до того, что назвал врач. Это подсказка, а не назначение.")
            } else if draft.normEntry == .perServing {
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
            // **Короче на пятую часть, и ни один факт не убран**
            // (отзыв 27.10.2026: «в общем текста сократи»). Убрана
            // ОДНА фраза — «приложение её не выдумывает», — и она была
            // отрицательным пересказом соседней: «норму называет врач
            // или упаковка» говорит то же самое утвердительно.
            // Три факта на месте: частное, кто называет норму, вода
            // во влажном корме.
            TGExplainer(text: "Порция = норма ÷ кормления: добавишь кормление — упадёт порция, а не дневная еда. Норму называет врач или упаковка. Влажный корм на три четверти вода — граммы там другие.")
        }
    }

    /// Прочерк вместо числа. Не «0 г»: ноль здесь был бы назначением,
    /// выведенным из того, что никто ничего не назначал.
    private static let нормаНеНазвана = "—"

    /// Строка «Норма в день — ·» и подпись, кто её называет.
    private var нетНормыСтрока: some View {
        HStack {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("Норма в день").textStyle(AppFont.body)
                Text("её называет врач или упаковка").textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            Text(verbatim: Self.нормаНеНазвана)
                .textStyle(AppFont.numeric(20).color(Token.Ink.secondary))
        }
        .frame(minHeight: Token.Size.tapTarget)
        .accessibilityElement(children: .combine)
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
            // Подпись и кнопка стоят на ЗАМЕРЕ часов, а не на флаге
            // «трогал пикер»: предлагать «разложить ровно» уже ровным
            // часам — это предлагать действие, которое ничего не делает.
            HStack {
                TGSectionHeader(
                    title: "во сколько кормить",
                    subtitle: draft.часыРазошлисьСРовными
                        ? "расставлено вручную"
                        : .готовая(scheduleSubtitle)
                )
                if draft.часыРазошлисьСРовными {
                    Button {
                        draft.isManual = false
                        draft.mealTimes = draft.evenMealTimes
                        Haptics.tap()
                    } label: {
                        // Подпись мелкая, а цель касания — нет: без рамки
                        // нажималась только высота строки caption, ~18 pt
                        // при пороге 44. Рамка внутри метки, а не снаружи
                        // кнопки: снаружи она растит место, но не касание.
                        Text("Разложить ровно")
                            .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
                            .frame(minHeight: Token.Size.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        guard let interval = draft.effectivePlan.dayInterval else { return String(localized: "одно кормление") }
        return "ровно через \(Fmt.duration(Double(interval) * 60))"
    }

    /// Ночь — тоже промежуток между кормлениями, и обычно самый длинный.
    /// Показываем его рядом с дневным: иначе человек его просто не видит.
    @ViewBuilder
    private var rhythmRow: some View {
        let plan = draft.effectivePlan
        if plan.times.count > 1 {
            // Два числа, не три — см. оговорку у `SkillAttemptSheet`.
            // Подписи здесь самые длинные из двойных рядов («днём между
            // едой»), так что если двойные ряды и мерить, то с этого.
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
                // Причина — вперёд, следствие — за ней: человек читает
                // этот абзац, чтобы понять, ПОЧЕМУ ночь длиннее.
                // Четыре факта те же, слов меньше.
                TGExplainer(text: "Ровный шаг в сутки не влезает: кормления разложены поровну между первым и последним, а ночь длиннее. Выровнять — вставать раньше или ложиться позже.")
            }
        }
    }

    private func mealName(_ index: Int) -> String {
        let count = draft.effectiveMealTimes.count
        if count == 1 { return String(localized: "Кормление") }
        if index == 0 { return String(localized: "Первое") }
        if index == count - 1 { return String(localized: "Последнее") }
        return String(localized: "\(index + 1)-е")
    }

    private func setMealTime(_ minute: Int, at index: Int) {
        var times = draft.effectiveMealTimes
        guard times.indices.contains(index) else { return }
        times[index] = minute
        draft.mealTimes = times
        // «Вручную» — только если вышло НЕ ровно. Поставил человек часы,
        // совпавшие с ровной раскладкой, — кнопка «Разложить ровно»
        // предлагала сделать уже сделанное (отзыв 27.10: «и так ровно
        // предлагает настроить ровно»).
        draft.isManual = times.sorted() != draft.evenMealTimes
    }

    private var explainerCard: some View {
        TGCard {
            Text("Это можно поменять когда угодно").textStyle(AppFont.cardTitle)
            Text("«Настройки → собака → Питание и режим». Приложение сравнит это с тем, как ты кормишь на самом деле, и скажет, если собака переедает.")
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
