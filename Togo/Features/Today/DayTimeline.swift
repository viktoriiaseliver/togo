import SwiftUI
import UIKit

/// Лента дня.
///
/// Переписана 22.10.2026 под хендофф `design_handoff_togo_ios28`, раздел
/// «Лента дня», решением Виктории «перепиши всё под дизайн».
///
/// ## Что изменил хендофф
///
/// Строка была рельсом: колонка времени 48, вертикальная линия, кружок 24
/// на ней. Стало — **сплошные строки `surface-card`**: время 44 справа,
/// кружок категории 40, заголовок 17, подпись 14. Рельса нет: сквозь него
/// (и сквозь стекло, которым его сперва рисовали) просвечивали кнопки
/// свайпа, и строка переставала читаться как строка.
///
/// ## Что от прежней редакции осталось нарочно
///
/// Каждое из этого оплачено кадром или отзывом, и хендофф ни одного
/// не отменяет:
///
/// * **Промежуток «дома N» между выходами.** Всё приложение про интервалы;
///   хендофф просит ровно это («Между выходами — строка „дома 3 ч“»), и
///   считает их по-прежнему `TimelineBuilder.timeIndoors` — от выхода
///   до выхода, не сбиваясь о еду посередине.
/// * **Отметки прогулки — своими строками под ней.** Это части одного
///   события, а не соседние события.
/// * **Строка — кнопка, а не жест.** Жест не даёт ни отклика, ни имени
///   для озвучки.
/// * **Ширина колонки времени масштабируется.** При плоских 44 на крупной
///   системной настройке «07:00» печаталось как «07:0» — кадр 28.09.
///   Число, обрезанное на последней цифре, читается как другое число.
/// * **Погашенная строка, пока висит тост.** Это вторая половина кнопки
///   «Отменить».
///
/// ## Свайпа здесь нет, и это стык, а не упущение
///
/// Хендофф просит `List` со `swipeActions`. `DayTimeline` стоит внутри
/// `ScrollView` у обоих хозяев (`TodayScreen.swift:123` и `TGSheet`
/// в `HistoryScreen`), а `List` внутри `ScrollView` не живёт: своей высоты
/// он не считает. Поэтому `List`-редакция лежит отдельно —
/// `DayTimelineList`, — и включается тем, кто владеет хозяином.
/// Собственный свайп взамен не писан нарочно: хендофф его прямо
/// не рекомендует, а прежняя попытка и дала ту самую просвечивающую строку.
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
        TGCard(padding: 0, spacing: 0) {
            Text(Fmt.dayTitle(now))
                .textStyle(AppFont.micro)
                .textCase(.lowercase)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Token.Spacing.cardPadding)
                .padding(.top, Token.Spacing.cardPadding)
                .padding(.bottom, Token.Space.s8)

            if blocks.isEmpty {
                EmptyDayState()
                    .padding(.horizontal, Token.Spacing.cardPadding)
                    .padding(.bottom, Token.Spacing.cardPadding)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    // Промежуток стоит ПЕРЕД выходом, а не после предыдущей
                    // записи: он отвечает на «сколько он терпел до этого раза».
                    if let indoors = TimelineBuilder.timeIndoors(
                        before: index, in: blocks, threshold: Self.gapThreshold) {
                        DayTimelineGapRow(interval: indoors)
                    } else if index > 0 {
                        TGDivider(inset: DayTimelineRow.separatorInset)
                    }

                    Button { onTap(block.event) } label: {
                        DayTimelineRow(block: block, showsAuthor: showsAuthor)
                    }
                    .buttonStyle(DayTimelineRowButtonStyle())

                    ForEach(block.markGroups) { group in
                        Button {
                            // Одна отметка открывается сама. У группы «какая
                            // из трёх» — вопрос без смысла, ровно по той же
                            // причине, по которой у неё нет и времени.
                            onTap(group.count == 1 ? group.representative : block.event)
                        } label: {
                            DayTimelineMarkRow(group: group)
                        }
                        .buttonStyle(DayTimelineRowButtonStyle())
                    }
                }
                if showsNow {
                    NowMarker(now: now, sinceLast: sinceLastEntry)
                        .padding(.horizontal, Token.Spacing.cardPadding)
                        .padding(.bottom, Token.Spacing.cardPadding)
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

/// Строка ленты дня.
///
/// Геометрия из хендоффа: время 44 справа-выровнено 15 semibold · кружок
/// категории 40 · заголовок 17 + подпись 14. Выносится отдельным типом,
/// потому что её рисуют два контейнера — карточка (`DayTimeline`) и список
/// со свайпом (`DayTimelineList`), — и расходиться им нельзя.
struct DayTimelineRow: View {
    let block: TimelineBlock
    /// В семье из одного человека подпись автора — шум: и так понятно, кто.
    var showsAuthor: Bool = false

    private var event: LogEvent { block.event }

    /// Запись удаляется — и пока висит тост, строка стоит зачёркнутой:
    /// это вторая половина кнопки «Отменить». Уехал тост — ушла и строка.
    private var isCancelled: Bool { event.deletedAt != nil }

    /// Отступ разделителя: он начинается там, где начинается текст, —
    /// то есть за колонкой времени и кружком. Разделитель во всю ширину
    /// резал бы строку под кружком пополам.
    static var separatorInset: CGFloat {
        Token.Spacing.cardPadding + timeWidth + Token.Space.s12
            + Token.Size.avatarMd + Token.Space.s12
    }

    /// Колонка времени. Хендофф задаёт 44 — берём `Token.Size.tapTarget`,
    /// это та же величина с именем.
    static var timeWidth: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: Token.Size.tapTarget)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            время
            CategoryBadge(kind: event.kind,
                          raisesAlarm: event.raisesAlarm,
                          isDeleted: isCancelled)

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                HStack(spacing: Token.Space.s8) {
                    // Цвет ВМЕСТО стилевого, а не поверх: `AppFont` несёт
                    // свой `color` и красит сам `Text`, то есть побеждает
                    // `foregroundStyle`. Прежняя редакция этой строки
                    // накладывала цвет сверху — на `bodyEmphasis` это
                    // сходило с рук только потому, что цвета совпадали.
                    Text(isCancelled ? event.kind.title + " · отменено" : event.kind.title)
                        .textStyle(AppFont.bodyEmphasis,
                                   color: isCancelled ? Token.Ink.secondary : event.titleColor)
                        .strikethrough(isCancelled, color: Token.Ink.secondary)
                    Spacer(minLength: 0)
                    if showsAuthor {
                        TGAuthorMark(author: event.authorName)
                    }
                }
                if let подпись {
                    Text(подпись)
                        .textStyle(AppFont.micro)
                        .wraps()
                }
            }
        }
        .padding(.horizontal, Token.Spacing.cardPadding)
        .padding(.vertical, Token.Space.s10)
        // Цель касания у строки не меньше 44: `ПолКегляTests` и
        // рекомендация хендоффа 4 требуют этого от всего, что нажимают.
        .frame(minHeight: Token.Size.tapTarget)
        .accessibilityElement(children: .combine)
    }

    /// У события с длительностью в колонке времени стоит интервал,
    /// а не только начало: прогулка — это отрезок, и человек ищет глазами
    /// именно «с и до».
    private var время: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Fmt.clock(block.startedAt))
                .textStyle(AppFont.numeric(Token.FontSize.meta,
                                           weight: Token.FontWeight.semibold),
                           color: isCancelled ? Token.Ink.secondary : Token.Ink.primary)
            if block.isSpan {
                Text(Fmt.clock(block.endedAt))
                    .textStyle(AppFont.numeric(Token.FontSize.meta,
                                               weight: Token.FontWeight.regular),
                               color: Token.Ink.secondary)
            }
        }
        .fixedSize()
        // Ширина растёт вместе с кеглем — см. голову файла про «07:0».
        .frame(width: Self.timeWidth, alignment: .trailing)
    }

    /// Что писать под названием.
    ///
    /// У события с длительностью — сколько оно шло. Итог прогулки
    /// («пописал · стул») здесь не повторяем: он и так стоит строками
    /// ниже, и раньше одно и то же было написано дважды.
    private var подпись: String? {
        if isCancelled { return String(localized: "след остаётся") }
        guard block.isSpan else { return event.subtitle }
        let minutes = Int(block.endedAt.timeIntervalSince(block.startedAt)) / 60
        return String(localized: "\(minutes) минут")
    }
}

/// Отметка внутри прогулки: то, что собака сделала, пока гуляли.
///
/// Отдельной строкой, но подчинённой — без своего кружка и мельче.
/// Это часть прогулки, а не соседнее событие.
///
/// Название берётся своё, а не общее имя вида записи: «пописал» вместо
/// «Выход». Раньше отметка внутри прогулки называлась ровно так же, как
/// самостоятельный выход по нужде, — одно слово на два разных события.
struct DayTimelineMarkRow: View {
    let group: MarkGroup

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            // Времени здесь нет намеренно: внутри прогулки его задаёт сама
            // прогулка («18:12 — 18:45»). В живом дневнике три «пописал»
            // стояли в 06:34, 06:38 и 06:39, и человек не узнавал из этих
            // цифр ничего, чего не знал бы из «×3».
            Color.clear
                .frame(width: DayTimelineRow.timeWidth, height: Token.Size.hairline)

            Image(systemName: group.kind.symbol)
                .font(.system(size: Token.Size.iconSm, weight: Token.FontWeight.semibold))
                .foregroundStyle(цвет)
                .frame(width: Token.Size.avatarMd)
                .accessibilityHidden(true)

            Text(подпись)
                .textStyle(AppFont.micro, color: цвет)
                .wraps()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Token.Spacing.cardPadding)
        .padding(.bottom, Token.Space.s8)
        .frame(minHeight: Token.Size.tapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(подпись)
    }

    private var цвет: Color {
        group.raisesAlarm ? Token.Status.overdueText : Token.Ink.secondary
    }

    /// «пописал ×3» вместо трёх одинаковых строк.
    private var подпись: String {
        var text = group.title
        if group.count > 1 { text += " ×\(group.count)" }
        if let detail = group.detail { text += " " + detail }
        return text
    }
}

/// Нажатие видно: строка на мгновение подсвечивается. Без этого тап
/// по ленте ощущается как промах.
struct DayTimelineRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(Token.Surface.sunken.opacity(configuration.isPressed ? 1 : 0))
            .animation(.easeOut(duration: Token.Duration.instant), value: configuration.isPressed)
    }
}

/// Сколько собака была дома между выходами.
///
/// Единственное, что отличает эту ленту от списка строк: всё приложение
/// про интервалы, и здесь они наконец видны. Хендофф просит эту строку
/// со значком `home` — в SF Symbols это `house`.
///
/// Считать промежутки между кормлениями смысла нет: их человек и так
/// примерно знает. А вот «сколько он уже терпит» — то, ради чего в ленту
/// вообще смотрят.
struct DayTimelineGapRow: View {
    let interval: TimeInterval
    /// Промежуток открыт: собака дома прямо сейчас.
    var isOpen: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.s12) {
            Text(Fmt.gap(interval))
                .textStyle(AppFont.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: DayTimelineRow.timeWidth, alignment: .trailing)

            Image(systemName: "house")
                .font(.system(size: Token.Size.iconSm, weight: Token.FontWeight.medium))
                .foregroundStyle(Token.Ink.secondary)
                .frame(width: Token.Size.avatarMd)
                .accessibilityHidden(true)

            Text(isOpen ? "дома с прошлого выхода" : "дома между выходами")
                .textStyle(AppFont.micro)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Token.Spacing.cardPadding)
        .padding(.vertical, Token.Space.s8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("дома \(Fmt.duration(interval)) с прошлого выхода")
    }
}

/// «Сейчас» — живая точка в той же колонке.
///
/// Единственная акцентная вещь в ленте: акцент означает действие и текущий
/// момент, и больше ничего.
struct NowMarker: View {
    let now: Date
    var sinceLast: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            if let sinceLast {
                DayTimelineGapRow(interval: sinceLast, isOpen: true)
            }

            HStack(alignment: .center, spacing: Token.Space.s12) {
                Text(Fmt.clock(now))
                    .textStyle(AppFont.numeric(Token.FontSize.meta,
                                               weight: Token.FontWeight.semibold),
                               color: Token.Ink.primary)
                    .fixedSize()
                    .frame(width: DayTimelineRow.timeWidth, alignment: .trailing)

                // **`Token.Action.primary`, а не `Component.Timeline.nowMarker`** —
                // красная линия проекта: в `Togo/Features` только `Token.*`
                // и `TG*`, компонентные токены принадлежат дизайн-системе.
                // Храповик `ComponentTokenScopeTests` поймал это как
                // одиннадцатое обращение при записанных десяти.
                //
                // Пикселя правка не двигает: шапка `Tokens.generated.swift:20`
                // объявляет `Timeline.nowMarker == Action.primary`, оба сидят
                // на примитиве `arctic`. В «Кино» это `#FFFFFF` в тёмной
                // и `#1F4FFF` в светлой.
                //
                // > **Следствие названо, а не замолчано: у
                // > `Component.Timeline.nowMarker` теперь НОЛЬ живых
                // > читателей в Swift.** Это наш класс «поле без читателя»:
                // > грепом оно находится один раз, в объявлении, и выглядит
                // > работающим. Если метка «сейчас» должна когда-нибудь
                // > разойтись с акцентом — расходиться ей придётся через
                // > семантику, а не через этот токен.
                //
                // **ТОКЕН ЖИВ, И «НОЛЬ ЧИТАТЕЛЕЙ В SWIFT» — НЕ ПОВОД ЕГО
                // СНОСИТЬ.** Половина замера выше верна, а разобрана
                // 23.10.2026, потому что одной строкой «ноль живых
                // читателей» она читается как приговор. Читатели есть,
                // просто не в Swift:
                //
                // ```
                // DesignTokens/build/figma-variables.json   timeline/nowMarker
                //        → переменная УЕЗЖАЕТ ДИЗАЙНЕРУ в Фигму
                // DesignTokens/build/tokens.css             три темы:
                //        #FFFFFF (тёмная) · #1F4FFF (светлая) · #0E14A1 (lightHC)
                // TogoTests/DesignTokenTests.swift:108      инвариант
                //        nowMarker == Action.primary — СТОРОЖ ЖИВОЙ
                // Tools/generate_tokens.py:120              тот же инвариант
                //        назван в голове генератора
                // ```
                //
                // Это ровно случай `Token.FontSize.micro` (`55138f4`):
                // ступень с нулём вызовов в Swift уезжала в макет, и
                // применивший получал в Фигме не то, что в приложении.
                // **Отличие у нас одно, и оно решающее: там инварианта
                // не было, здесь есть.** Опусти `micro` — не покраснело бы
                // ничто; разведи `nowMarker` с `Action.primary` —
                // `DesignTokenTests:108` краснеет в ту же секунду.
                //
                // > **«Ноль читателей» отвечает про язык, на котором
                // > спросили.** Прежде чем сносить токен, спрашивать его
                // > не только в `*.swift`: у токена три поверхности —
                // > Swift, CSS и переменная Фигмы, — и уехать к человеку
                // > он может мимо кода.
                Circle()
                    .fill(Token.Action.primary)
                    .frame(width: Token.Size.handleH, height: Token.Size.handleH)
                    .frame(width: Token.Size.avatarMd)

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
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            Image(systemName: "sun.horizon")
                .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.light))
                .foregroundStyle(Token.Ink.silhouette)
                .padding(.bottom, Token.Space.s2)
                .accessibilityHidden(true)
            Text("Пока пусто").textStyle(AppFont.cardTitle, color: Token.Ink.primary)
            Text("Нажми «Просится», когда он подойдёт к двери. Через день здесь появится его режим — и станет видно, когда он правда хочет на улицу.")
                .textStyle(AppFont.caption, color: Token.Ink.secondary)
            Text("Ничего заполнять заранее не надо.")
                .textStyle(AppFont.caption, color: Token.Ink.secondary)
        }
        .padding(.vertical, Token.Space.s8)
    }
}
