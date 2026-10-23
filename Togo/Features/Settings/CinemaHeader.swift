import SwiftUI
import UIKit

/// Шапка экрана темы «Кино»: надпись капсом, крупный заголовок 36/−0,9
/// и фотография под ними.
///
/// **Заменяет `posterHeader` на настройках и их подэкранах.** Решение
/// Виктории 22.10.2026 («Кино» ЗАМЕНЯЕТ Graphite, не ложится третьим
/// набором) снимает индиговую полосу плаката: в «Кино» экран чёрный,
/// заголовок крупный, под шапкой лежит фото, а не заливка. `TGPosterHeader`
/// не тронут — он живёт в `Togo/DesignSystem`, у него сорок пять мест
/// вызова в чужих каталогах, и снимать его целиком — работа волн 4–6,
/// а не этой.
///
/// **Где этому файлу место на самом деле.** Рядом с `TGPosterHeader`,
/// в дизайн-системе: это компонент, а не экран. Он лежит здесь потому,
/// что `Togo/DesignSystem/**` на 23.10.2026 правит другая сессия, и два
/// автора в одном каталоге — это чужая незакоммиченная работа в общем
/// дереве. Переезд — отдельным коммитом, когда каталог освободится;
/// тогда же стиль заголовка уедет в `AppFont`, а размеры — на
/// компонентные токены (см. ниже).
///
/// ## Чем это НЕ является
///
/// Это не `TGPoster` (блок состояния «Сегодня») и не панель показания
/// (`ReadingPanel`). У шапки подэкрана нет ни режима, ни тона: «Настройки»
/// не бывают натощак.
///
/// ## Откуда числа
///
/// ```
/// кегль 36, трекинг −0,9    Token.FontSize.titleLarge, Token.FontTracking.titleLarge
///                           ЖИВЫХ ЧИТАТЕЛЕЙ У ОБОИХ БЫЛО НОЛЬ (замер 23.10.2026:
///                           grep titleLarge по *.swift — объявление и комментарий,
///                           ни одного вызова). Эта шапка — первый.
/// прототип говорит 34/−0,02em  Togo-RU.dc.html, `.bigt` в шапке страницы.
///                           Расхождение прозы и токена названо, а не усреднено:
///                           взят ТОКЕН, потому что источник правды по токенам —
///                           DesignTokens/tokens.json, и ступень 36 заведена
///                           в него решением 22.10 (`6821646`).
/// высота фото 360           прототип: `if (S.sub) m = [SUBP[kind], '50% 35%', '360px']`.
///                           То же число лежит в `component.backdrop.height.sub`,
///                           но КОМПОНЕНТНЫЙ токен экрану звать нельзя
///                           (`ComponentTokenScopeTests`, счёт на пределе 10),
///                           поэтому взята равная ступень `Token.Size.hero`.
///                           ОДНО ЧИСЛО, ДВА ИМЕНИ — разойдутся молча,
///                           и это названо здесь, а не спрятано.
/// маска 45 % → 92 %         прототип, `-webkit-mask-image`; в токенах
///                           `component.backdrop.mask` теми же двумя стопами.
/// ```
///
/// **Эталонного кадра у этой шапки НЕТ.** `15.png` («Настройки · фон»)
/// негоден — во весь кадр лавандовая пилюля, экрана под ней не видно
/// (`Дизайн/эталонные-кадры/ios28-кино-22.10/ПОДПИСИ.md`). Состав снят
/// с ГОДНЫХ кадров соседних подэкранов — `13.png` (Питание) и `14.png`
/// (Анализы): надпись капсом, под ней крупный заголовок, за ними фото,
/// гаснущее к низу. Это подэкраны ЧУЖИХ волн, то есть основание
/// косвенное, и выдавать его за «сверено с дизайном» нельзя.
@MainActor
struct CinemaHeader: View {

    /// Название экрана: ключ каталога либо готовое значение.
    ///
    /// Разведено типом по той же причине, что у `TGPosterHeader.Название`:
    /// `Text` со значением типа `String` рисует текст **дословно, мимо
    /// каталога**, и 23.09.2026 это стоило наполовину русского
    /// французского экрана. `.ключ` — для литералов, `.значение` —
    /// для клички, города, имени участника.
    enum Название {
        case ключ(LocalizedStringKey)
        case значение(String)
    }

    let title: Название
    var надпись: LocalizedStringKey?
    /// Чей фон лежит под шапкой. От этого зависит **семья текста**,
    /// а не только вид: на фото честны только `Poster.labelOnColor`
    /// и `Poster.captionOnColor` — они белые в обеих темах, а `Ink.primary`
    /// в светлой теме чёрный и на фотографии пропадает.
    ///
    /// Ключ, а не `Bool`: «есть ли фото» обязан отвечать тот же
    /// `BackgroundStore`, который его и рисует. Два ответа на один
    /// вопрос из разных мест разойдутся молча — у нас это записано
    /// про две копии любого числа.
    var экран: ScreenKey?

    init(_ title: LocalizedStringKey,
         надпись: LocalizedStringKey? = nil,
         экран: ScreenKey? = nil) {
        self.title = .ключ(title)
        self.надпись = надпись
        self.экран = экран
    }

    init(значение: String,
         надпись: LocalizedStringKey? = nil,
         экран: ScreenKey? = nil) {
        self.title = .значение(значение)
        self.надпись = надпись
        self.экран = экран
    }

    @Environment(\.accessibilityReduceTransparency) private var снизитьПрозрачность

    /// Лежит ли под шапкой фотография **сейчас**. Спрашивается у того же
    /// хозяина и с той же оговоркой про сниженную прозрачность, что
    /// в `CinemaBackdrop`: иначе текст оденется в белое там, где фона
    /// уже нет.
    private var наФото: Bool {
        guard !снизитьПрозрачность, let экран else { return false }
        return BackgroundStore.shared.background(for: экран) != nil
    }

    /// Крупный заголовок «Кино». Стиль собран здесь, а не в `AppFont`,
    /// потому что `AppFont` живёт в чужом сегодня каталоге; значения —
    /// токены, а не числа.
    private var стильЗаголовка: TextStyleToken {
        TextStyleToken(size: Token.FontSize.titleLarge,
                       weight: Token.FontWeight.bold,
                       color: наФото ? Token.Poster.labelOnColor : Token.Ink.primary,
                       relativeTo: .largeTitle)
    }

    private var стильНадписи: TextStyleToken {
        AppFont.caps.color(наФото ? Token.Poster.captionOnColor : Token.Ink.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s2) {
            if let надпись {
                Text(надпись)
                    .textStyle(стильНадписи)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .wraps()
            }
            заголовок
                .tracking(Token.FontTracking.titleLarge)
                .wraps()
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, Token.Space.s2)
        .padding(.bottom, Token.Space.s10)
    }

    private var заголовок: Text {
        switch title {
        case .ключ(let ключ): Text(ключ).textStyle(стильЗаголовка)
        case .значение(let строка): Text(строка).textStyle(стильЗаголовка)
        }
    }
}

/// Фотография под шапкой: 360 точек сверху, маска к низу, затемнение.
///
/// **Это первый живой читатель `BackgroundStore.background(for:)`
/// в приложении.** Замер 23.10.2026: вызовов `background(for:` — три,
/// и все три свои (объявление в `BackgroundStore`, два в предпросмотре
/// `BackgroundScreen`). Фото человека показывал **только виджет**
/// (`TogoWidgets/TodayWidget.swift`, два обращения к `BackgroundBridge`),
/// а в самом приложении его не видел никто: фича «Фон приложения»
/// складывала снимки в App Group и не рисовала их ни на одном экране.
/// Это наш класс «механизм без входа», только наоборот — **вход есть,
/// показа нет**.
///
/// **Чего он НЕ показывает и почему.** В режиме «как задумано» (`auto`)
/// `background(for:)` отвечает `nil` — «фон берёт не отсюда», потому что
/// фото раздела кладёт дизайн, а у нас их нет: в прототипе на этом месте
/// стоят плейсхолдеры Unsplash, а хендофф прямо запрещает тащить их
/// в продукт. Тогда экран остаётся чёрным — `#000000` темы «Кино».
/// **Это открытый вопрос к Виктории, а не решение разработки**
/// (`docs/спринт-редизайн-ios28.md`, волна 3, пункт 3: «что показывать,
/// пока не добавили ни одного фото»).
@MainActor
struct CinemaBackdrop: View {
    let экран: ScreenKey

    /// Сниженная прозрачность снимает не блюр (его здесь нет), а само
    /// фото: человек, попросивший систему убрать полупрозрачность,
    /// просил читаемости, а текст поверх фотографии — ровно то,
    /// от чего он отказывается.
    @Environment(\.accessibilityReduceTransparency) private var снизитьПрозрачность

    private var store: BackgroundStore { .shared }

    var body: some View {
        ZStack(alignment: .top) {
            Token.Surface.screen
            if !снизитьПрозрачность,
               let фото = store.background(for: экран),
               let картинка = UIImage(data: фото.data) {
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: Token.Size.hero)
                    .clipped()
                    .mask { маска }
                    .overlay { затемнение }
                    // Фото — оформление. Голосом его читать нечем,
                    // а подпись к нему была бы выдумкой: мы не знаем,
                    // что на фотографии человека.
                    .accessibilityHidden(true)
            }
        }
    }

    /// Фото гаснет к низу: сплошное до 45 % высоты, прозрачное к 92 %.
    /// Два стопа — те же, что в прототипе и в `component.backdrop.mask`.
    ///
    /// Цвет берётся из `Token.Ink.primary` не ради цвета: маску читает
    /// только альфа-канал, а литеральный `.black` слой вида не пускает
    /// (`DesignLiteralTests`, «цветов строго ноль»).
    private var маска: some View {
        LinearGradient(stops: [
            .init(color: Token.Ink.primary, location: 0.45),
            .init(color: Token.Ink.primary.opacity(0), location: 0.92),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Затемнение сверху и к низу. Без него заголовок ложится на светлое
    /// место фотографии и пропадает — тот же `--bd-scrim`, которым
    /// пользуется панель показания.
    private var затемнение: some View {
        LinearGradient(
            colors: [Token.Surface.scrim.opacity(0.85),
                     Token.Surface.scrim.opacity(0.25),
                     Token.Surface.scrim],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {

    /// Надеть на экран тему «Кино»: чёрный фон, прозрачная панель
    /// навигации и фотография под шапкой.
    ///
    /// **Заголовок в панели навигации гасится, а `navigationTitle`
    /// остаётся.** Снять его нельзя: по нему подписана кнопка «назад»
    /// у дочерних экранов и им экран называет себя VoiceOver. Поэтому
    /// гасится ПОКАЗ, и гасится он **непустым** видом — замер
    /// `TGPosterHeader` 07.10.2026: `EmptyView()` в `ToolbarItem` SwiftUI
    /// считает отсутствием пункта, подмены не происходит вовсе, и на
    /// живом кадре название экрана выходило ДВАЖДЫ. Подменыш прячется
    /// от озвучки — иначе `Color.clear` наследует ярлык у `navigationTitle`
    /// и VoiceOver читает название дважды.
    ///
    /// **Фон панели скрыт, а не перекрашен:** в кадрах 13 и 14 фотография
    /// уходит под статус-бар, и материал системной панели её бы срезал.
    ///
    /// - Parameter экран: чьё фото показывать. `nil` — экран без фото,
    ///   просто чёрный: так сделаны подэкраны на каркасе `TGScreen`,
    ///   который рисует свою непрозрачную подложку и фотографию под собой
    ///   не пропустит. Переделка каркаса — чужой файл
    ///   (`Togo/DesignSystem/Components/TGScaffolds.swift`), и она названа
    ///   в отчёте, а не сделана молча.
    func cinemaScreen(экран: ScreenKey? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: Token.Size.hairline, height: Token.Size.hairline)
                        .accessibilityHidden(true)
                }
            }
            .background(alignment: .top) {
                Group {
                    if let экран {
                        CinemaBackdrop(экран: экран)
                    } else {
                        Token.Surface.screen
                    }
                }
                .ignoresSafeArea()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#if DEBUG
#Preview("Шапка «Кино»") {
    NavigationStack {
        List {
            Section {
                CinemaHeader("Настройки", надпись: "язык, уведомления, перенос")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                TGListRow(title: "Фон приложения", value: "как задумано",
                          systemImage: "photo.on.rectangle.angled")
            } header: {
                Text("как выглядит")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Настройки")
        .cinemaScreen(экран: .sub("settings"))
    }
}
#endif
