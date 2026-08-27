import SwiftUI

// Режим дня: что нужно сделать сегодня и что уже сделано.
//
// Жил в одном файле с лентой, и файл дорос до шестисот сорока строк.
// Лента показывает, что **было**; режим дня — что **надо**. Это два
// разных вопроса, и правка одного заставляла листать другой.

struct DayPlanItem: Identifiable, Equatable {
    enum Kind { case meal, dose, care }

    let id: String
    let time: Date
    let title: String
    var hint: String?
    let kind: Kind
    var isDone: Bool
    /// К какому препарату относится пункт — нужно, чтобы отметить приём,
    /// а не только записать строку в ленту.
    var medication: Medication?
    /// К какому делу ухода. Уход переехал сюда из отдельной карточки:
    /// она говорила, что надо сделать, но сделать оттуда было нельзя —
    /// приходилось идти на вкладку собаки и искать дело руками.
    var careTask: CareTask?
    /// У ухода часа нет: зубы чистят не в 19:40, а «сегодня».
    var showsTime: Bool = true

    static func == (lhs: DayPlanItem, rhs: DayPlanItem) -> Bool {
        lhs.id == rhs.id && lhs.isDone == rhs.isDone && lhs.time == rhs.time
    }
}

/// Свайп вправо означает «сделано» — и в режиме дня, и у ситтера.
struct DayPlanList: View {
    let items: [DayPlanItem]
    let now: Date
    var onComplete: (DayPlanItem) -> Void
    /// Вернуть пункт в невыполненные. Отметили не то — должно быть
    /// куда отступить.
    var onUndo: (DayPlanItem) -> Void = { _ in }
    /// Сколько дел ухода ждут даты. Пока её нет, дело не станет сроком
    /// и не напомнит ни о чём — а выглядит заведённым.
    var awaitingDate: Int = 0
    var onOpenCare: () -> Void = {}

    /// Показывать ли сделанное. По умолчанию свёрнуто.
    @State private var showsDone = false

    private var pending: [DayPlanItem] { items.filter { !$0.isDone } }
    private var done: [DayPlanItem] { items.filter(\.isDone) }

    var body: some View {
        if !items.isEmpty {
            TGCard {
                header
                if pending.isEmpty && !showsDone {
                    // Всё сделано — и это стоит сказать словами, а не
                    // показать пустотой.
                    TGExplainer(text: "На сегодня всё. Ниже — что уже сделали.")
                } else {
                    rows(pending)
                }

                if !done.isEmpty {
                    TGDivider()
                    doneToggle
                    if showsDone { rows(done, isDone: true) }
                }

                if awaitingDate > 0 {
                    TGDivider()
                    awaitingDateRow
                }
            }
        }
    }

    /// Шапка говорит, сколько осталось, а не сколько всего: остаток —
    /// единственное, ради чего в режим дня заглядывают.
    private var header: some View {
        HStack {
            Text(pending.isEmpty
                 ? "режим дня · всё сделано"
                 : "режим дня · осталось \(pending.count) из \(items.count)")
                .textStyle(AppFont.micro)
                .foregroundStyle(Token.Ink.faint)
            Spacer(minLength: 0)
            if !pending.isEmpty {
                Text("свайп вправо = сделано")
                    .textStyle(AppFont.micro)
                    .foregroundStyle(Token.Ink.faint)
            }
        }
    }

    /// Сделанное сворачивается, но не исчезает.
    ///
    /// Выполненные пункты весь день висели наравне с невыполненными,
    /// и остаток приходилось выискивать глазами. Просто убрать их тоже
    /// нельзя: «я точно кормила?» — вопрос, который задают каждый вечер.
    private var doneToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: Token.Duration.quick)) { showsDone.toggle() }
        } label: {
            HStack(spacing: Token.Space.s6) {
                Image(systemName: showsDone ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("сделано · \(done.count)")
                    .textStyle(AppFont.captionEmphasis)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Token.Action.done)
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsDone ? "Скрыть сделанное" : "Показать сделанное, \(done.count)")
    }

    /// Дела, которые заведены, но молчат.
    ///
    /// Напоминание без даты никогда не станет сроком: у «раз в 28 дней»
    /// нет точки отсчёта, у прививки нет дня. Такие дела выглядят
    /// заведёнными и не напоминают ни о чём — а узнать об этом можно
    /// было, только зайдя в уход и увидев их там отдельной группой.
    private var awaitingDateRow: some View {
        Button(action: onOpenCare) {
            HStack(spacing: Token.Space.s8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Token.Status.waitingText)
                    .accessibilityHidden(true)
                Text("\(awaitingDate) \(Fmt.plural(awaitingDate, "напоминание ждёт", "напоминания ждут", "напоминаний ждут")) даты")
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .wraps()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Token.Ink.faint)
            }
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rows(_ list: [DayPlanItem], isDone: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { item in
                if isDone {
                    DonePlanRow(item: item) { onUndo(item) }
                } else {
                    SwipeToCompleteRow(item: item, now: now) { onComplete(item) }
                }
                if item.id != list.last?.id { TGDivider(inset: 52) }
            }
        }
    }
}

/// Сделанный пункт: тихо, но с возможностью передумать.
private struct DonePlanRow: View {
    let item: DayPlanItem
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Token.Space.s10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Token.Action.done)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .strikethrough(color: Token.Ink.faint)
                Text(Fmt.clock(item.time))
                    .textStyle(AppFont.micro)
                    .foregroundStyle(Token.Ink.faint)
            }
            Spacer(minLength: 0)
            Button("Вернуть", action: onUndo)
                .textStyle(AppFont.micro)
                .buttonStyle(.plain)
                .foregroundStyle(Token.Ink.secondary)
                .frame(minHeight: Token.Size.tapTarget)
        }
        .frame(minHeight: Token.Size.tapTarget)
    }
}

struct SwipeToCompleteRow: View {
    let item: DayPlanItem
    let now: Date
    var onComplete: () -> Void

    @State private var offset: CGFloat = 0

    /// Просрочено — только про то, у чего есть час. У ухода его нет:
    /// зубы чистят «сегодня», и красная цифра тут была бы упрёком
    /// на ровном месте.
    private var isOverdue: Bool { item.showsTime && !item.isDone && item.time < now }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text("Готово")
            }
            .textStyle(AppFont.captionEmphasis)
            .foregroundStyle(Token.Action.done)
            .padding(.leading, 12)

            HStack(alignment: .center, spacing: 12) {
                Text(item.showsTime ? Fmt.clock(item.time) : "днём")
                    .textStyle(AppFont.numeric(13, weight: .medium))
                    .foregroundStyle(isOverdue ? Token.Status.overdueText : Token.Ink.secondary)
                    .fixedSize()
                    .frame(minWidth: 40, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(item.isDone ? Token.Ink.faint : Token.Ink.primary)
                        .strikethrough(item.isDone, color: Token.Ink.faint)
                    if let hint = item.hint {
                        Text(hint).textStyle(AppFont.caption).foregroundStyle(Token.Ink.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isDone ? Token.Action.done : Token.Ink.faint)
            }
            .padding(.vertical, 12)
            .background(Token.Surface.card)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !item.isDone else { return }
                        offset = max(0, min(value.translation.width, 120))
                    }
                    .onEnded { _ in
                        if offset > 80 {
                            Haptics.success()
                            onComplete()
                        }
                        withAnimation(.spring(duration: 0.28)) { offset = 0 }
                    }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Отметить сделанным") { onComplete() }
    }
}
