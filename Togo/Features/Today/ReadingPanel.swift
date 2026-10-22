import SwiftUI

/// Верхний блок «Сегодня»: фото, шапка, крупный заголовок, чип состояния
/// и стеклянная панель показания.
///
/// Решение Виктории 22.10.2026, источник — `design_handoff_togo_ios28`.
/// **Геометрия и состав сняты с КАДРОВ** (`screenshots/01.png` — обычный
/// день, `02.png` — время дозы), а не с прозы README: они расходятся,
/// и расхождения названы ниже поимённо.
///
/// ```
/// README говорит                        на кадре 01/02 видно
/// «пилюля второго состояния (≤ 1)»      пилюль ДВЕ, и места разные:
///                                       «Запас 5 дн» справа В СТРОКЕ
///                                       ЗАГОЛОВКА, «Доза по часам»
///                                       отдельной строкой слева
/// про крупный заголовок молчит          «Сегодня» 36 pt белым есть,
///                                       и он несёт правую пилюлю
/// «строка „Дальше · {когда}“ 17 sb»     строки ДВЕ, и вторая красится
///                                       тоном ВТОРОГО состояния
///                                       (на 02 — янтарём)
/// «панель показания (высота 360)»       360 — это блок с фото целиком,
///                                       а стеклянная панель внутри него
/// ```
///
/// > **Кадр старше прозы.** Проза README описывает не всё и местами
/// > иначе; где они разошлись, здесь исполнен кадр, а расхождение
/// > названо в отчёте — чтобы правил его тот, у кого есть право.
///
/// ## Красные линии, которые тут стреляют
///
/// **Прозрачности на тексте нет ни в одном состоянии.** Текст берёт
/// сплошной цвет; считать контраст надо по **композиту** — панель
/// поверх фото, — а не по исходному цвету панели. Это работа приёмки
/// по кадру, компилятор такого не ловит.
///
/// **`ViewThatFits` не применяется** — запрещён в проекте: он держал
/// в дереве обе раскладки, и озвучка находила две кнопки «Отменить».
/// Раскладка выбирается явным `if` по `dynamicTypeSize`, как
/// в `ActionGrid` и `UndoToastView`.
struct ReadingPanel<Шапка: View>: View {
    /// Тон — он один на панель, чип, фото и главную кнопку.
    let tone: ReadingTone
    /// Чип состояния: отдельная строка слева под заголовком.
    /// На кадре 01 это «Дома», на 02 — «Доза по часам · 17:59».
    let чип: Чип
    /// Пилюля справа в строке заголовка. Независима от тона:
    /// на обоих кадрах «Запас 5 дн» терракотовая, хотя тона разные.
    var пилюля: Пилюля?
    /// Само показание.
    let показание: Показание
    /// «гулял в 15:44 · обычно до 22:44» — две подписи под показанием.
    var откуда: String?
    var докуда: String?
    /// Насколько заполнена полоса-косточка, 0…1. Пусто — полосы нет.
    var доля: Double?
    /// Фото собаки. Пусто — фона нет, остаётся заливка.
    var фото: Data?
    /// Шапка: аватар, кличка, «вес · дежурит», кнопка «…».
    @ViewBuilder var шапка: Шапка

    @Environment(\.dynamicTypeSize) private var размерТекста
    /// Прозрачность выключена в системе — блюра не будет, будет
    /// сплошная поверхность (хендофф, «Рекомендации» 7).
    @Environment(\.accessibilityReduceTransparency) private var безПрозрачности

    /// Чип состояния — светлый на обычном дне, цветной на дозе.
    struct Чип {
        let символ: String
        let текст: LocalizedStringKey
        /// Тон чипа. Обычно равен тону экрана, но не всегда: на кадре 01
        /// экран нейтральный, а чип «Дома» светлый.
        var цветной: Bool = false
    }

    /// Пилюля в строке заголовка.
    struct Пилюля {
        let символ: String
        let текст: LocalizedStringKey
    }

    /// Что стоит крупно.
    ///
    /// Три вида, и у каждого свой смысл — правило взято у
    /// `TGPoster.Reading`: **число без имени читается как что угодно**,
    /// поэтому вид показания решает, нужна ли подпись.
    enum Показание {
        /// Часы и минуты. Принимает **интервал**, а не пару чисел:
        /// строку печатает `Fmt.hoursMinutes`, у которого единицы
        /// печатает система.
        ///
        /// Прототип собирал это склейкой — `h + 'ч' + m + 'мин'`, —
        /// и ровно такие склейки хендофф запрещает переносить:
        /// 154 фрагмента («` мин`», «`гулял в `») в `xcstrings`
        /// **не включены** нарочно. Собрать «2 ч 12 мин» на любом
        /// языке, кроме русского, из кусков нечем.
        case часыМинуты(TimeInterval)
        /// Минуты и секунды — идущий выход. `Fmt.stopwatch`.
        case минутыСекунды(TimeInterval)
        /// Фраза: «Сегодня ещё не выходили».
        case фраза(LocalizedStringKey)
    }

    // Имена величин — из `tokens/togo-ios28.tokens.json`. Токенов
    // с такими именами в проекте ещё НЕТ: их заводит другой агент.
    // Пока они константами с адресом источника, и это названо
    // в отчёте, а не спрятано.
    //
    //   size.hero            360   высота блока с фото
    //   size.heroAX          220   та же высота на крупном кегле
    //   size.heroPanelRadius  24   радиус стеклянной панели
    //   type.reading          56 / 300 / SF Pro Rounded
    //   cinema.titleLarge     36 / −0.025
    private var высота: CGFloat { размерТекста.isAccessibilitySize ? 220 : 360 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            фон
            VStack(alignment: .leading, spacing: Token.Space.s8) {
                шапка
                строкаЗаголовка
                чипСостояния
                Spacer(minLength: Token.Space.s12)
                стекляннаяПанель
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.bottom, Token.Space.s16)
        }
        .frame(minHeight: высота)
        // Опознаётся приёмкой по РАМКЕ блока, а не по доле экрана:
        // координата от края экрана меряет экран, рамка меряет элемент.
        // На этом однажды уже промахнулись — точка «92 % ширины, 9 %
        // высоты» попадала в шестерёнку настроек.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("панель-показания")
    }

    // MARK: Фон

    /// Фото под всем блоком, затемнённое к низу и подкрашенное тоном.
    ///
    /// **Тон красит ФОТО, а не только панель** — это видно на кадре 02:
    /// при дозе синим залит весь верх экрана, не один прямоугольник.
    /// В токенах это `backdrop.tint` (`softLight`, 55–60 % прозрачности).
    private var фон: some View {
        ZStack {
            Token.Surface.screen
            if let фото, let картинка = UIImage(data: фото) {
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFill()
            }
            // Затемнение к низу: без него текст показания ложится
            // на светлое место фотографии и пропадает. Это `--bd-scrim`.
            LinearGradient(
                colors: [Token.Surface.scrim.opacity(0.70),
                         Token.Surface.scrim.opacity(0.15),
                         Token.Surface.scrim],
                startPoint: .top,
                endPoint: .bottom
            )
            if let подкраска {
                подкраска.opacity(0.55).blendMode(.softLight)
            }
            // Ночь: `saturate(.3) brightness(.7)` — приглушается ФОТО,
            // а не панель.
            if tone.dimsPhoto {
                Token.Surface.scrim.opacity(0.30)
            }
        }
        .clipped()
        // Фото — оформление. Голосом его читать нечем, а подпись
        // к нему была бы выдумкой: мы не знаем, что на фотографии.
        .accessibilityHidden(true)
    }

    /// Подкраска фото по тону. Пусто — фото остаётся как есть.
    private var подкраска: Color? {
        switch tone {
        case .dose: Token.Action.primary
        case .fasting: Token.Status.waitingText
        case .alarm: Token.Status.overdueText
        case .normal, .night, .walk: nil
        }
    }

    // MARK: Заголовок и чипы

    /// «Сегодня» крупно и пилюля запаса справа.
    ///
    /// Заголовок рисуем **сами**, а не `navigationTitle`: по кадру он
    /// лежит поверх фотографии и делит строку с пилюлей, чего системный
    /// заголовок не умеет.
    private var строкаЗаголовка: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
            Text("Сегодня")
                .textStyle(AppFont.screenTitle, color: Token.Ink.onAccent)
                .wraps()
            Spacer(minLength: Token.Space.s8)
            if let пилюля { пилюляВида(пилюля) }
        }
    }

    private func пилюляВида(_ п: Пилюля) -> some View {
        HStack(spacing: Token.Space.s6) {
            Image(systemName: п.символ)
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .accessibilityHidden(true)
            Text(п.текст).textStyle(AppFont.captionEmphasis, color: Token.Status.stockLowText)
                .wraps()
        }
        .foregroundStyle(Token.Status.stockLowText)
        .padding(.horizontal, Token.Space.s10)
        // Не кнопка, но высота — как у цели касания: так пилюля
        // не схлопывается на мелком кегле и остаётся читаемой.
        .frame(minHeight: Token.Size.tapTarget)
        .background(Token.Status.stockLowBg, in: Capsule())
    }

    /// Чип состояния — отдельной строкой слева под заголовком.
    private var чипСостояния: some View {
        HStack(spacing: Token.Space.s6) {
            Image(systemName: чип.символ)
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .accessibilityHidden(true)
            Text(чип.текст)
                .textStyle(AppFont.captionEmphasis, color: чернилаЧипа)
                .wraps()
        }
        .foregroundStyle(чернилаЧипа)
        .padding(.horizontal, Token.Space.s10)
        .frame(minHeight: Token.Size.tapTarget)
        .background(заливкаЧипа, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Стеклянная панель

    private var стекляннаяПанель: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            показаниеКрупно
            if откуда != nil || докуда != nil { строкаСДо }
            if let доля { полосаКосточка(доля) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Token.Space.s16)
        // `background { … }` со слотом, а не `background(_:in:)`:
        // поверхность тут ВЬЮ (материал либо заливка), а не `ShapeStyle`,
        // и форму ей задаёт обрезка. Компилятор сказал это прямо —
        // «requires that 'some View' conform to 'ShapeStyle'».
        .background {
            поверхность
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    /// Показание крупно: SF Rounded 300, 56 pt.
    ///
    /// **Кегль через `relativeTo:`, а не голым `Font.system(size:)`** —
    /// голый размер настройку iOS не спрашивает, и на кадре 28.09
    /// половина экрана выросла, а половина осталась мелкой. Это хуже,
    /// чем если бы не вырос никто: выглядит поломкой, а не ограничением.
    @ViewBuilder
    private var показаниеКрупно: some View {
        let шрифт = Font.system(size: 56, weight: .light, design: .rounded)
        switch показание {
        case .часыМинуты(let интервал):
            Text(Fmt.hoursMinutes(интервал))
                .font(шрифт)
                .foregroundStyle(чернила)
                .minimumScaleFactor(0.5)
                .wraps()
        case .минутыСекунды(let интервал):
            Text(Fmt.stopwatch(интервал))
                .font(шрифт)
                .monospacedDigit()
                .foregroundStyle(чернила)
                .minimumScaleFactor(0.5)
        case .фраза(let текст):
            // Фраза кеглем 56 не влезет никогда — у неё свой стиль.
            // Это не «мельче ради места», а другой вид показания:
            // число отвечает «сколько», фраза — «нечего считать».
            Text(текст)
                .textStyle(AppFont.cardTitle, color: чернила)
                .wraps()
        }
    }

    /// «гулял в 15:44 · обычно до 22:44» — 14 semibold.
    private var строкаСДо: some View {
        HStack(spacing: Token.Space.s6) {
            if let откуда {
                Text(откуда).textStyle(AppFont.captionEmphasis, color: чернилаПодписи)
            }
            if откуда != nil, докуда != nil {
                Text(verbatim: "·").foregroundStyle(чернилаПодписи)
            }
            if let докуда {
                Text(докуда).textStyle(AppFont.captionEmphasis, color: чернилаПодписи)
            }
        }
        .wraps()
    }

    /// Полоса-косточка: сколько прошло от выхода до следующего.
    ///
    /// Доля приходит готовой — считать её здесь значило бы завести
    /// вторую реализацию ритма рядом с `WalkRhythmAnalyzer`.
    private func полосаКосточка(_ доля: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(чернила.opacity(0.18))
                Capsule()
                    .fill(чернилаПолосы)
                    .frame(width: max(0, min(1, доля)) * proxy.size.width)
            }
        }
        .frame(height: Token.Size.bone)
        // Полоса — графика, а не орган управления: число уже сказано
        // показанием выше, и читать её голосом нечем.
        .accessibilityHidden(true)
    }

    // MARK: Цвета тона

    /// Поверхность панели.
    ///
    /// **Reduce Transparency → сплошная поверхность без блюра**
    /// (хендофф, «Рекомендации» 7). Иначе `--g-strong`: в тёмной
    /// и «Кино» это `.ultraThinMaterial`, как сказано
    /// в `togo-ios28.tokens.json` (`glass.swiftui`).
    @ViewBuilder
    private var поверхность: some View {
        if tone.paintsPanel {
            // Янтарь, синий и терракот кроют панель целиком — стекла
            // под ними нет вовсе, и блюр тут ничего не решает.
            Rectangle().fill(заливкаПанели)
        } else if безПрозрачности {
            Rectangle().fill(Token.Surface.card)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    /// Заливка панели у тех трёх тонов, что её красят.
    ///
    /// Значения — `tokens/togo-ios28.tokens.json`, раздел `readingTone`.
    /// **Токенов с этими именами в проекте ещё нет**, и завести их мне
    /// нельзя (`DesignTokens/**` и `Togo/DesignSystem/**` — чужие пути).
    /// Здесь ближайшие живые токены того же смысла; точные значения
    /// названы в отчёте: `fasting rgba(255,194,51,.92)`,
    /// `dose rgba(31,79,255,.92)`, `alarm rgba(213,37,25,.92)`.
    private var заливкаПанели: Color {
        switch tone {
        case .fasting: Token.Status.waitingBg
        case .dose: Token.Action.primary
        case .alarm: Token.Status.overdueText
        case .normal, .night, .walk: Token.Surface.card
        }
    }

    /// Чернила показания.
    ///
    /// На крашеной панели их диктует тон (`#2A1D00` на янтаре, белый
    /// на синем и терракоте); на стекле — `onAccent`, потому что под
    /// стеклом фотография, и нейтральные чернила там нечитаемы.
    /// Это ровно тот случай, который `TodayHeader` уже оплатил:
    /// `Ink.primary` не проходил 12 клеток из 20.
    private var чернила: Color {
        tone == .fasting ? Token.Ink.primary : Token.Ink.onAccent
    }

    private var чернилаПодписи: Color {
        tone == .fasting ? Token.Ink.primary : Token.Ink.onAccent
    }

    private var чернилаПолосы: Color {
        tone.paintsPanel ? Token.Ink.onAccent : Token.Action.primary
    }

    private var чернилаЧипа: Color {
        чип.цветной ? Token.Ink.onAccent : Token.Ink.primary
    }

    private var заливкаЧипа: Color {
        чип.цветной ? Token.Action.primary : Token.Surface.card
    }
}
