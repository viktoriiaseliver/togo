import SwiftUI
import SwiftData

/// Режим прогулки. Таймер идёт, а человек по ходу отмечает, что собака
/// сделала — одной рукой, не думая и не глядя.
///
/// Правила экрана:
/// * самая частая отметка — большая охряная кнопка, остальные плитками;
/// * отметка ставится мгновенно и её видно — время и отклик;
/// * промахнуться легко, поэтому последнюю отметку можно снять одним тапом;
/// * «Закончить» — снизу и не охряная: за прогулку её жмут один раз,
///   а отмечают десять.
struct WalkModeScreen: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Системный кегль. Читается, а не задаётся: `\.dynamicTypeSize`
    /// приезжает сюда от настройки **процесса**, и на этом же месте
    /// его подменяет аргумент запуска `-UIPreferredContentSizeCategoryName`
    /// у прогона.
    @Environment(\.dynamicTypeSize) private var размерТекста

    @State private var now = Date()
    @State private var summary: ActiveSession?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: ActiveSession? { appState.session }

    /// Есть ли что разбирать в итоге прогулки.
    ///
    /// Правило из ФИНАЛа, раздел 3 «Шторки и итоги»: **«Итог прогулки —
    /// только если был срыв, инцидент или заметка».** Прогулка, где
    /// ничего не случилось, не задаёт вопросов: человек только что
    /// вернулся с холода, и показывать ему шторку ради строки «отметок
    /// не было» — значит спрашивать, не имея вопроса.
    ///
    /// **Правило относится к ПРОГУЛКЕ, а не к выходу**, и это не
    /// буквоедство: в словаре продукта это разные вещи —
    /// `ActiveSession.Kind.outing` = «Выход», `.walk` = «Прогулка».
    /// Поставь тот же гейт на «Как сходил?» (`TodayScreen.endOuting`) —
    /// и главный вопрос короткого пути исчезнет: отметки в сессию кладут
    /// только режим прогулки (`mark(_:)` ниже) и локскран
    /// (`ActiveSession:205`, и тот лишь мочу и стул), так что на коротком
    /// выходе срыва, заметки и инцидента быть НЕ МОЖЕТ — их нечем
    /// поставить.
    ///
    /// > Правка собирается из двух верных половин: правило верное,
    /// > место неверное. Проверяется не чтением правила, а перечислением
    /// > того, кто вообще может создать его предмет.
    ///
    /// Моча и стул сюда не входят намеренно: они записываются сами
    /// и уточнений не просят. Спрашивать здесь не о чем.
    private func естьЧтоРазбирать(_ сессия: ActiveSession) -> Bool {
        сессия.reactions > 0
            || сессия.count(of: .incident) > 0
            || сессия.count(of: .note) > 0
    }

    var body: some View {
        Group {
            if let summary {
                WalkSummarySheet(session: summary, dog: dog) { dismiss() }
            } else if let session {
                walkSheet(session)
            } else {
                startSheet
            }
        }
        .presentationDetents([.large])
        .usageScreen(.walk)
        .onReceive(tick) { now = $0 }
    }

    // MARK: Начало

    private var startSheet: some View {
        TGSheet(
            title: "Прогулка",
            subtitle: "таймер пойдёт сразу — отмечать можно на ходу"
        ) {
            TGCard {
                Text("Что можно отметить по дороге").textStyle(AppFont.cardTitle)
                // **НЕ `allCases`, и это починка от 28.10.2026.**
                // Список обещал все восемь случаев `Mark.Kind`,
                // а кнопок на экране прогулки шесть: «Попил»
                // и «Занятие» человек читал в обещании и не находил.
                //
                // ```
                // обещано  allCases                        8
                // дано     .urine .stool + ряды :413, :453 6
                // разница  .water «Попил» — кнопки НЕ БЫЛО никогда,
                //                  и `WalkRecorder.apply` уводит его
                //                  в `default: break`
                //          .training «Занятие» — кнопку сняли, а довод
                //                  («вход лучше есть в шторке „Ещё“»)
                //                  на сегодня уже неверен: ту строку
                //                  сняли коммитом 9b2777f, входов ноль
                // ```
                //
                // Чинится ОСЬЮ, а не вычёркиванием двух имён: обещание
                // и кнопки берут один список `предлагаемые`. Снимут
                // кнопку — обещание уедет следом само. `allCases`
                // отвечал на вопрос «что умеет модель», а карточка
                // спрашивает «что даст нажать этот экран».
                ForEach(Self.предлагаемые, id: \.self) { kind in
                    HStack(spacing: Token.Space.s10) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: Token.Size.iconMd, weight: .medium))
                            .foregroundStyle(Token.Ink.silhouette)
                            .frame(width: Token.Space.s24)
                            .accessibilityHidden(true)
                        Text(kind.title).textStyle(AppFont.body)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 34)
                }
                TGExplainer(text: "Время каждой отметки запишется само. Телефон можно убрать в карман — секунды считаются от начала, а не тикают на экране.", памятка: "прогулка.времяСамо")
            }
        } footer: {
            TGButton(title: "Пошли", systemImage: "figure.walk") { start() }
        }
    }

    private func start() {
        appState.startWalk(by: appState.currentUserName)
        if let dog {
            LiveActivityController.startWalk(dogName: dog.name,  // кличка-в-слот: вход живой активности кормит и именительный ярлык, и винительные подписи — падеж знает слот
                                             by: appState.currentUserName,
                                             at: Date(),
                                             кобель: dog.sex == .male)
        }
        Haptics.success()
    }

    // MARK: Прогулка идёт

    /// Экран прогулки по кадру 08 хендоффа `design_handoff_togo_ios28`.
    ///
    /// Сверху вниз, как на кадре: строка «с 17:55» → **тост сверху** →
    /// фото собаки в круге на фоне-фотографии → таймер крупно и подпись
    /// «пока без отметок» → кнопки. Таб-бара на кадре нет вовсе: режим
    /// занимает экран целиком.
    ///
    /// **Порядок кнопок взят с кадра, а не из README.** README говорит
    /// «„Пописал“ / „Стул“ — сплошные `surface-raised`»; на кадре
    /// «Пописал» **белая во всю ширину** (главная кнопка темы «Кино»),
    /// а `surface-raised` только «Стул». Мерено по кадру.
    ///
    /// Отметки закреплены, список прокручивается. Было наоборот: сетка
    /// уезжала вверх вместе с прокруткой, а «Пауза» оставалась внизу —
    /// самые частые кнопки убегали от пальца. На морозе одной рукой это
    /// просто не работает.
    private func walkSheet(_ session: ActiveSession) -> some View {
        VStack(spacing: 0) {
            header(session)

            if session.marks.isEmpty {
                // **Пока отметок нет, середина стояла БЕЗ прокрутки** —
                // два `Spacer` вокруг портрета и таймера. На обычном
                // кегле это верно: портрет 0,46 ширины и таймер
                // помещаются с запасом. На `AccessibilityXXXL`
                // не помещаются, а деться им некуда: `Spacer` схлопнется
                // в ноль и упрётся, после чего сжимать начнёт
                // САМ ТАЙМЕР и низ под ним.
                //
                // Ветка с отметками уже прокручивается — там `ScrollView`
                // стоит с рождения. То есть дефект виден только
                // в начале прогулки: ровно тогда, когда человек
                // на улице и смотрит на экран первый раз.
                // Раскладка выбирается явным `if` по той же причине,
                // что и в низу «Сегодня»: `ViewThatFits` запрещён.
                //
                // **Прокрутка включается только на крупном кегле, и это
                // не осторожность, а сохранение обычного вида:**
                // в `ScrollView` содержимое прижимается к верху,
                // а здесь портрет с таймером стоят ПО ЦЕНТРУ — их
                // центрируют как раз эти два `Spacer`. Завернуть ветку
                // целиком значило бы сдвинуть вверх экран, который
                // сегодня правильный.
                if размерТекста.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 0) {
                            кольцо(session)
                            таймер(session)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Spacer(minLength: 0)
                    кольцо(session)
                    таймер(session)
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    VStack(spacing: Token.Space.s16) {
                        кольцо(session)
                        таймер(session)
                        marksList(session)
                            .padding(.horizontal, Token.Spacing.screenPadding)
                    }
                    .padding(.bottom, Token.Space.s10)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            кнопки(session)
        }
        .background(фон)
        // **Тост — СВЕРХУ.** Хендофф: «Тост — сверху (740 pt от низа
        // в кадре 874), не перекрывает кнопки».
        //
        // И вторая половина, которой в хендоффе нет: `UndoToastView`
        // висит **только** на `RootView:75`, снизу у `TabView`. Режим
        // прогулки показывается шторкой — значит до сегодня тост
        // от «Пописал» рисовался ПОД шторкой, то есть человек, отметивший
        // на улице, не видел подтверждения вовсе. Своя плашка здесь
        // не строится: тот же `UndoToastView`, просто сверху.
        .overlay(alignment: .top) {
            UndoToastView()
                .padding(.top, Token.Space.s8)
        }
    }

    /// Фон — фотография собаки, растворяющаяся в чёрный.
    ///
    /// На кадре маска не доходит до низа: нижняя треть чёрная, иначе
    /// под белой кнопкой «Пописал» просвечивал бы мех.
    ///
    /// # ~~«Токена `backdrop.height.walk` = 520 у нас нет»~~ — ЛОЖНО
    ///
    /// Замер 26.10.2026, точечно по генерату:
    ///
    /// ```
    /// Token.Size.backdropWalk                   CGFloat = 520   ЕСТЬ
    /// Token.Component.Backdrop.Height.walk      CGFloat = 520   ЕСТЬ
    /// контроль: вся четвёрка на месте            sub 360 · tab 420
    ///                                            today 640 · walk 520
    /// отрицательный контроль (`backdropТакогоНет`)        0, rc=1
    /// ```
    ///
    /// Токенов не один, а **два**, и строка отрицала оба. Утверждение
    /// было верным когда-то и **поменяло знак в момент, когда токен
    /// завели** — наш класс «условие, привязанное к наличию
    /// инструмента»: из описания дыры оно стало описанием несуществующей
    /// дыры, и произошло это в момент успеха, когда плохих новостей
    /// никто не ждёт.
    ///
    /// > **Ложное утверждение в коде опаснее отсутствующего:** его
    /// > не перепроверяют, на него ссылаются. Эту строку уже прочли
    /// > как задел работы.
    ///
    /// **Высоту при этом НЕ перевожу на токен, и это не недоделка.**
    /// Доля вместо точек — решение с доводом, который замер
    /// подтверждает: 520 из кадра 874 это 0,59, и на SE точки соврали
    /// бы. Токен даёт 520 pt безусловно. Что из двух верно — вопрос
    /// к дизайну, а не к коду, и он открыт. Снято только ложное
    /// отрицание, а поведение оставлено как было.
    ///
    /// # Затемнение: было три стопа, стало восемь
    ///
    /// Последняя урезанная версия слоя в проекте
    /// (`Token.Surface.scrim` → `Color.clear` → `Token.Surface.screen`,
    /// три цвета в ровных третях) заменена компонентом
    /// `TGBackdropScrim` — восемь стопов `Token.Component.Backdrop.scrim`.
    /// Разбор и происхождение обхода — в голове компонента.
    ///
    /// **Вид меняется, и меняется в сторону, которую требует строка
    /// выше.** Замер альфы по позициям доли фото:
    ///
    /// ```
    ///  поз.   три стопа   восемь    что там лежит
    ///  0,00        55 %     70 %
    ///  0,14        40 %     45 %
    ///  0,30        22 %     15 %    ← ОКНО ФОТО: плато 30–38 %,
    ///  0,38        13 %     15 %      самое светлое место кадра,
    ///                                 где собаку видно. В трёх
    ///                                 стопах плато нет вовсе
    ///  0,55        10 %     75 %
    ///  0,70        40 %     97 %
    ///  0,76        52 %    100 %    ← «нижняя треть чёрная»
    ///  0,90        80 %    100 %
    /// ```
    ///
    /// То есть требование «под белой кнопкой не просвечивает мех»
    /// три стопа **не исполняли**: на 76 % высоты фото они давали 52 %,
    /// на 90 % — 80 %, и мех просвечивал ровно там, где комментарий
    /// обещал чёрное. Восемь стопов дают сплошное с 76 %. Правка
    /// закрывает и расхождение с макетом, и собственное обещание
    /// этого файла.
    ///
    /// Проценты — доли **высоты фото**, а не экрана: слой лежит
    /// `.overlay` на рамке снимка, а хендофф задаёт стопы в процентах
    /// от высоты подложки. Это сходится, и потому замена геометрически
    /// дословна, несмотря на то что высота здесь доля, а не 520 pt.
    ///
    /// **Кадра на эту правку нет** — стенд у `projects-4e`. Вид
    /// меняется, значит приёмка кадром обязательна, и до неё правка
    /// принята по числам, а не по картинке.
    @ViewBuilder
    private var фон: some View {
        ZStack(alignment: .top) {
            Token.Surface.screen
            if let photo = dog?.photo, let image = КэшСнимков.картинка(photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical) { высота, _ in
                        высота * Self.доляФона
                    }
                    .clipped()
                    .overlay { TGBackdropScrim() }
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    /// Какую долю высоты занимает фото. Доля, а не точки: 520 из кадра
    /// 874 — это 0,59 экрана, и на SE точки соврали бы.
    private static let доляФона: CGFloat = 0.59

    /// Кольцо времени с портретом внутри.
    ///
    /// Долю кольца считает `WalkRing`, а секунды сюда приезжают от того
    /// же `tick`, что уже крутит экран, — своего таймера у кольца нет:
    /// два тикающих источника на одном экране разошлись бы, и разошлись
    /// бы молча.
    private func кольцо(_ session: ActiveSession) -> some View {
        WalkRing(dog: dog,
                 прошло: session.duration(at: now),
                 наПаузе: session.isPaused)
    }

    /// Таймер и что под ним.
    ///
    /// «пока без отметок» — пустое состояние с кадра: до первой отметки
    /// сводка `tally` и так говорит ровно это, поэтому строка одна,
    /// а не две.
    private func таймер(_ session: ActiveSession) -> some View {
        VStack(spacing: Token.Space.s4) {
            TGStopwatch(session: session, now: now, style: Self.стильТаймера)
            Text(session.isPaused
                 ? String(localized: "на паузе · \(session.tally)")
                 : session.tally)
                .textStyle(AppFont.caption)
                .wraps()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Token.Spacing.screenPadding)
    }

    /// Крупная цифра прогулки: SF Rounded, светлое начертание.
    ///
    /// Хендофф задаёт 76 (`type.walkTimer`), такой ступени у нас нет —
    /// `Token.FontSize.hero` = 56 самая крупная. Берём её, и 76 назван
    /// в отчёте как недостающий токен. Выдумывать число нельзя: оно
    /// уедет дизайнеру тем же именем и разойдётся с макетом молча.
    private static var стильТаймера: TextStyleToken {
        TextStyleToken(size: Token.FontSize.hero,
                       weight: Token.FontWeight.light,
                       color: Token.Ink.primary,
                       rounded: true,
                       monospacedDigits: true,
                       relativeTo: .largeTitle)
    }

    /// Строка «с 17:55» и возврат на главный экран.
    ///
    /// «Свернуть» оставлена, хотя на кадре её нет: у нас прогулка —
    /// шторка, и без неё единственный выход остаётся смахиванием.
    /// Когда показ переедет на `fullScreenCover` (как на кадре),
    /// кнопка станет единственным выходом, а не запасным.
    private func header(_ session: ActiveSession) -> some View {
        HStack(alignment: .center, spacing: Token.Space.s8) {
            Circle()
                .fill(session.isPaused ? Token.Ink.secondary : Token.Action.primary)
                .frame(width: Token.Size.handleH, height: Token.Size.handleH)
                .accessibilityHidden(true)
            Text("с \(Fmt.clock(session.startedAt))")
                .textStyle(AppFont.micro)
            Spacer(minLength: 0)
            TGCloseButton(title: "Свернуть") { dismiss() }
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, Token.Space.s8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Прогулка с \(Fmt.clock(session.startedAt))")
    }

    /// Пауза обратима и ничего не записывает — ей хватает камня.
    /// Горчицей её красить нельзя: этот цвет занят окном натощак
    /// и больше нигде не появляется.
    ///
    /// `fullWidth` по раскладке: в строке кнопка держит свою ширину,
    /// столбцом — тянется во всю, иначе столбец из узкой кнопки
    /// и широкого слайдера читается как две разные вещи.
    private func кнопкаПаузы(_ session: ActiveSession) -> some View {
        TGButton(title: session.isPaused ? "Продолжить" : "Пауза",
                 variant: .secondary, size: .medium,
                 systemImage: session.isPaused ? "play.fill" : "pause.fill",
                 fullWidth: размерТекста.isAccessibilitySize) {
            togglePause()
        }
    }

    /// Кнопки по кадру 08: две широких, ряд плиток и низ со слайдером.
    ///
    /// **«Закончить» заменена слайдером «Домой»** — хендофф, раздел
    /// «На улице». Прогулку заканчивают один раз, а отмечают десять,
    /// и случайный тап по «Закончить» стоил записи; слайдер промахом
    /// не срабатывает.
    // MARK: Что этот экран даёт отметить — ОДИН список на два читателя

    /// Главная кнопка экрана и вторая под ней.
    ///
    /// Именами, а не индексами в массив: у каждой свой тон и своя
    /// высота, и `предлагаемые[0]` читалось бы как «порядок важен»,
    /// а важен он только в обещании.
    private static let главная: ActiveSession.Mark.Kind = .urine
    private static let вторая: ActiveSession.Mark.Kind = .stool

    /// Ряд событий и отдельный ряд срыва — теми же списками, какими
    /// их получает `плитки(_:)`.
    private static let рядСобытий: [ActiveSession.Mark.Kind] = [.incident, .treat, .note]
    private static let рядСрыва: [ActiveSession.Mark.Kind] = [.reaction]

    /// Обещание на шторке начала. **Читается там, где раньше стоял
    /// `allCases`** — и в этом вся починка: список обещанного теперь
    /// СОБРАН ИЗ КНОПОК, а не из перечисления модели.
    ///
    /// Два вопроса звучат одинаково и отвечают разное:
    ///
    /// ```
    /// Mark.Kind.allCases   что УМЕЕТ МОДЕЛЬ        8 случаев
    /// предлагаемые         что ДАСТ НАЖАТЬ ЭКРАН   6 случаев
    /// ```
    ///
    /// Разошлись они молча и жили так до отзыва: кнопку сняли, а
    /// обещание осталось — его никто не правил, потому что оно
    /// не называло имён.
    static var предлагаемые: [ActiveSession.Mark.Kind] {
        [главная, вторая] + рядСобытий + рядСрыва
    }

    private func кнопки(_ session: ActiveSession) -> some View {
        VStack(spacing: Token.Space.s10) {
            if session.isPaused {
                TGBanner(tone: .waiting, title: "Прогулка на паузе",
                         subtitle: "Время не идёт. Нажми «Продолжить», когда пойдёте дальше.",
                         systemImage: "pause.circle")
            }

            VStack(spacing: Token.Space.s10) {
                // Самое частое — главной кнопкой экрана. В теме «Кино»
                // она белая; роль та же, что у `Button.Primary`.
                //
                // **У кобеля мочи на экране нет** — решение Виктории
                // 29.10.2026: «поход на улицу для кобеля = туалет,
                // и незачем указывать мочу». Он метит на каждой прогулке,
                // и прогулка сама считается мочой (`ToiletClock`). Главной
                // становится единственная отметка, которая у него
                // что-то сообщает, — стул.
                if dog?.sex == .male {
                    широкая(Self.вторая, на: .accent, высота: Token.Size.capsule)
                } else {
                    широкая(Self.главная, на: .accent, высота: Token.Size.capsule)
                    широкая(Self.вторая, на: .quiet, высота: Token.Size.controlL)
                }

                // Инцидент первым и красным — порядок с кадра и из
                // шторки «Записать»: то, о чём жалеют, что не записали.
                плитки(Self.рядСобытий)

                // **На эталоне v10 (`49-screens.jpg`) здесь нет ни срыва,
                // ни занятия. Убрано одно из двух, и это замер, а не
                // полумера.**
                //
                // Прежняя редакция этого комментария защищала ОБЕ кнопки
                // одним доводом («механизм без входа»). Довод верен для
                // срыва и ЛОЖЕН для занятия — проверено пути́, а не
                // прочтением комментария:
                //
                // ```
                // .reaction  Mark.Kind.reaction создаётся ТОЛЬКО здесь.
                //            На нём стоят: карточка «на что сорвался»
                //            + «как близко» (:530), счётчик «N срывов»
                //            (:604) и дописывание reactionTrigger/
                //            reactionDistance в save() (:655). Контроль:
                //            IncidentKind.reaction — ДРУГОЙ случай
                //            другого перечисления, он садится на событие
                //            kind == .incident и под `event.kind ==
                //            .reaction` в save() не попадает. Входа
                //            второго НЕТ → кнопка ОСТАЁТСЯ
                // .training  Mark.Kind.training пишет голую запись ленты
                //            без занятия. Настоящее занятие заводит
                //            TrainingSessionScreen:387 (.record(.training)
                //            + trainingSessionID), а открывают его
                //            из шторки «Ещё» — TodayRouter:55, и на
                //            эталоне `06-screens.jpg` плитка «Занятие»
                //            в «Ещё» ЕСТЬ. Вход второй есть и он лучше
                //            → кнопка УБРАНА
                // ```
                //
                // > **Чужое утверждение о собственном коде проверяют
                // > реже всего.** Комментарий стоял рядом с кнопками
                // > и звучал как замер; замером он был наполовину.
                //
                // Срыв остаётся рядом один и во всю ширину — не из-за
                // раскладки, а потому что он и есть отдельная вещь:
                // у реактивной собаки их пять за выход, и на них стоит
                // работа с порогом.
                плитки(Self.рядСрыва)
            }
            .disabled(session.isPaused)
            .opacity(session.isPaused ? 0.4 : 1)

            // Два органа в строку — и на крупном кегле они туда
            // не помещаются ПО УСТРОЙСТВУ. Кадр 25.10.2026
            // (`06-выгул-ax5.png`, `AccessibilityXXXL`): «Пауза»
            // переносится на «Пау / за» и **вылезает за капсулу
            // сверху и снизу**, потому что ширины у кнопки остаётся
            // треть ряда, а слайдер рядом держит свою.
            //
            // Раскладка выбирается явным `if`, а не `ViewThatFits`:
            // он в проекте запрещён — держит в дереве обе ветки,
            // и озвучка находит два «Домой». Форма взята у соседа,
            // который это уже решил, — `TodayBottom:53`.
            Group {
                if размерТекста.isAccessibilitySize {
                    VStack(spacing: Token.Space.s10) {
                        кнопкаПаузы(session)
                        WalkHomeSlider { finish() }
                    }
                } else {
                    HStack(spacing: Token.Space.s10) {
                        кнопкаПаузы(session)
                        WalkHomeSlider { finish() }
                    }
                }
            }
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, Token.Space.s10)
        .padding(.bottom, Token.Space.s8)
    }

    /// Широкая кнопка отметки: значок и подпись в строку, счётчик — хвостом.
    ///
    /// Счётчик приписывается к подписи («Стул · 2»), как в прототипе,
    /// а не стоит второй строкой: на кадре кнопка в одну строку, и вторая
    /// строка меняла бы её высоту от числа отметок.
    private func широкая(_ kind: ActiveSession.Mark.Kind,
                         на заливка: MarkFill, высота: CGFloat) -> some View {
        let count = session?.count(of: kind) ?? 0
        return Button { mark(kind) } label: {
            HStack(spacing: Token.Space.s8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.medium))
                    .accessibilityHidden(true)
                // Цвет ВМЕСТО стилевого, а не поверх: `AppFont` несёт свой
                // `color` и красит сам `Text`, то есть побеждает
                // `foregroundStyle` предка.
                Text(count > 0 ? kind.title + " · \(count)" : kind.title)
                    .textStyle(AppFont.cardTitle, color: заливка.label)
            }
            .foregroundStyle(заливка.label)
            .frame(maxWidth: .infinity, minHeight: высота)
            .background(заливка.color,
                        in: RoundedRectangle(cornerRadius: Token.Radius.capsule, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(count > 0 ? "отмечено \(count)" : "не отмечено")
        // **Признак кнопки приходится ставить руками, и это замер.**
        // `.accessibilityElement(children: .ignore)` заводит НОВЫЙ
        // элемент вместо поддерева — признаки `Button` у него
        // не наследуются, хотя снаружи это `Button` и нажимается
        // он как кнопка. Озвучка читала «Пописал, не отмечено»
        // без слова «кнопка»: человеку с VoiceOver нечем было узнать,
        // что по ней жмут.
        //
        // Замер 25.10.2026: `app.buttons["отметка-urine"]` не находит
        // ничего при открытом режиме выгула (15 с, оба кегля),
        // а `descendants(matching: .any)` находит — то есть в дереве
        // элемент лежит как `Other`. На этой же строке красен
        // `DynamicTypeScreenshotTests.testXL13РежимВыгула`
        // (прогон 25.10, 1 тест, 1 отказ) — и красен он был
        // ДО этой правки, своим прогоном на `8822698`.
        //
        // Слайдер «Домой» рядом признак ставит явно
        // (`WalkControls.swift`) — там это заметили, здесь нет.
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(Self.имяОтметки(kind))
    }

    /// Имя отметки для прогона. Человеку не видно, переводу не подлежит.
    ///
    /// **Заведено замером 24.10.2026, и предмет у него не косметический.**
    /// Пока прогулка идёт, низ «Сегодня» показывает кнопку с подписью
    /// «Пописал» (`TodayBottom`) — и она остаётся в дереве под шторкой
    /// режима выгула. То есть на экране ДВЕ кнопки «Пописал», и
    /// `app.buttons["Пописал"].firstMatch` брал ту, что под шторкой:
    ///
    /// ```
    /// низ «Сегодня», под шторкой   {{171, 725}, {143, 60}}  ← брался
    /// шторка выгула, «Пописал»     {{18,  532}, {366, 60}}  ← предмет
    /// первый тап   синтезирован в центр закрытой кнопки (242, 755) —
    ///              а там, в шторке, лежит плитка «Сорвался»
    /// второй тап   «Computed hit point {-1, -1} after scrolling
    ///              to visible» — не ушёл никуда
    /// ```
    ///
    /// Обе записанные версии промаха («попал в соседнюю плитку»
    /// и «hit point {-1,-1}») описывали ОДИН элемент и два его тапа.
    /// Пересборка ряда по `session.marks.isEmpty` тут ни при чём:
    /// взятая кнопка в шторке вообще не лежит.
    ///
    /// > **Совпадение имён — не «кнопки нет», а худшее: кнопка есть,
    /// > и она чужая.** Различает только идентификатор — ровно так же
    /// > это уже лечили у «Ещё» (`ScreenshotTests.test04Занятие`).
    static func имяОтметки(_ kind: ActiveSession.Mark.Kind) -> String {
        "отметка-\(kind.rawValue)"
    }

    /// Ряд плиток. Инцидент красный — единственный, кто красится.
    ///
    /// **На крупном кегле ряд превращается в столбец.** Кадр
    /// `06-выгул-ax5` от 25.10.2026: три плитки в строку дали
    /// «Ин… · Лак… · Зам…» — от трёх слов осталось по три буквы,
    /// и «Инцидент» с «Лакомством» на `AccessibilityXXXL` различаются
    /// только длиной огрызка. Это не теснота оформления: человек
    /// на улице не может прочитать, что он отмечает.
    ///
    /// Ширины тут не хватает ПО УСТРОЙСТВУ — треть экрана минус
    /// значок на слово из девяти букв кеглем под пятьдесят. Поэтому
    /// столбцом, той же формой, что у соседей (`TodayBottom:53`,
    /// и ряд «Пауза + Домой» выше в этом файле).
    @ViewBuilder
    private func плитки(_ kinds: [ActiveSession.Mark.Kind]) -> some View {
        if размерТекста.isAccessibilitySize {
            VStack(spacing: Token.Space.s10) {
                плиткиСодержимое(kinds)
            }
        } else {
            HStack(spacing: Token.Space.s10) {
                плиткиСодержимое(kinds)
            }
        }
    }

    @ViewBuilder
    private func плиткиСодержимое(_ kinds: [ActiveSession.Mark.Kind]) -> some View {
        Group {
            ForEach(kinds, id: \.self) { kind in
                let count = session?.count(of: kind) ?? 0
                Button { mark(kind) } label: {
                    // `TGTile` вместо своего прямоугольника: при
                    // `isSelected` и `tone: .alarm` компонент даёт ровно
                    // `Token.Status.overdueBg`, иначе `Token.Surface.sunken`,
                    // плюс `.themeSurface`, которого у ручной копии не было.
                    TGTile(isSelected: count > 0,
                           tone: kind == .incident ? .alarm : .neutral,
                           minHeight: Token.Size.tapTarget) {
                        HStack(spacing: Token.Space.s6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: Token.Size.iconSm,
                                              weight: Token.FontWeight.medium))
                                .accessibilityHidden(true)
                            Text(count > 0 ? kind.title + " · \(count)" : kind.title)
                                .textStyle(AppFont.captionEmphasis, color: подпись(kind))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(подпись(kind))
                        .padding(.horizontal, Token.Space.s8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(kind.title)
                .accessibilityValue(count > 0 ? "отмечено \(count)" : "не отмечено")
                // Та же правка, что у широкой отметки выше, и по той же
                // измеренной причине: `children: .ignore` не наследует
                // признак `Button`. Плитки «Инцидент · Лакомство ·
                // Замечание · Сорвался» озвучка читала текстом.
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(Self.имяОтметки(kind))
            }
        }
    }

    private func подпись(_ kind: ActiveSession.Mark.Kind) -> Color {
        kind == .incident ? Token.Status.overdueText : Token.Ink.primary
    }

    private func marksList(_ session: ActiveSession) -> some View {
        TGCard(spacing: 0) {
            HStack {
                TGSectionHeader(title: "отмечено")
                Button("Убрать последнюю") { undoMark() }
                    .textStyle(AppFont.captionEmphasis.color(Token.Status.overdueText))
            }
            ForEach(session.marks.reversed()) { entry in
                HStack(spacing: Token.Space.s12) {
                    Text(Fmt.clock(entry.at))
                        .textStyle(AppFont.numeric(13, weight: .medium))
                        .fixedSize()
                        .frame(minWidth: 44, alignment: .leading)
                    Image(systemName: entry.kind.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Token.Ink.silhouette)
                        .accessibilityHidden(true)
                    Text(entry.kind.title).textStyle(AppFont.body)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 38)
            }
        }
    }

    // MARK: Действия

    private func mark(_ kind: ActiveSession.Mark.Kind) {
        // Неповторяемое переключается, а не копится. Свойство `isRepeatable`
        // было описано в модели и не использовалось нигде: занятие можно
        // было отметить пять раз подряд, и в ленту уезжали пять записей.
        if !kind.isRepeatable, (appState.session?.count(of: kind) ?? 0) > 0 {
            appState.removeMarks(of: kind)
            Haptics.warning()
            appState.showUndo(String(localized: "Отметка убрана · \(kind.title)"))
            return
        }

        appState.mark(kind)
        Haptics.tap()
        let count = appState.session?.count(of: kind) ?? 1
        appState.showUndo(count > 1
                          ? String(localized: "\(kind.title) · \(count)-й раз")
                          : String(localized: "Отмечено · \(kind.title)"))
    }

    private func undoMark() {
        if let removed = appState.undoLastMark() {
            Haptics.warning()
            appState.showUndo(String(localized: "Отметка убрана · \(removed.kind.title)"))
        }
    }

    private func togglePause() {
        guard let session else { return }
        if session.isPaused {
            appState.resumeSession()
            // Начало сдвигаем на всё простоянное: на блокировке должно
            // быть то же время, что и здесь.
            if let resumed = appState.session, let dog {
                LiveActivityController.resumeWalk(
                    dogName: dog.name, by: resumed.startedBy,  // кличка-в-слот: вход живой активности кормит и именительный ярлык, и винительные подписи — падеж знает слот
                    effectiveStart: Date().addingTimeInterval(-resumed.duration()),
                    tally: resumed.marks.isEmpty ? nil : resumed.tally,
                    кобель: dog.sex == .male
                )
            }
            Haptics.tap()
        } else {
            appState.pauseSession()
            Task { await LiveActivityController.pauseWalk() }
            Haptics.warning()
        }
    }

    /// Записи создаются в конце, а не по ходу: иначе случайный тап уже
    /// уехал бы в ленту, и убирать его пришлось бы отдельно.
    private func finish() {
        // Сессию завершаем в любом случае — иначе таймер зависнет навсегда,
        // если собаку успели удалить с другого экрана.
        guard let finished = appState.finishSession() else { return }
        Task { await LiveActivityController.finishWalk(outcome: finished.tally) }

        guard let dog else {
            // **Путь теряет прогулку молча, и это про путь, а не про
            // случай.** Ветка закрывает сессию, показывает итог — и
            // не пишет ничего: ни в ленту, ни в журнал действий.
            //
            // ~~«Измерено 30.10.2026: прогулка 07:50 → 08:06 в журнале
            // есть двумя `finish:walk · done` и ни одной `record:walk`,
            // шестнадцать минут не записаны».~~ **Опровергнуто кадром
            // отзыва того же утра** (`2026-10-30_0814-AMcNF8YO-3.jpg`,
            // 09:07 локального): в ленте стоит «08:50 → 09:06 ·
            // Прогулка · 15 минут». Выгул записан; не записалась
            // строка `record` в журнале действий, и журнал шумит
            // лишним вторым `finish`. Разные дефекты и разная цена.
            //
            // > **Отсутствие строки в журнале я прочитала как
            // > отсутствие записи в дневнике.** Журнал отвечает про
            // > себя: «я не отметил» и «этого не было» — у него одна
            // > форма. Различил кадр, который человек приложил сам.
            //
            // Порядок выше менять нельзя — сессию закрываем безусловно,
            // иначе таймер зависнет навсегда (довод на строке 780
            // остаётся в силе). Чинится не порядок, а **молчание**:
            //
            // ```
            // было   показатьИтог(finished)   — итог как у записанной
            // стало  отказ человеку + отказ в журнале
            // ```
            //
            // > **Итог прогулки, показанный после незаписанной
            // > прогулки, — это не недоработка показа, а ложное
            // > свидетельство:** человек уходит уверенным, что выход
            // > в дневнике, и второй раз его не отметит.
            //
            // Живых случаев этой ветки в журнале за 27–30.10 ноль —
            // и названо это так нарочно: сюда попадают, когда видимой
            // собаки нет, а до 30.10 единственной причиной её
            // отсутствия была пустая база. С правкой `Dog.canBeShown`
            // того же дня причин стало меньше, не больше, — но ветка
            // достижима и обязана говорить.
            UsageLog.note(.finish, "walk:неЗаписана:нетСобаки",
                          on: .walk, outcome: .failed)
            Haptics.warning()
            appState.showFailure(
                String(localized: "Выход не записан: не выбрана собака. Открой «Собака» и выбери её — отметить можно вручную."))
            dismiss()
            return
        }

        // Короткий выход, открытый сюда кнопкой «Открыть» или тапом
        // по живой активности, уже лежит в ленте с начала. Прогулкой
        // поверх него он ложился вторым выходом за ту же дверь
        // (29.10.2026). Одна запись — та, что есть; см. `OutingFinisher.close`.
        if finished.kind == .outing {
            guard appState.can(.logBasics) else {
                appState.showFailure(String(localized: "Записывать может тот, кому это разрешено"))
                dismiss()
                return
            }
            if !OutingFinisher.close(finished, dog: dog, at: Date(), context: context) {
                Haptics.warning()
                appState.showFailure("Ответ не записался · отметь ещё раз")
            }
            OutingFinisher.записатьПрочиеОтметки(finished, dog: dog,
                                                 appState: appState, context: context)
            if finished.count(of: .incident) > 0 {
                EpisodeRaiser.afterIncident(dog: dog, context: context, appState: appState)
            }
            показатьИтог(finished)
            return
        }

        let log = EventLog(context: context, appState: appState)
        let duration = Int(finished.duration())

        let walkEvent = log.record(.walk, dog: dog, at: finished.startedAt,
                                   confirmation: "Записано · прогулка \(duration / 60) мин") { event in
            event.durationSeconds = duration
            event.note = finished.marks.isEmpty ? nil : finished.tally
        }

        for entry in finished.marks {
            log.record(entry.kind.logKind, dog: dog, at: entry.at,
                       confirmation: nil, haptic: .none) { event in
                WalkRecorder.apply(entry, to: event, dog: dog, walkID: walkEvent?.id)
            }
        }
        // Инцидент с прогулки поднимает эпизод так же, как из шторки
        // «Что случилось» (`EpisodeRaiser`, 29.10.2026).
        if finished.count(of: .incident) > 0 {
            EpisodeRaiser.afterIncident(dog: dog, context: context, appState: appState)
        }

        показатьИтог(finished)
    }

    /// Показать итог — или закрыть прогулку молча.
    ///
    /// **Решение принимается здесь, а не в теле вида, и это не вкус.**
    /// Первая редакция ставила условие прямо на `if let summary` —
    /// и при пустой прогулке `Group` проваливался в `else`, где сессии
    /// уже нет (её закрыл `finishSession()`), то есть человек после
    /// прогулки видел СТАРТОВУЮ шторку «Прогулка · таймер пойдёт
    /// сразу». Гейт, поставленный на показ, завёл бы дефект хуже того,
    /// что убирал.
    ///
    /// > Условие, выключающее экран, ставится там, где решают
    /// > его судьбу, а не там, где его рисуют: у отрисовки всегда
    /// > есть «иначе», и оно редко то, что нужно.
    private func показатьИтог(_ finished: ActiveSession) {
        guard естьЧтоРазбирать(finished) else {
            dismiss()
            return
        }
        summary = finished
    }
}

/// Итог прогулки. Короткий: человек только что вернулся с холода.
struct WalkSummarySheet: View {
    let session: ActiveSession
    let dog: Dog?
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var trigger: ReactionTrigger?
    @State private var distance: ReactionDistance?
    @State private var noteText = ""

    /// Есть ли что терять при закрытии.
    private var hasAnswers: Bool {
        trigger != nil || distance != nil
            || !noteText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        // Итог закрывается и крестиком, и свайпом — а ответы про срыв
        // сохранялись только по кнопке «Готово». Человек отвечал на два
        // вопроса, смахивал шторку и терял оба ответа молча.
        TGSheet(title: "Погуляли", subtitle: .готовая(Fmt.duration(session.duration())),
                onClose: { save() }, hasUnsavedChanges: hasAnswers) {
            statsCard
            if session.reactions > 0 { reactionCard }
            if session.count(of: .stool) > 0 { stoolNote }
            if session.count(of: .note) > 0 { noteCard }
            // НЕДОСТИЖИМО-С-07.10.2026 · ветка «отметок не было»
            //
            // Шторка перестала открываться без отметок: гейт
            // `показатьИтог(_:)` выше закрывает прогулку молча, если
            // не было ни срыва, ни инцидента, ни заметки (правило
            // ФИНАЛа, раздел 3). Значит `session.marks.isEmpty` здесь
            // истинным больше не бывает.
            //
            // **Не удалено нарочно, и текст не тронут:** тексты
            // заморожены решением Виктории, а мёртвый код с объяснением
            // честнее тихо выкинутой строки.
            //
            // СТАНЕТ ДОСТИЖИМОЙ СНОВА, если: снимут гейт
            // `естьЧтоРазбирать` — или на коротком выходе появятся
            // отметки срыва, заметки и инцидента, и правило растянут
            // на «Как сходил?». Оба случая находятся грепом по
            // `естьЧтоРазбирать`, а не по памяти.
            //
            // Это родня `verdictBadge` наоборот: там поле пишут
            // и никто не читает, здесь ветка читается кодом и никогда
            // не наступает. Обе формы видны только перечислением.
            if session.marks.isEmpty {
                TGExplainer(text: "Отметок не было — записалась только прогулка. Это нормально: не каждый выход надо разбирать.")
            }
        } footer: {
            TGButton(title: "Готово") {
                save()
                onDone()
            }
        }
    }

    /// Что на самом деле записалось со стулом.
    ///
    /// Раньше здесь стояло «стул записан как обычный» — и это было неправдой.
    /// Форму приложение подставляет, только если последние четыре стула были
    /// одинаковыми и без особенностей; в остальных случаях она пустая,
    /// и такая запись не попадает даже в график по стулу.
    @ViewBuilder
    private var stoolNote: some View {
        if let dog, Diary.usualStool(dog.events) != nil {
            TGExplainer(text: "Стул записан таким же, как обычно у него. Если было не так — тапни по строке в ленте и поправь.")
        } else {
            TGExplainer(text: "Стул записан без формы: приложение не угадывает её за тебя. Тапни по строке в ленте и выбери — тогда он попадёт в график.")
        }
    }

    /// Заметку набирают здесь, а не на улице.
    ///
    /// Кнопка «Заметка» в режиме прогулки ставила отметку без единого слова:
    /// в ленте оставалась пустая запись с подписью «на прогулке». Печатать
    /// на морозе всё равно невозможно — поэтому спрашиваем текст один раз,
    /// когда человек уже вернулся и остановился.
    private var noteCard: some View {
        TGCard {
            TGSectionHeader(title: session.count(of: .note) == 1 ? "что за заметка" : "заметки с прогулки",
                            subtitle: "отметку поставили на ходу — допиши словами")
            TextEditor(text: $noteText)
                .textStyle(AppFont.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
        }
    }

    /// Отметок мочи и опорожнений — две разные величины, и ось названа
    /// в той же строке, что число. Разбор — `ActiveSession.опорожнений`.
    private var меток: Int { session.count(of: .urine) }
    private var опорожнений: Int { session.опорожнений }
    private var метил: Bool { меток > опорожнений }

    private var statsCard: some View {
        TGCard {
            РядЧисел {
                TGStat(value: Fmt.duration(session.duration()), caption: "в пути", size: 20)
                // **«8 раз пописал» было утверждением о мочевом пузыре,
                // выведенным из числа тапов.** Отзыв 28.10.2026, 08:47:
                // «У меня кастрированный кобель, почему считает мочу
                // много раз?» Кобель метит; подряд идущие метки — одно
                // опорожнение, и это правило у Togo уже измерено
                // (`Diary.sameEmptyingWindow`) и применялось к вердикту,
                // но не к тому, что человек читает.
                //
                // Число остаётся её: тапы настоящие, и прятать их нельзя.
                // Меняется СЛОВО — с утверждения о физиологии на то, что
                // отмечено на самом деле.
                TGStat(count: меток,
                       сЧислом: метил
                           ? String(localized: "\(меток) раз пометил")
                           : String(localized: "\(меток) раз пописал"),
                       size: 20)
                if session.reactions > 0 {
                    TGStat(count: session.reactions,
                           сЧислом: String(localized: "\(session.reactions) срывов"),
                           size: 20)
                } else {
                    TGStat(value: session.count(of: .stool) > 0
                               ? String(localized: "да") : String(localized: "нет"),
                           caption: "стул", size: 20)
                }
            }
            if !session.marks.isEmpty {
                TGDivider()
                Text(session.tally).textStyle(AppFont.caption)
            }
            if метил {
                // Отвечаем ровно на заданный вопрос, и числом из кода,
                // а не из головы: окно подставляется из
                // `Diary.sameEmptyingWindow`, поэтому фраза не разойдётся
                // с правилом, когда правило подвинут.
                TGExplainer(text: .готовая(String(
                    localized: "Метки — не отдельные опорожнения: подряд идущие в пределах \(Fmt.duration(Diary.sameEmptyingWindow)) приложение считает одним разом. Вердикт «просится» считает по ним, а не по тапам — \(опорожнений) за этот выход."
                )))
            }
        }
    }

    /// Спрашиваем не «почему собака плохая», а на что и как близко.
    /// Из этих двух ответов и складывается работа с порогом.
    private var reactionCard: some View {
        TGCard {
            TGSectionHeader(title: session.reactions == 1 ? "на что сорвался" : "на что срывался",
                            subtitle: "одним тапом, если помнишь")
            TGChipGroup(items: ReactionTrigger.allCases, title: \.title,
                        isSelected: { $0 == trigger }, minimumWidth: 130) { chosen in
                trigger = trigger == chosen ? nil : chosen
                Haptics.tap()
            }

            TGDivider()
            TGSectionHeader(title: "как близко",
                            subtitle: "дистанция — главная ручка: что рвёт в двух метрах, часто спокойно проходится в двадцати")
            TGChipGroup(items: ReactionDistance.allCases, title: \.title,
                        isSelected: { $0 == distance }, minimumWidth: 110) { chosen in
                distance = distance == chosen ? nil : chosen
                Haptics.tap()
            }

            TGDivider()
            Text("Срыв — это порог, а не проступок")
                .textStyle(AppFont.bodyEmphasis)
            Text("Сорвавшаяся собака учиться сейчас не может, ругать её бессмысленно. Отойди дальше, дай выдохнуть, а в следующий раз держи дистанцию, на которой она справляется.")
                .textStyle(AppFont.caption)
        }
    }

    /// Дописываем подробности в уже созданные записи.
    private func save() {
        guard hasAnswers, let dog else { return }

        if trigger != nil || distance != nil {
            let times = Set(session.marks.filter { $0.kind == .reaction }.map(\.at))
            for event in dog.events where event.kind == .reaction && times.contains(event.date) {
                event.reactionTrigger = trigger
                event.reactionDistance = distance
            }
        }

        let text = noteText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            let times = Set(session.marks.filter { $0.kind == .note }.map(\.at))
            for event in dog.events where event.kind == .note && times.contains(event.date) {
                event.note = text
            }
        }
        // Заметка к прогулке — то, ради чего её и писали. Молчать
        // о непопавшей в хранилище нельзя: у этой шторки своего тоста
        // нет, поэтому отказ виден откликом и остаётся в журнале.
        if !context.persist(otherwise: {}) {
            Haptics.warning()
            UsageLog.note(.edit, "walk-note", on: .walk, outcome: .failed)
        }
    }
}

/// Карточка идущей прогулки или выхода на главном экране.
///
/// **Тап по карточке открывает режим обратно** — свернуть шторку
/// и потерять прогулку нельзя. Но только у прогулки: у выхода на той же
/// кнопке стоит «Стоп», и тап по всей карточке завершал выход целиком.
///
/// Так и читался отзыв «нажатие на один из таймеров закрывает экран»:
/// секундомер лежит внутри карточки, палец попадает в него, а не в кнопку
/// — и выход заканчивался, открывая шторку «Как сходил?» поверх экрана.
/// В тихие часы хуже: там выход закрывается молча, и экран просто меняется
/// сам по себе.
///
/// Правило отсюда общее: **жест на всю карточку ставится только там, где
/// он открывает.** Завершение спрашивает кнопку — по ней не промахиваются
/// случайно, и её видно.
struct ActiveSessionCard: View {
    let session: ActiveSession
    let now: Date
    var onOpen: () -> Void
    var onFinish: () -> Void

    var body: some View {
        TGCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(session.isPaused ? session.kind.pausedTitle : session.kind.runningTitle)
                        .textStyle(AppFont.micro.color(
                            // Горчица занята окном натощак: пауза красится
                            // спокойным серым, идущая прогулка — шалфеем.
                            session.isPaused ? Token.Ink.secondary : Token.Status.doneText
                        ))
                    TGStopwatch(session: session, now: now,
                                style: AppFont.display.color(
                                    session.isPaused ? Token.Ink.secondary : Token.Ink.primary
                                ))
                }
                Spacer()
                Button(session.kind == .walk ? "Открыть" : "Стоп") {
                    session.kind == .walk ? onOpen() : onFinish()
                }
                .textStyle(AppFont.cardTitle.color(Token.Ink.onAccent))
                .padding(.horizontal, Token.Space.s20)
                .frame(minHeight: Token.Size.tapTarget)
                .background(Token.Action.primary,
                            in: RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
            }
            Text("\(session.startedBy) · с \(Fmt.clock(session.startedAt)) · \(session.tally)")
                .textStyle(AppFont.caption)
                .wraps()
        }
        .contentShape(Rectangle())
        // Только у прогулки: у выхода тап по карточке означал бы «Стоп».
        .onTapGesture { if session.kind == .walk { onOpen() } }
    }
}
