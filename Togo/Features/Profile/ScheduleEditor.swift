import SwiftUI

/// Режим дня и питания. Один компонент — и в онбординге, и в профиле:
/// человек настраивает это один раз, а меняет там, где привык.
///
/// Работает с черновиком, а не с моделью: в онбординге собаки ещё нет,
/// а в профиле правку не хочется писать в базу на каждое касание степпера.
struct ScheduleDraft: Equatable {
    var mealsPerDay: Int = 2
    var portionGrams: Int = 60
    var wakeMinuteOfDay: Int = 7 * 60
    var sleepMinuteOfDay: Int = 23 * 60
    var mealTimes: [Int] = []
    /// Времена расставлены вручную — тогда приложение их не пересчитывает.
    var isManual: Bool = false

    var dailyGrams: Int { portionGrams * mealsPerDay }

    var awakeMinutes: Int {
        let span = sleepMinuteOfDay - wakeMinuteOfDay
        return span > 0 ? span : span + 24 * 60
    }

    /// Ровный интервал между кормлениями важнее точного часа: собака
    /// привыкает к промежутку, а не к цифре на часах.
    var evenMealTimes: [Int] {
        guard mealsPerDay > 0 else { return [] }
        let first = wakeMinuteOfDay + 30
        guard mealsPerDay > 1 else { return [first % (24 * 60)] }
        let last = wakeMinuteOfDay + max(90, awakeMinutes - 120)
        let step = (last - first) / (mealsPerDay - 1)
        return (0..<mealsPerDay).map { (first + step * $0) % (24 * 60) }
    }

    var effectiveMealTimes: [Int] {
        isManual && mealTimes.count == mealsPerDay ? mealTimes.sorted() : evenMealTimes
    }

    var intervalBetweenMeals: Int? {
        let times = effectiveMealTimes
        guard times.count > 1 else { return nil }
        return times[1] - times[0]
    }

    static func from(_ dog: Dog) -> ScheduleDraft {
        var draft = ScheduleDraft()
        draft.mealsPerDay = dog.mealsPerDay
        draft.portionGrams = dog.portionGrams
        draft.wakeMinuteOfDay = dog.wakeMinuteOfDay
        draft.sleepMinuteOfDay = dog.sleepMinuteOfDay
        draft.mealTimes = dog.mealTimes
        draft.isManual = dog.mealTimes.sorted() != dog.evenMealTimes()
        return draft
    }

    func apply(to dog: Dog) {
        dog.mealsPerDay = mealsPerDay
        dog.portionGrams = portionGrams
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
            Stepper(value: $draft.portionGrams, in: 5...600, step: 5) {
                HStack {
                    Text("Грамм за раз").textStyle(AppFont.body)
                    Spacer(minLength: Token.Space.s8)
                    Text("\(draft.portionGrams) г").textStyle(AppFont.numeric(17))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)

            TGDivider()
            HStack {
                Text("Выходит в день").textStyle(AppFont.bodyEmphasis)
                Spacer(minLength: Token.Space.s8)
                Text("\(draft.dailyGrams) г").textStyle(AppFont.numeric(20))
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGExplainer(text: "Порция одна на все кормления: уменьшишь её — уменьшится весь день. Норму называет врач, приложение её не выдумывает.")
        }
    }

    // MARK: Во сколько

    private var timesCard: some View {
        TGCard {
            HStack {
                TGSectionHeader(
                    title: "во сколько кормить",
                    subtitle: draft.isManual
                        ? "расставлено вручную"
                        : draft.intervalBetweenMeals.map { "ровно через \(Fmt.duration(Double($0) * 60))" }
                            ?? "одно кормление"
                )
                if draft.isManual {
                    Button("Разложить ровно") {
                        draft.isManual = false
                        draft.mealTimes = draft.evenMealTimes
                        Haptics.tap()
                    }
                    .textStyle(AppFont.captionEmphasis.color(Token.Action.done))
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
            Text("«Настройки → собака → Питание и режим». Приложение потом сравнит это с тем, как вы кормите на самом деле, и скажет, если Стич переедает.")
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
