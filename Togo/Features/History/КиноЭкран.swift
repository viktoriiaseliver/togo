import SwiftUI

/// Каркас вкладки темы «Кино»: фото под шапкой, надпись капсом, крупный
/// заголовок 36 и одна кнопка «…».
///
/// Решение Виктории 22.10.2026 («перепиши всё под дизайн») и 23.10.2026
/// («Кино. Одна тема»). Состав снят **с кадров**
/// `Дизайн/эталонные-кадры/ios28-кино-22.10/` — `10.png` («История»),
/// `11.png` («Здоровье»), `14.png` («Анализы»), — а не с прозы README:
/// где они расходятся, исполнен кадр, расхождение названо в отчёте.
///
/// ## Шапку и фон рисует НЕ этот файл
///
/// `CinemaHeader`, `CinemaBackdrop` и `.cinemaScreen(экран:)` уже живут
/// в `Togo/Features/Settings/CinemaHeader.swift` (коммит `f06c9a3`,
/// волна 3). Первая редакция этого файла несла **свою** шапку с фото,
/// своей маской и своим гашением титула — то есть вторую копию одного
/// правила, которая разошлась бы молча. Копия снята, вызовы переведены
/// на готовое.
///
/// Здесь остаётся ровно то, чего у соседа нет: **кнопка «…» в строке
/// заголовка** (её нет у настроек, потому что там шапка без меню)
/// и блоки, из которых собраны «История», «Здоровье» и «Анализы»:
/// чип-пилюля, полоса столбиков, блок показания.
///
/// ## Чем этот каркас НЕ занимается
///
/// Он **не прячет навигационную панель**. Соблазн велик — на кадрах
/// её нет, — но `TogoUITests/МедслойДороги` адресует экраны по
/// `app.navigationBars["Здоровье"]`, `["Анализы"]`, `["График"]`
/// и возвращается назад через `app.navigationBars.buttons.firstMatch`.
/// Панель остаётся: `.cinemaScreen` снимает её фон и гасит титул,
/// `navigationTitle` сохраняется ради кнопки «назад» и озвучки.
///
/// **Высота фото — 360, а не 420.** `CinemaBackdrop` берёт
/// `Token.Size.hero`; у вкладки в хендоффе стоит `backdropTab` = 420
/// (`component.backdrop.height.tab`). Расхождение названо, а не
/// исправлено форком: параметр высоты заводится в `CinemaBackdrop`,
/// а он в чужом файле.
struct КиноЭкран<Содержимое: View>: View {

    /// Какой экран спрашивает фон. Через него работает «Фон приложения»
    /// (решение 22.10.2026): режим «вперемешку» раздаёт снимки по ключу.
    let экран: ScreenKey
    /// Строка капсом над заголовком: «ВСЁ · 30 ДНЕЙ»,
    /// «СХЕМА · ЗАПАС · АНАЛИЗЫ».
    var кикер: LocalizedStringKey?
    let заголовок: LocalizedStringKey
    /// Что делает «…». Пункт в меню один — «Настройки»: «Другой день»
    /// живёт на «Сегодня», «Семья» — на вкладке собаки.
    var настройки: () -> Void
    @ViewBuilder var содержимое: Содержимое

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                шапка
                содержимое
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.bottom, Token.Space.s28)
        }
        .scrollBounceBehavior(.basedOnSize)
        // То же, что делает `TGScreen`: карточки внутри спрашивают
        // окружение, на какой поверхности они стоят.
        .themeSurface(.screen)
        .navigationTitle(заголовок)
        .cinemaScreen(экран: экран)
    }

    /// Шапка и «…» в одной строке — как на кадрах 10, 11 и 14.
    ///
    /// `отступы: false`, потому что боковой отступ уже положен колонкой
    /// содержимого; второй дал бы двойной.
    private var шапка: some View {
        HStack(alignment: .center, spacing: Token.Space.s8) {
            CinemaHeader(заголовок, надпись: кикер, экран: экран, отступы: false)
            HeaderMenu(настройки: настройки)
                .tint(Token.Poster.labelOnColor)
                .foregroundStyle(Token.Poster.labelOnColor)
                .стекло(.плавающее, радиус: Token.Size.tapTarget / 2)
        }
    }
}

// MARK: - Величины, которых нет в токенах

/// Величины блока «Metric».
///
/// Сняты с прототипа дословно (`prototypes/Togo-RU.dc.html`, ветка
/// `b.isMetric`): число 48/300, полоса столбиков высотой 48, зазор 3,
/// скругление 3, четырнадцать столбиков. Имён в `DesignTokens/tokens.json`
/// у них сегодня нет ни одного — замер 23.10.2026, `grep -i metric`
/// по `tokens.json` и по `Дизайн/редизайн-ios28/tokens/*` дал ноль.
///
/// **Поэтому они здесь константами с адресом источника, а не спрятаны
/// числом по месту вызова.** Это долг, он назван в отчёте, и хозяин
/// у него — дизайн: завести `component.metric.*` и убрать отсюда.
/// Тот же приём и по той же причине применён в `ReadingPanel`.
nonisolated enum КиноРазмеры {
    /// `font-size:48px;font-weight:300` у числа метрики.
    static let метрика: CGFloat = 48
    /// `height:48px` у полосы столбиков.
    static let полоса: CGFloat = 48
    static let зазорСтолбика: CGFloat = 3
    static let радиусСтолбика: CGFloat = 3
    /// День без записей всё равно виден: иначе пустые дни читаются
    /// как «графика нет», а не как «в эти дни не выходили».
    static let минимумСтолбика: CGFloat = 2
    /// Сколько значений показывает полоса.
    static let днейВПолосе = 14
}

// MARK: - Блоки, из которых собраны экраны

/// Чип-пилюля темы «Кино»: фильтр на «Истории», отметка дозы
/// на «Здоровье».
///
/// **Это не `TGChip`.** Тот — плитка из `TGTile` с подзаголовком, она
/// раскладывается сеткой и переносится. Здесь пилюля одной строки,
/// и выбранная красится акцентом — главной кнопкой, то есть белым
/// в «Кино» и чёрным текстом по ней.
struct КиноЧип: View {
    let подпись: LocalizedStringKey
    var значок: String?
    var выбран: Bool = false
    /// Пусто — чип не нажимается: на кадре `11.png` «✓ 8:00 · дал»
    /// это отметка, а не кнопка.
    var действие: (() -> Void)?

    var body: some View {
        if let действие {
            Button(action: действие) { тело }
                .buttonStyle(.plain)
                .accessibilityAddTraits(выбран ? [.isButton, .isSelected] : .isButton)
        } else {
            тело
        }
    }

    private var тело: some View {
        HStack(spacing: Token.Space.s6) {
            if let значок {
                Image(systemName: значок)
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(подпись)
                .textStyle(AppFont.captionEmphasis, color: чернила)
                .wraps()
        }
        .foregroundStyle(чернила)
        .padding(.horizontal, Token.Space.s16)
        .frame(minHeight: Token.Size.tapTarget)
        .background(заливка, in: Capsule())
    }

    private var чернила: Color {
        выбран ? Token.Ink.onAccent : Token.Ink.primary
    }

    private var заливка: Color {
        выбран ? Token.Action.primary : Token.Action.secondary
    }
}

/// Полоса столбиков.
///
/// **День без записей рисуется чертой, а не пустотой** — так на кадре
/// `10.png`: слева у «Выходов» идут пунктиром дни, когда записей ещё
/// не было. Пустое место читалось бы как «график не нарисовался».
struct КиноСтолбики: View {
    let значения: [Double]
    var цвет: Color = Token.Ink.link
    /// Номера значений, в которые была тревога. Цвет здесь **не
    /// единственный различитель**: рядом с полосой всегда стоит
    /// пояснение словами, и день с кровью ищут по календарю, где
    /// у него своя форма значка.
    var тревожные: Set<Int> = []

    private var потолок: Double {
        max(значения.max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: КиноРазмеры.зазорСтолбика) {
                ForEach(Array(значения.enumerated()), id: \.offset) { номер, значение in
                    RoundedRectangle(cornerRadius: КиноРазмеры.радиусСтолбика,
                                     style: .continuous)
                        .fill(тревожные.contains(номер) ? Token.Status.overdueText : цвет)
                        .frame(height: высота(значение, полная: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: КиноРазмеры.полоса)
        // Голосом столбики не читаются: число стоит рядом крупно,
        // а четырнадцать «столбик, столбик» — это шум, а не сведения.
        .accessibilityHidden(true)
    }

    private func высота(_ значение: Double, полная: CGFloat) -> CGFloat {
        let доля = max(0, min(1, значение / потолок))
        return max(КиноРазмеры.минимумСтолбика, полная * CGFloat(доля))
    }
}

/// Блок «Metric»: шапка капсом, крупное число с единицей, пояснение
/// и полоса столбиков. Кадры `10.png` («Как часто гуляете»)
/// и `14.png` («Т4 общий · окт»).
struct КиноМетрика: View {
    let шапка: LocalizedStringKey
    /// Число уже собрано строкой: округление у веса и у анализа разное,
    /// и решать это здесь нельзя. `16,75 нмоль/л` как `16,8` — потеря
    /// данных, а `4,1 кг` — норма; поэтому форматирует вызывающий.
    let число: String
    var единица: LocalizedStringKey?
    var пояснение: LocalizedStringKey?
    var столбики: [Double] = []
    var цвет: Color = Token.Ink.link

    @Environment(\.dynamicTypeSize) private var размерТекста

    private var стильЧисла: TextStyleToken {
        TextStyleToken(size: КиноРазмеры.метрика,
                       weight: Token.FontWeight.light,
                       color: цвет,
                       monospacedDigits: true,
                       relativeTo: .title2)
    }

    var body: some View {
        TGCard {
            TGSectionHeader(title: шапка)
            числоСЕдиницей
            if let пояснение {
                Text(пояснение).textStyle(AppFont.caption).wraps()
            }
            if !столбики.isEmpty {
                КиноСтолбики(значения: столбики, цвет: цвет)
            }
        }
    }

    /// На доступных кеглях число и единица встают столбиком.
    /// **`ViewThatFits` здесь не применяется** — он запрещён в проекте:
    /// держал в дереве обе раскладки, и озвучка находила два элемента.
    @ViewBuilder
    private var числоСЕдиницей: some View {
        if размерТекста.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(verbatim: число).textStyle(стильЧисла).wraps()
                единицаText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(verbatim: число).textStyle(стильЧисла).wraps()
                единицаText
            }
        }
    }

    @ViewBuilder
    private var единицаText: some View {
        if let единица {
            Text(единица)
                .textStyle(AppFont.bodyEmphasis.color(цвет))
                .wraps()
        }
    }
}
