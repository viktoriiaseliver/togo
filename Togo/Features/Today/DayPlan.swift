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
    /// Доза ждёт таймера от еды — отметить её раньше нельзя.
    var gate: DoseGate.State = .open

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
    /// Открыть запись пункта: тап по тексту, а не по кругу.
    var onOpen: (DayPlanItem) -> Void = { _ in }
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
                 ? "план дня · всё сделано"
                 : "план дня · осталось \(pending.count) из \(items.count)")
                .textStyle(AppFont.micro)
                .foregroundStyle(Token.Ink.faint)
            Spacer(minLength: 0)
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
                // `Fmt.plural` возвращает число ВМЕСТЕ со словом. Число
                // перед ним печаталось второй раз: «5 5 напоминаний».
                Text("\(Fmt.plural(awaitingDate, "напоминание ждёт", "напоминания ждут", "напоминаний ждут")) даты")
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

    /// Что стоит под названием: время и, у сделанного, кто и когда.
    private func subtitle(for item: DayPlanItem, isDone: Bool) -> String? {
        // Замок говорит сам за себя: время дозы, которая ещё не открылась,
        // человеку ничего не даёт.
        if let waiting = DoseGate.caption(item.gate, now: now) { return waiting }
        var parts: [String] = []
        if item.showsTime { parts.append(Fmt.clock(item.time)) } else { parts.append("днём") }
        if let hint = item.hint { parts.append(hint) }
        return parts.joined(separator: " · ")
    }

    /// Чем красить подпись: ожидание — мятой, просрочка — жёлтым.
    private func tint(for item: DayPlanItem) -> Color? {
        if !item.gate.isOpen { return Token.Status.doneText }
        return isOverdue(item) ? Token.Status.waitingText : nil
    }

    /// Просрочка желтеет — но только у того, у чего есть час.
    private func isOverdue(_ item: DayPlanItem) -> Bool {
        item.showsTime && !item.isDone && item.time < now
    }

    private func rows(_ list: [DayPlanItem], isDone: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { item in
                TGCheckRow(title: item.title,
                           subtitle: subtitle(for: item, isDone: isDone),
                           isDone: isDone,
                           isLocked: !item.gate.isOpen,
                           subtitleTint: tint(for: item),
                           onCheck: {
                               // Закрытую дозу нажатие не отмечает —
                               // оно объясняет, чего ждём.
                               if !item.gate.isOpen { onOpen(item) }
                               else if isDone { onUndo(item) } else { onComplete(item) }
                           },
                           onOpen: { onOpen(item) })
                if item.id != list.last?.id { TGDivider(inset: 52) }
            }
        }
    }
}
