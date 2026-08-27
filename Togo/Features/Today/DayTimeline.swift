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

            if blocks.isEmpty {
                EmptyDayState()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        // Промежуток стоит перед выходом, а не после
                        // предыдущей записи: он отвечает на вопрос
                        // «сколько он терпел до этого раза».
                        if let indoors = TimelineBuilder.timeIndoors(
                            before: index, in: blocks, threshold: Self.gapThreshold) {
                            TimelineGap(interval: indoors)
                        }

                        // Кнопка, а не жест: строка отвечает на нажатие
                        // и становится кнопкой для голоса. Жест не делает
                        // ни того, ни другого.
                        Button { onTap(block.event) } label: {
                            TimelineRow(
                                block: block,
                                isFirst: index == 0,
                                showsAuthor: showsAuthor
                            )
                        }
                        .buttonStyle(TimelineRowButtonStyle())

                        // Отметки внутри прогулки — своими строками, но
                        // под ней и с её же рельса: это части одного
                        // события, а не соседние события.
                        ForEach(block.marks) { mark in
                            Button { onTap(mark) } label: {
                                TimelineMarkRow(event: mark)
                            }
                            .buttonStyle(TimelineRowButtonStyle())
                        }

                    }
                    if showsNow {
                        NowMarker(now: now, sinceLast: sinceLastEntry)
                    }
                }
            }
        }
    }

    /// Лента блоками: прогулка со своими отметками — один блок.
    private var blocks: [TimelineBlock] { TimelineBuilder.blocks(events) }

    /// Сколько прошло с последней записи. Самая полезная цифра на экране:
    /// именно её человек и ищет глазами.
    private var sinceLastEntry: TimeInterval? {
        TimelineBuilder.timeIndoorsNow(blocks, now: now, threshold: Self.gapThreshold)
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
    let block: TimelineBlock
    var isFirst: Bool = false
    /// В семье из одного человека подпись автора — шум: и так понятно, кто.
    var showsAuthor: Bool = false

    private var event: LogEvent { block.event }

    /// Запись удалили, но след остался: тост уезжает через пять секунд,
    /// и без строки человек оставался без ответа на «я точно это убрала?».
    private var isCancelled: Bool { event.deletedAt != nil }

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s6) {
            time
            marker

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                HStack(spacing: Token.Space.s8) {
                    Text(isCancelled ? event.kind.title + " · отменено" : event.kind.title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(isCancelled ? Token.Ink.faint : event.titleColor)
                        .strikethrough(isCancelled, color: Token.Ink.faint)
                    Spacer(minLength: 0)
                    if showsAuthor {
                        TGAuthorMark(author: event.authorName)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption)
                        .foregroundStyle(Token.Ink.secondary)
                        .wraps()
                }
            }
            .padding(.top, 3)
            .padding(.bottom, block.hasMarks ? Token.Space.s4 : Token.Space.s10)
        }
        .accessibilityElement(children: .combine)
    }

    /// У события с длительностью в колонке времени стоит интервал,
    /// а не только начало: прогулка — это отрезок, и человек ищет глазами
    /// именно «с и до».
    private var time: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Fmt.clock(block.startedAt))
                .textStyle(AppFont.numeric(13, weight: .medium))
                .foregroundStyle(Token.Ink.secondary)
            if block.isSpan {
                Text(Fmt.clock(block.endedAt))
                    .textStyle(AppFont.numeric(13, weight: .medium))
                    .foregroundStyle(Token.Ink.faint)
            }
        }
        .fixedSize()
        .frame(width: TimelineRail.timeWidth, alignment: .leading)
        .padding(.top, 5)
    }

    /// Что писать под названием.
    ///
    /// У события с длительностью — сколько оно шло. Итог прогулки
    /// («пописал · стул») здесь не повторяем: он и так стоит строками
    /// ниже, и раньше одно и то же было написано дважды.
    private var subtitle: String? {
        if isCancelled { return "след остаётся" }
        guard block.isSpan else { return event.subtitle }
        let minutes = Int(block.endedAt.timeIntervalSince(block.startedAt)) / 60
        return Fmt.plural(minutes, "минута", "минуты", "минут")
    }

    private var markerTint: Color {
        if isCancelled { return Token.Ink.faint }
        return event.raisesAlarm ? Token.Status.overdueText : Token.Ink.primary
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
                .foregroundStyle(markerTint)
                .frame(width: TimelineRail.markerSize, height: TimelineRail.markerSize)
                .background(
                    Circle().fill(isCancelled ? Token.Surface.sunken
                                  : (event.raisesAlarm ? Token.Status.overdueBg : Token.Surface.control))
                )

            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
        }
        .frame(width: TimelineRail.railWidth)
        .accessibilityHidden(true)
    }
}

/// Отметка внутри прогулки: то, что собака сделала, пока гуляли.
///
/// Отдельной строкой, но подчинённой — с отступом, мельче и без своего
/// маркера на рельсе. Это часть прогулки, а не соседнее событие.
///
/// Название берётся своё, а не общее имя вида записи: «пописал» вместо
/// «Выход». Раньше отметка внутри прогулки называлась ровно так же, как
/// самостоятельный выход по нужде, — одно слово на два разных события.
struct TimelineMarkRow: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s6) {
            Text(Fmt.clock(event.date))
                .textStyle(AppFont.numeric(12))
                .foregroundStyle(Token.Ink.faint)
                .fixedSize()
                .frame(width: TimelineRail.timeWidth, alignment: .leading)
                .padding(.top, 2)

            // Рельс продолжается, но кружка на нём нет: событие одно.
            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
                .frame(width: TimelineRail.markerSize)

            HStack(spacing: Token.Space.s6) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(event.raisesAlarm ? Token.Status.overdueText : Token.Ink.faint)
                Text(markTitle)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(event.raisesAlarm ? Token.Status.overdueText : Token.Ink.secondary)
                    .wraps()
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
            .padding(.bottom, Token.Space.s6)
        }
        .accessibilityElement(children: .combine)
    }

    private var markTitle: String {
        switch event.kind {
        case .outing: "пописал"
        case .stool: "сходил по-большому"
        case .water: "попил"
        case .treat: "лакомство"
        case .training: "занятие"
        case .reaction: "сорвался"
        case .incident: "инцидент"
        case .note: event.note ?? "заметка"
        default: event.kind.title.lowercased()
        }
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
/// Сколько собака была дома между выходами.
///
/// Раньше здесь стояла голая цифра между любыми соседними строками,
/// и о чём она — приходилось догадываться. Считать промежутки между
/// кормлениями смысла нет: их человек и так примерно знает. А вот
/// «сколько он уже терпит» — то, ради чего в ленту вообще смотрят.
struct TimelineGap: View {
    let interval: TimeInterval
    /// Промежуток открыт: собака дома прямо сейчас.
    var isOpen: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.s6) {
            Text(Fmt.gap(interval))
                .textStyle(AppFont.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: TimelineRail.timeWidth, alignment: .trailing)

            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
                .frame(width: TimelineRail.railWidth)

            Text(isOpen ? "дома с прошлого выхода" : "дома между выходами")
                .textStyle(AppFont.micro.color(Token.Ink.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("дома \(Fmt.duration(interval)) с прошлого выхода")
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
                TimelineGap(interval: sinceLast, isOpen: true)
            }

            HStack(alignment: .center, spacing: Token.Space.s6) {
                Text(Fmt.clock(now))
                    .textStyle(AppFont.numeric(13, weight: .semibold))
                    .foregroundStyle(Token.Status.doneText)
                    .fixedSize()
                    .frame(width: TimelineRail.timeWidth, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(Token.Action.done.opacity(0.18))
                        .frame(width: TimelineRail.nowDotSize + 10,
                               height: TimelineRail.nowDotSize + 10)
                    Circle()
                        .fill(Token.Action.done)
                        .frame(width: TimelineRail.nowDotSize, height: TimelineRail.nowDotSize)
                }
                .frame(width: TimelineRail.railWidth)

                Text("сейчас")
                    .textStyle(AppFont.micro.color(Token.Status.doneText))
                Spacer(minLength: 0)
            }
            .padding(.top, Token.Space.s2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sinceLast.map { "Сейчас \(Fmt.clock(now)), дома \(Fmt.duration($0)) с прошлого выхода" }
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
