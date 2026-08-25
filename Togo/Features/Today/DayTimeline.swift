import SwiftUI

/// Таймлайн всегда показывает, где «сейчас», охряной точкой между прошлым
/// и запланированным. У каждой записи стоит галочка синхронизации, а не просто
/// аватар: видно, что запись дошла до остальных.
struct DayTimeline: View {
    let events: [LogEvent]
    let now: Date
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
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        TimelineRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(event) }
                        if event.id != events.last?.id { TGDivider().padding(.leading, 52) }
                    }
                    NowMarker(now: now)
                }
            }
        }
    }
}

struct TimelineRow: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Fmt.clock(event.date))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Ink.secondary)
                .frame(width: 40, alignment: .leading)

            Image(systemName: event.kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(event.raisesAlarm ? Token.Status.overdueText : Token.Ink.silhouette)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.title)
                    .textStyle(AppFont.bodyEmphasis)
                    .foregroundStyle(event.raisesAlarm ? Token.Status.overdueText : Token.Ink.primary)
                if let subtitle = event.subtitle {
                    Text(subtitle).textStyle(AppFont.caption).foregroundStyle(Token.Ink.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(String(event.authorName.prefix(1)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Token.Ink.secondary)
                Image(systemName: event.isSynced ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.isSynced ? Token.Action.done : Token.Ink.faint)
                    .accessibilityLabel(event.isSynced ? "Синхронизировано" : "Ждёт синхронизации")
            }
        }
        .padding(.vertical, 10)
    }
}

struct NowMarker: View {
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Text("сейчас").textStyle(AppFont.micro).foregroundStyle(Token.Action.primary)
                .frame(width: 40, alignment: .leading)
            Circle().fill(Token.Action.primary).frame(width: 8, height: 8)
            Rectangle().fill(Token.Action.primary.opacity(0.28)).frame(height: 1)
            Text(Fmt.clock(now))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Action.primary)
        }
        .padding(.top, 10)
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
                        if item.id != items.last?.id { TGDivider().padding(.leading, 52) }
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
                    .frame(width: 40, alignment: .leading)

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
