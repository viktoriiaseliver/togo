import SwiftUI



/// Плакат: верхняя треть «Сегодня» — цветной блок состояния.
///
/// Figma: `PosterCard`. Решение дизайна окт 2026, утверждён концепт 1b
/// (`docs/design-handoff/design/Togo Смелее.dc.html`, `DECISIONS.md`
/// раздел «Сегодня»): верхняя треть — цветной блок (показание крупно,
/// косточка, «дальше»), **строки состояния нет** — она стала подписью
/// показания.
///
/// **Вид только красит. Правило живёт в `PosterMode`.**
/// Цвет блока спрашивают четыре поверхности — экран, «На улице»,
/// виджет и «остров», — и у Togo записано, чем кончается третья
/// реализация одного правила: виджет считал окно «не кормить»
/// собственной арифметикой, и сторож на вызов был к этому слеп.
/// Поэтому здесь нет ни одного `mode == .dose`: для этого есть
/// `needsInverseLabel` и `carriesStatusColour`, они отдельные нарочно.
///
/// **Чем оплачена сама необходимость этого файла.** `PosterMode`
/// написан, покрыт восемью тестами и до 07.10.2026 **не вызывался
/// ниоткуда** — тот же класс, что `replaceInPool` у Gamut: правило
/// верное, тест зелёный, действия нет. Поверхность при этом была
/// не «непроверенной», а **непроверяемой**: смотреть было не на что.
/// Чем красить плакат — **одно место на все поверхности.**
///
/// Вынесено из `TGPoster` 07.10.2026 по кадру. Блок прокручивается
/// вместе с содержимым, поэтому полосу под статус-баром красит ЭКРАН,
/// а не блок: `.ignoresSafeArea` внутри прокрутки не выходит за её
/// обрезку, и кадр показал над плакатом чёрную полосу.
///
/// **Но это не повод писать `switch` по режиму второй раз.** Правило
/// цвета у Togo уже трижды оказывалось списанным по местам применения,
/// и каждый раз третья копия расходилась молча. Здесь функция одна,
/// зовут её двое — блок и экран.
///
/// > **Два места, которым нужен один цвет, — это не повод для двух
/// > `switch`, а повод для одной функции.**
nonisolated enum PosterPaint {
    /// Подложка по режиму. Перечисление полное: добавят шестой режим —
    /// компилятор потребует решить, каким он будет, а не подставит
    /// обычный индиго молча.
    static func background(_ mode: PosterMode) -> Color {
        switch mode {
        case .usual: Token.Poster.background
        case .fasting: Token.Poster.backgroundFasting
        case .dose: Token.Poster.backgroundDose
        case .alarm: Token.Poster.backgroundAlarm
        case .quiet: Token.Poster.backgroundQuiet
        }
    }
}

struct TGPoster<Trailing: View>: View {

    /// Показание — главный ответ экрана.
    ///
    /// **Два числа с отдельными подписями единиц, а не одна строка.**
    /// Так в макете (`font-variant-numeric: tabular-nums`, «ч» и «мин»
    /// отдельными глифами 24 pt), и так надо по делу: одна строка
    /// «14 ч 15 мин» героем рвётся посередине числа — «14 ч» сверху,
    /// «15 мин» снизу, — и ровно это приехало кадром 24.09.
    enum Reading {
        /// Часы и минуты. Любая часть может быть нулём.
        case hoursMinutes(h: Int, m: Int)
        /// Считать нечего — тогда предложение, а не большее число.
        /// Так закрыт дефект 21.09: «434 ч назад · на улице были»
        /// говорило о СОБАКЕ то, чего приложение не знало.
        case sentence(LocalizedStringKey)
        /// Выход идёт — показание отвечает таймером.
        ///
        /// **Тем же `TGStopwatch`, что у героя, а не своим счётом.**
        /// На паузах начало сдвигается, и вторая арифметика разошлась бы
        /// с первой молча — у Togo это уже стоило трёх реализаций одного
        /// правила в виджете, на главном и в «острове».
        case running(session: ActiveSession, now: Date)
    }

    /// Подпись показания — прежняя строка состояния.
    struct Caption: Equatable {
        var symbol: String
        var text: LocalizedStringKey

        init(symbol: String, text: LocalizedStringKey) {
            self.symbol = symbol
            self.text = text
        }
    }

    /// «Дальше» — что и когда.
    struct Next: Equatable {
        var symbol: String
        var what: LocalizedStringKey
        var when: LocalizedStringKey

        init(symbol: String, what: LocalizedStringKey, when: LocalizedStringKey) {
            self.symbol = symbol
            self.what = what
            self.when = when
        }
    }

    let mode: PosterMode
    let reading: Reading
    var caption: Caption?
    var next: Next?
    /// Косточка: доля пройденного до следующего события, 0…1.
    /// `nil` — мерить нечего, и косточки нет вовсе.
    var progress: Double?
    /// Блок сжат (экран прокручен). Решение дизайна: при прокрутке блок
    /// сжимается, а не уезжает.
    var collapsed: Bool = false
    /// Шапка экрана внутри блока — она на цветном, а не над ним.
    @ViewBuilder var trailing: Trailing

    // MARK: Цвет

    private var background: Color { PosterPaint.background(mode) }

    /// Цвет цифр и надписей. **Цифры всегда основным текстом** —
    /// решение дизайна, и никаких `opacity` на тексте: `#666`
    /// под `0.85` это уже `#7D7D7D` и 4,12:1, а прозрачность
    /// съедает запас молча.
    private var ink: Color {
        if mode.needsInverseLabel { return Token.Poster.labelOnDose }
        // Нейтральный блок — тот, который не несёт цвета состояния.
        // Спрашиваем у режима тем же предикатом, что и подпись:
        // третья ветка к той же развилке, а не новая развилка.
        if !mode.carriesStatusColour { return Token.Poster.label }
        return Token.Poster.labelOnColor
    }

    /// Цвет подписей. **У плаката три семьи текста, а не одна.**
    ///
    /// ```
    /// четыре цветных блока   labelOnColor · captionOnColor
    /// нейтральный блок       label · caption
    /// доза                   labelOnDose · captionOnDose
    /// ```
    ///
    /// **Это переделка часа спустя, и повод у неё не мой.** Первая
    /// редакция брала две семьи — «обычную» и «инверсную на дозе», —
    /// и была верна **для тёмной темы**, которая в тот момент была
    /// единственной. `togo-08` завёл светлую и перемерил пять блоков
    /// × два текста × две темы:
    ///
    /// ```
    /// блок                старое ink/inkMuted   стало poster/fg·sub
    /// background           10,25 / 3,15  ✘      10,25 / 5,99
    /// backgroundAlarm      10,42 / 3,37  ✘      10,42 / 5,62
    /// backgroundFasting    10,00 / 3,52  ✘      10,00 / 5,37
    /// backgroundQuiet      16,12 / 16,15        16,12 / 1,17  ✘
    /// backgroundDose        1,64 / 1,47  ✘       1,64 / 12,86 ✘
    /// ```
    ///
    /// Нейтральный блок ломает «белый текст на плакате» ровно так же,
    /// как цветные ломали «тёмный»: в светлой теме он светло-серый,
    /// и белое на нём нечитаемо.
    ///
    /// > **Замер верен в той теме, в которой снят. Заведение нового
    /// > режима не правит числа — оно их обесценивает**, и перемерить
    /// > обязан тот, кто режим завёл. Ни один из двух замеров не был
    /// > ошибкой: устарела работа, а не человек.
    ///
    /// Запас на цветных блоках в светлой теме **тонкий и назван**:
    /// 5,04 · 4,70 · 4,56 при пороге 4,5. Сменят цвет блока —
    /// проверять заново, запас не бесконечен.
    ///
    /// Остальное про дозу — ниже, оно осталось верным.
    ///
    /// Дело в том, что доза — единственный режим со светлой подложкой,
    /// и обычная тихая подпись на ней нечитаема. Посчитал все девять
    /// пар плаката (арифметика по токенам, 07.10.2026):
    ///
    /// ```
    /// caption      на backgroundDose      1,17:1   НЕ ПРОХОДИТ
    /// caption      на background          5,31:1
    /// caption      на backgroundFasting   5,18:1
    /// caption      на backgroundAlarm     5,39:1
    /// caption      на backgroundQuiet     8,35:1
    /// label        на background         10,25:1
    /// labelOnDose  на backgroundDose     10,43:1
    /// bar          на background          6,23:1
    /// barOnDose    на backgroundDose     10,43:1
    /// ```
    ///
    /// Восемь из девяти в порядке; девятая — цена нашей же конструкции,
    /// и это стоит знать: **у плаката дизайн-пакета режима дозы нет
    /// вовсе** (замер `togo-08`), его блок всегда тёмный с белым
    /// текстом. Светлая акцентная подложка под тихой подписью —
    /// наша, и искать ответ в пакете бесполезно.
    ///
    /// Первая редакция брала здесь `labelOnDose` (10,43:1) — читаемо
    /// и **неверно по смыслу**: подпись становилась того же цвета, что
    /// показание, и иерархия «цифра громче подписи» на одном режиме
    /// из пяти пропадала. Вместо подстановки своего hex завёл токен
    /// у владельца токенов: источник правды — `DesignTokens/tokens.json`,
    /// а не этот файл.
    ///
    /// `Token.Poster.captionOnDose` даёт **6,19:1 в тёмной и 10,01:1
    /// в светлой**, и иерархия цела: показание на дозе 10,43 громче
    /// подписи 6,19. Числа сняты двумя независимыми счётами — его
    /// и моим, — и они не спорят до второго знака.
    ///
    /// И граница обоих замеров, названная нами одинаково: числа выше
    /// сняты **по токенам**, а не по пикселю. Прозрачность слоя вида
    /// арифметика не видит. Приёмка — кадр с замером точки; разойдётся
    /// с арифметикой — права точка. У нас это оплачено кнопкой 1,68:1,
    /// которую месяцами «проверяли глазами» при верном токене.
    private var subInk: Color {
        if mode.needsInverseLabel { return Token.Poster.captionOnDose }
        if !mode.carriesStatusColour { return Token.Poster.caption }
        return Token.Poster.captionOnColor
    }

    private var barInk: Color {
        mode.needsInverseLabel ? Token.Poster.barOnDose : Token.Poster.bar
    }

    // MARK: Вид

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trailing
            if !collapsed {
                captionRow
                readingRow
                if let progress { bone(progress) }
            } else {
                collapsedRow
            }
            if let next, !collapsed { nextRow(next) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Token.Space.s24)
        .padding(.bottom, collapsed ? Token.Space.s12 : Token.Space.s24)
        // **Цвет доходит до верха, содержимое — нет.** Подложка вынесена
        // в `.background` и игнорирует безопасную область сама; текст
        // и шапка остаются внутри неё.
        //
        // Первая редакция делала обратное — `.ignoresSafeArea` стоял
        // на всей прокрутке экрана, — и кадр 07.10 показал, во что это
        // обходится: **шапка «Стич · 4,1 кг · дежурит Тео» ушла под
        // статус-бар и обрезалась**, наложившись на часы и батарею.
        // Ни один замер этого не поймал: цвет был верным, токены
        // верными, тест мерил пиксель подложки и был прав.
        //
        // > **Замер отвечает на вопрос, который ему задали. Кадр
        // > показывает то, о чём спросить не догадались.**
        //
        // Скругление живёт здесь же, на подложке: примени его снаружи —
        // и оно обрежет расширение вверх ровно там, где оно нужно.
        .background {
            background
                .clipShape(
                    .rect(bottomLeadingRadius: Token.Radius.poster,
                          bottomTrailingRadius: Token.Radius.poster)
                )
                .ignoresSafeArea(edges: .top)
        }
        // **Безопасной области здесь нет нарочно.** На «Сегодня» блок
        // обязан идти от статус-бара, и `.ignoresSafeArea(edges: .top)`
        // ставит ЭКРАН, а не компонент. Первая редакция держала это
        // внутри — и плакат в галерее полез под статус-бар, где он
        // не при чём: один и тот же компонент стоит и в верхней трети
        // экрана, и девятью штуками в списке.
        //
        // > Решение о безопасной области принадлежит тому, кто знает,
        // > где компонент стоит. Компонент этого не знает.
        //
        // Та же причина, по которой поверхность пришлось делать
        // снимаемой: пока вид сам решал про экран, построить его вне
        // экрана было нельзя.
    }

    @ViewBuilder
    private var captionRow: some View {
        // На нейтральном блоке статусной подписи нечего делать —
        // спрашиваем у режима, а не у себя.
        if let caption, mode.carriesStatusColour {
            HStack(spacing: Token.Space.s6) {
                Image(systemName: caption.symbol)
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .accessibilityHidden(true)
                Text(caption.text)
                    .textStyle(AppFont.captionEmphasis.color(subInk))
                    .wraps()
            }
            .foregroundStyle(subInk)
            .padding(.top, Token.Space.s8)
        }
    }

    @ViewBuilder
    private var readingRow: some View {
        switch reading {
        case .running(let session, let сейчас):
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                TGStopwatch(session: session, now: сейчас,
                            style: AppFont.hero.color(ink))
                Text(session.isPaused ? "на паузе" : "на улице")
                    .textStyle(AppFont.caption.color(subInk))
                Spacer(minLength: 0)
            }
            .padding(.top, Token.Space.s4)
        case .sentence(let фраза):
            Text(фраза)
                .textStyle(AppFont.sectionTitle.color(ink))
                .wraps()
                .padding(.top, Token.Space.s4)
        case .hoursMinutes(let h, let m):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                число(h)
                единица("ч")
                Spacer().frame(width: Token.Space.s12)
                число(m)
                единица("мин")
                Spacer(minLength: 0)
            }
            .padding(.top, Token.Space.s4)
        }
    }

    /// Цифра показания.
    ///
    /// **112 pt — по обоим макетам для ширины 402** (`Togo Смелее` 1b
    /// и шаблон плаката в `Togo ФИНАЛ`). Описание токена
    /// `Token.FontSize.hero` говорит про 96/80/112 с осью устройства —
    /// это про ДРУГОЙ элемент, прежнего героя одной строкой; проверено
    /// 07.10: все семь вхождений `96px` в `ФИНАЛ` — зазоры и маски
    /// прокрутки, а не цифра.
    ///
    /// **Оси устройства в наших токенах нет**, и заводить её здесь
    /// нельзя — это отдельная работа у владельца токенов. Поэтому
    /// число **ужимается, а не рвётся**: у нас записано, что герой —
    /// ответ на главный вопрос экрана и обрезать его нельзя ни при
    /// какой настройке (кадр 28.09: «2 ч 9… назад» при 0,6).
    /// Что получится на SE 375 — вопрос к кадру, а не к рассуждению,
    /// и кадр снимается приёмкой.
    private func число(_ значение: Int) -> some View {
        Text(значение.formatted())
            .font(.system(size: 112, weight: Token.FontWeight.light, design: .rounded))
            // Табличные цифры: иначе показание дёргается каждую минуту,
            // потому что «1» уже «4».
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
    }

    private func единица(_ слово: LocalizedStringKey) -> some View {
        Text(слово)
            .font(.system(size: Token.FontSize.display - 10,
                          weight: Token.FontWeight.regular, design: .rounded))
            .foregroundStyle(subInk)
    }

    /// Сжатая строка: показание и «дальше» в одну линию.
    @ViewBuilder
    private var collapsedRow: some View {
        HStack(spacing: Token.Space.s8) {
            switch reading {
            case .running(let session, let сейчас):
                TGStopwatch(session: session, now: сейчас,
                            style: AppFont.cardTitle.color(ink))
            case .sentence(let фраза):
                Text(фраза).textStyle(AppFont.cardTitle.color(ink)).lineLimit(1)
            case .hoursMinutes(let h, let m):
                Text(.готовая("\(h) ч \(m) мин"))
                    .textStyle(AppFont.cardTitle.color(ink))
                    .monospacedDigit()
            }
            if let next {
                Text(next.when).textStyle(AppFont.caption.color(subInk)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Token.Space.s4)
    }

    /// Косточка — полоса до следующего события.
    private func bone(_ доля: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(barInk.opacity(0.25))
                Capsule()
                    .fill(barInk)
                    .frame(width: max(0, min(1, доля)) * geo.size.width)
            }
        }
        .frame(height: Token.Size.bone)
        .padding(.top, Token.Space.s24)
        .accessibilityHidden(true)
    }

    private func nextRow(_ next: Next) -> some View {
        HStack(spacing: Token.Space.s6) {
            Image(systemName: next.symbol)
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .accessibilityHidden(true)
            Text("дальше").textStyle(AppFont.caption.color(subInk))
            Text(next.what).textStyle(AppFont.captionEmphasis.color(ink)).wraps()
            Spacer(minLength: Token.Space.s8)
            Text(next.when).textStyle(AppFont.caption.color(subInk))
        }
        .padding(.top, Token.Space.s12)
    }
}

extension TGPoster where Trailing == EmptyView {
    init(mode: PosterMode,
         reading: Reading,
         caption: Caption? = nil,
         next: Next? = nil,
         progress: Double? = nil,
         collapsed: Bool = false) {
        self.init(mode: mode, reading: reading, caption: caption, next: next,
                  progress: progress, collapsed: collapsed) { EmptyView() }
    }
}
