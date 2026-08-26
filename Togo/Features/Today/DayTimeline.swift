import SwiftUI

/// Таймлайн всегда показывает, где «сейчас», охряной точкой между прошлым
/// и запланированным. У каждой записи стоит галочка синхронизации, а не просто
/// аватар: видно, что запись дошла до остальных.
struct DayTimeline: View {
    let events: [LogEvent]
    let now: Date
    var showsAuthor: Bool = false
    var onTap: (LogEvent) -> Void

    var body: some View {
        TGCard {
            Text(Fmt.dayTitle(now))
                .textStyle(AppFont.micro)
                .textCase(.lowercase)
                .foregroundStyle(Token.Ink.faint)

            if events.isEmpty {
                EmptyDayState()
            } else {
                // Лента — это лента: непрерывный рельс с точками, а не
                // список строк с разделителями. По рельсу видно, что день
                // идёт, и где в нём «сейчас».
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(
                            event: event,
                            isFirst: index == 0,
                            isLast: false,
                            showsAuthor: showsAuthor
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(event) }
                    }
                    NowMarker(now: now)
                }
            }
        }
    }
}

/// Геометрия рельса. Одна на строку и на маркер «сейчас» — иначе точки
/// разъезжаются на пиксель, и это видно.
enum TimelineRail {
    static let timeWidth: CGFloat = 44
    static let railWidth: CGFloat = 22
    static let dotSize: CGFloat = 9
    static let lineWidth: CGFloat = 2
}

struct TimelineRow: View {
    let event: LogEvent
    var isFirst: Bool = false
    var isLast: Bool = false
    /// В семье из одного человека подпись автора — шум: и так понятно, кто.
    var showsAuthor: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s8) {
            Text(Fmt.clock(event.date))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Ink.secondary)
                .fixedSize()
                .frame(minWidth: TimelineRail.timeWidth, alignment: .leading)
                .padding(.top, 2)

            rail

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                HStack(spacing: Token.Space.s6) {
                    Image(systemName: event.kind.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(event.symbolColor)
                        .accessibilityHidden(true)
                    Text(event.kind.title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(event.titleColor)
                    Spacer(minLength: Token.Space.s8)
                    if showsAuthor {
                        TGAuthorMark(author: event.authorName)
                    }
                }
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption)
                        .foregroundStyle(Token.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Token.Space.s14)
        }
        .accessibilityElement(children: .combine)
    }

    /// Точка на рельсе: сверху отрезок к предыдущей записи, снизу — к следующей.
    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth, height: 6)
            Circle()
                .fill(event.raisesAlarm ? Token.Status.overdueText : Token.Action.done)
                .frame(width: TimelineRail.dotSize, height: TimelineRail.dotSize)
            Rectangle()
                .fill(isLast ? Color.clear : Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
        }
        .frame(width: TimelineRail.railWidth)
        .accessibilityHidden(true)
    }
}

/// «Сейчас» — живая точка на том же рельсе, между прошлым и запланированным.
struct NowMarker: View {
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.s8) {
            Text("сейчас")
                .textStyle(AppFont.micro)
                .foregroundStyle(Token.Action.primary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: TimelineRail.timeWidth, alignment: .leading)

            ZStack {
                Rectangle()
                    .fill(Token.Surface.hairline)
                    .frame(width: TimelineRail.lineWidth, height: 10)
                    .offset(y: -8)
                Circle()
                    .fill(Token.Action.primary)
                    .frame(width: TimelineRail.dotSize + 3, height: TimelineRail.dotSize + 3)
                Circle()
                    .stroke(Token.Action.primary.opacity(0.25), lineWidth: 4)
                    .frame(width: TimelineRail.dotSize + 9, height: TimelineRail.dotSize + 9)
            }
            .frame(width: TimelineRail.railWidth)

            Rectangle()
                .fill(Token.Action.primary.opacity(0.22))
                .frame(height: 1)

            Text(Fmt.clock(now))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Action.primary)
        }
        .padding(.top, Token.Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Сейчас \(Fmt.clock(now))")
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
