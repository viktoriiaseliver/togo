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
                .foregroundStyle(Token.Ink.secondary)
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
                        ForEach(block.markGroups) { group in
                            Button {
                                // Одна отметка открывается сама. У группы
                                // «какая из трёх» — вопрос без смысла,
                                // ровно по той же причине, по которой у неё
                                // нет и времени: открываем прогулку.
                                onTap(group.count == 1 ? group.representative : block.event)
                            } label: {
                                TimelineMarkRow(group: group)
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

/// По чему выравнивается строка ленты.
///
/// Раньше время, кружок и заголовок разъезжались по вертикали: у каждого
/// стоял свой отступ сверху, подобранный на глаз под один размер шрифта.
/// Стоило системному шрифту стать крупнее — и кружок уезжал ниже
/// собственной подписи.
///
/// Теперь все трое объявляют одну и ту же точку — свой вертикальный
/// центр, — и стек считает отступы сам, при любом размере текста.
extension VerticalAlignment {
    private enum TimelineMarkerID: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.top]
        }
    }

    static let timelineMarker = VerticalAlignment(TimelineMarkerID.self)
}

struct TimelineRow: View {
    let block: TimelineBlock
    var isFirst: Bool = false
    /// В семье из одного человека подпись автора — шум: и так понятно, кто.
    var showsAuthor: Bool = false

    private var event: LogEvent { block.event }

    /// Запись удаляется — и пока висит тост, строка стоит зачёркнутой:
    /// это вторая половина кнопки «Отменить». Уехал тост — ушла и строка.
    private var isCancelled: Bool { event.deletedAt != nil }

    var body: some View {
        HStack(alignment: .timelineMarker, spacing: Token.Space.s6) {
            time
            marker

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                HStack(spacing: Token.Space.s8) {
                    Text(isCancelled ? event.kind.title + " · отменено" : event.kind.title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(isCancelled ? Token.Ink.secondary : event.titleColor)
                        .strikethrough(isCancelled, color: Token.Ink.secondary)
                        .alignmentGuide(.timelineMarker) { $0[VerticalAlignment.center] }
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
                .alignmentGuide(.timelineMarker) { $0[VerticalAlignment.center] }
            if block.isSpan {
                Text(Fmt.clock(block.endedAt))
                    .textStyle(AppFont.numeric(13, weight: .medium))
                    .foregroundStyle(Token.Ink.secondary)
            }
        }
        .fixedSize()
        .frame(width: TimelineRail.timeWidth, alignment: .leading)
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
        return String(localized: "\(minutes) минут")
    }

    private var markerTint: Color {
        if isCancelled { return Token.Ink.secondary }
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
                .alignmentGuide(.timelineMarker) { $0[VerticalAlignment.center] }

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
    let group: MarkGroup

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s6) {
            // Времени здесь нет намеренно.
            //
            // Внутри прогулки его уже задаёт сама прогулка: «18:12 — 18:45».
            // Мелкая метка у отметки не добавляла ничего — в живом дневнике
            // три «пописал» стояли в 06:34, 06:38 и 06:39, и человек
            // не узнавал из этих цифр ничего, чего не знал бы из «×3».
            // Точное время осталось в самой записи: тап её открывает.
            Color.clear
                .frame(width: TimelineRail.timeWidth, height: 1)

            // Рельс продолжается, но кружка на нём нет: событие одно.
            //
            // Ширина — та же, что у колонки маркера. С `markerSize`
            // линия под каждой прогулкой уезжала на три точки влево,
            // и рельс шёл ступеньками.
            Rectangle()
                .fill(Token.Surface.hairline)
                .frame(width: TimelineRail.lineWidth)
                .frame(width: TimelineRail.railWidth)

            HStack(spacing: Token.Space.s6) {
                Image(systemName: group.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(tint)
                    .wraps()
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
            .padding(.bottom, Token.Space.s6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var tint: Color {
        group.raisesAlarm ? Token.Status.overdueText : Token.Ink.secondary
    }

    /// «пописал ×3» вместо трёх одинаковых строк.
    private var label: String {
        var text = group.title
        if group.count > 1 { text += " ×\(group.count)" }
        if let detail = group.detail { text += " " + detail }
        return text
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
            // По левому краю — как все часы в этой колонке. С выравниванием
            // вправо промежуток стоял не под временем, а сам по себе,
            // и колонка выглядела рваной.
            Text(Fmt.gap(interval))
                .textStyle(AppFont.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: TimelineRail.timeWidth, alignment: .leading)

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
                    .foregroundStyle(Token.Ink.primary)
                    .fixedSize()
                    .frame(width: TimelineRail.timeWidth, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(Token.Action.primaryQuiet)
                        .frame(width: TimelineRail.nowDotSize + 10,
                               height: TimelineRail.nowDotSize + 10)
                    Circle()
                        .fill(Token.Ink.primary)
                        .frame(width: TimelineRail.nowDotSize, height: TimelineRail.nowDotSize)
                }
                .frame(width: TimelineRail.railWidth)

                Text("сейчас")
                    .textStyle(AppFont.micro.color(Token.Ink.primary))
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
            Text("Нажми «Просится», когда он подойдёт к двери. Через день здесь появится его режим — и станет видно, когда он правда хочет на улицу.")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.secondary)
            Text("Ничего заполнять заранее не надо.")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Режим дня
