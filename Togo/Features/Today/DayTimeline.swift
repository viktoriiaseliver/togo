import SwiftUI

/// Лента дня.
///
/// Переделана по трём претензиям, которые видно глазами дизайнера:
///
/// 1. **Цвет опять ничего не значил.** Точки на рельсе были все
///    сине-зелёные — то есть цвет был украшением, как та галочка
///    синхронизации. Теперь маркер нейтральный, а терракот получает
///    только то, что его правда заслуживает: кровь и инциденты.
/// 2. **Иконка дублировала подпись.** Рядом со словом «Еда» стояла вилка,
///    и то и другое в одной строке. Иконка переехала на сам рельс
///    и стала маркером — так делают Apple в «Дневнике» и «Кошельке».
/// 3. **Промежутки были не видны.** Всё приложение про интервалы —
///    «не писал 5 ч 20 мин», — а на ленте они не показывались нигде.
///    Теперь промежуток стоит между записями, в колонке времени.
///    Это то, ради чего ленту вообще читают.
struct DayTimeline: View {
    let events: [LogEvent]
    let now: Date
    var showsAuthor: Bool = false
    /// В прошедшем дне «сейчас» не место: он давно прошёл.
    var showsNow: Bool = true
    var onTap: (LogEvent) -> Void

    /// Короче часа промежуток не показываем: это шум, а не сведения.
    private static let gapThreshold: TimeInterval = 60 * 60

    var body: some View {
        TGCard {
            Text(Fmt.dayTitle(now))
                .textStyle(AppFont.micro)
                .textCase(.lowercase)
                .foregroundStyle(Token.Ink.faint)
                .accessibilityAddTraits(.isHeader)

            if events.isEmpty {
                EmptyDayState()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        // Кнопка, а не жест: строка отвечает на нажатие
                        // и становится кнопкой для голоса. Жест не делает
                        // ни того, ни другого.
                        Button { onTap(event) } label: {
                            TimelineRow(
                                event: event,
                                isFirst: index == 0,
                                showsAuthor: showsAuthor
                            )
                        }
                        .buttonStyle(TimelineRowButtonStyle())

                        if let gap = gap(after: index) {
                            TimelineGap(interval: gap)
                        }
                    }
                    if showsNow {
                        NowMarker(now: now, sinceLast: sinceLastEntry)
                    }
                }
            }
        }
    }

    /// Промежуток до следующей записи.
    private func gap(after index: Int) -> TimeInterval? {
        guard index + 1 < events.count else { return nil }
        let interval = events[index + 1].date.timeIntervalSince(events[index].date)
        return interval >= Self.gapThreshold ? interval : nil
    }

    /// Сколько прошло с последней записи. Самая полезная цифра на экране:
    /// именно её человек и ищет глазами.
    private var sinceLastEntry: TimeInterval? {
        guard let last = events.last?.date else { return nil }
        let interval = now.timeIntervalSince(last)
        return interval >= Self.gapThreshold ? interval : nil
    }
}

/// Геометрия рельса. В одном месте, иначе маркеры разъезжаются на пиксель —
/// и это видно.
enum TimelineRail {
    static let timeWidth: CGFloat = 48
    static let railWidth: CGFloat = 30
    static let markerSize: CGFloat = 24
    static let nowDotSize: CGFloat = 12
    static let lineWidth: CGFloat = 1.5
    /// Отрезок над маркером — чтобы линия шла непрерывно.
    static let topStub: CGFloat = 4
}

struct TimelineRow: View {
    let event: LogEvent
    var isFirst: Bool = false
    /// В семье из одного человека подпись автора — шум: и так понятно, кто.
    var showsAuthor: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s6) {
            Text(Fmt.clock(event.date))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Ink.secondary)
                .fixedSize()
                .frame(width: TimelineRail.timeWidth, alignment: .leading)
                .padding(.top, 5)

            marker

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                HStack(spacing: Token.Space.s8) {
                    Text(event.kind.title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(event.titleColor)
                    Spacer(minLength: 0)
                    if showsAuthor {
                        TGAuthorMark(author: event.authorName)
                    }
                }
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption)
                        .foregroundStyle(Token.Ink.secondary)
                        .wraps()
                }
            }
            .padding(.top, 3)
            .padding(.bottom, Token.Space.s10)
        }
        .accessibilityElement(children: .combine)
    }

    /// Маркер — это и есть иконка записи. Кружок нейтральный; терракот
    /// достаётся только тому, что его заслуживает.
    private var marker: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth, height: TimelineRail.topStub)

            Image(systemName: event.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(event.raisesAlarm ? Token.Status.overdueText : Token.Ink.silhouette)
                .frame(width: TimelineRail.markerSize, height: TimelineRail.markerSize)
                .background(
                    Circle().fill(event.raisesAlarm ? Token.Status.overdueBg : Token.Surface.sunken)
                )

            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
        }
        .frame(width: TimelineRail.railWidth)
        .accessibilityHidden(true)
    }
}

/// Нажатие видно: строка на мгновение подсвечивается. Без этого тап
/// по ленте ощущается как промах.
struct TimelineRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                    .fill(Token.Surface.sunken)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .padding(.horizontal, -Token.Space.s6)
            )
            .animation(.easeOut(duration: Token.Duration.instant), value: configuration.isPressed)
    }
}

/// Промежуток между записями.
///
/// Единственное, что отличает эту ленту от списка строк: всё приложение
/// про интервалы, и здесь они наконец видны.
struct TimelineGap: View {
    let interval: TimeInterval

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.s6) {
            Text(Fmt.gap(interval))
                .textStyle(AppFont.micro.color(Token.Ink.faint))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: TimelineRail.timeWidth, alignment: .trailing)

            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
                .frame(width: TimelineRail.railWidth)

            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("прошло \(Fmt.duration(interval))")
    }
}

/// «Сейчас» — живая точка на том же рельсе.
///
/// Единственная охряная вещь в ленте: охра означает действие и текущий
/// момент, и больше ничего.
struct NowMarker: View {
    let now: Date
    var sinceLast: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            if let sinceLast {
                TimelineGap(interval: sinceLast)
            }

            HStack(alignment: .center, spacing: Token.Space.s6) {
                Text(Fmt.clock(now))
                    .textStyle(AppFont.numeric(13, weight: .semibold))
                    .foregroundStyle(Token.Action.primary)
                    .fixedSize()
                    .frame(width: TimelineRail.timeWidth, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(Token.Action.primary.opacity(0.18))
                        .frame(width: TimelineRail.nowDotSize + 10,
                               height: TimelineRail.nowDotSize + 10)
                    Circle()
                        .fill(Token.Action.primary)
                        .frame(width: TimelineRail.nowDotSize, height: TimelineRail.nowDotSize)
                }
                .frame(width: TimelineRail.railWidth)

                Text("сейчас")
                    .textStyle(AppFont.micro.color(Token.Action.primary))
                Spacer(minLength: 0)
            }
            .padding(.top, Token.Space.s2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sinceLast.map { "Сейчас \(Fmt.clock(now)), с последней записи \(Fmt.duration($0))" }
                            ?? "Сейчас \(Fmt.clock(now))")
    }
}

/// Пустой экран первого дня рассказывает, что будет через три дня —
/// вместо «нет данных».
struct EmptyDayState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Token.Ink.silhouette)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text("Пока пусто").textStyle(AppFont.cardTitle).foregroundStyle(Token.Ink.primary)
            Text("Нажми «Просится», когда он подойдёт к двери. Через день здесь появится его режим, и приложение начнёт понимать, когда он действительно хочет на улицу.")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.secondary)
            Text("Ничего заполнять заранее не надо.")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.faint)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Режим дня

struct DayPlanItem: Identifiable, Equatable {
    enum Kind { case meal, dose }

    let id: String
    let time: Date
    let title: String
    var hint: String?
    let kind: Kind
    var isDone: Bool
    /// К какому препарату относится пункт — нужно, чтобы отметить приём,
    /// а не только записать строку в ленту.
    var medication: Medication?

    static func == (lhs: DayPlanItem, rhs: DayPlanItem) -> Bool {
        lhs.id == rhs.id && lhs.isDone == rhs.isDone && lhs.time == rhs.time
    }
}

/// Свайп вправо означает «сделано» — и в режиме дня, и у ситтера.
struct DayPlanList: View {
    let items: [DayPlanItem]
    let now: Date
    var onComplete: (DayPlanItem) -> Void

    var body: some View {
        if !items.isEmpty {
            TGCard {
                Text("режим дня · свайп вправо = сделано")
                    .textStyle(AppFont.micro)
                    .foregroundStyle(Token.Ink.faint)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        SwipeToCompleteRow(item: item, now: now) { onComplete(item) }
                        if item.id != items.last?.id { TGDivider(inset: 52) }
                    }
                }
            }
        }
    }
}

struct SwipeToCompleteRow: View {
    let item: DayPlanItem
    let now: Date
    var onComplete: () -> Void

    @State private var offset: CGFloat = 0

    private var isOverdue: Bool { !item.isDone && item.time < now }

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
                Text(Fmt.clock(item.time))
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
