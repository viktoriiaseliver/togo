import SwiftUI
import SwiftData

/// Главный экран. Порядок блоков: натощак → уход, если есть срок → таймлайн → режим дня.
/// В поездке между натощак и таймлайном встаёт блок дороги, а сводка «ел и пил»
/// поднимается выше таймлайна.
struct TodayScreen: View {
    /// Куда уводить, когда речь про собаку целиком: вкладка, а не шторка.
    var onOpenDog: () -> Void = {}

    /// Пришли тапом по живой активности (`togo://walk`) — открыть
    /// «На улице» сразу.
    ///
    /// **Вторая половина цепочки дизайна** (круг 3 §1 и круг 2 §6: «тап
    /// по активности открывает „На улице"»). Первая половина —
    /// `WalkLiveActivity.тапВедёт`, она стояла в дереве одна, и
    /// `RootView.handle` знал ровно один хост, `join`. Отказа человек
    /// не видел: неизвестный хост `handle` молча пропускал, и тап
    /// открывал просто приложение.
    ///
    /// Вход тем же способом, что у «Семьи» (`DogTab.открытьСемью`),
    /// и по той же причине: у `WalkModeScreen` нет вкладки, довести
    /// до него обязан тот, кто поймал ссылку. Маршрут тот же самый,
    /// которым экран открывается изнутри (`route = .walk` у карточки
    /// активной сессии) — второй путь показа разошёлся бы с первым молча.
    @Binding var открытьПрогулку: Bool

    @Environment(AppState.self) private var appState
    @Environment(Settings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var dogs: [Dog]
    @Query private var members: [FamilyMember]
    @Query private var trips: [Trip]
    @Query private var episodes: [Episode]
    @Query private var daysOut: [DayOut]

    @State private var route: TodayRoute?
    @State private var finishingDayOut: DayOut?
    @State private var now = Date()
    /// Какой день показан. Не путать с `now`: `now` — который час,
    /// это — за какой день считать. Пока показывают сегодня, они
    /// совпадают, и разницы не видно; на «вчера» она решает всё.
    @State private var показанныйДень = Date()
    /// Когда в последний раз предлагали воду в режиме «собака со мной».
    @State private var lastWaterOffer: Date?
    /// Когда дело ухода было сделано в прошлый раз — чтобы «вернуть»
    /// возвращало именно туда, а не обнуляло срок.
    @State private var lastCareDone: [UUID: Date?] = [:]
    @State private var lockedDose: LockedDose?
    @State private var missedDose: MissedDoseTarget?
    @State private var gatedDose: GatedDose?
    @State private var alarm: AlarmThreshold?
    /// Пункт плана, по которому спрашиваем «когда дали». Не пусто только
    /// когда назначенный час уже прошёл дольше чем на `LateMarking.grace`.
    @State private var askingGivenAt: DayPlanItem?
    /// Шторка «Записать» — та, что открывает круглая «+».
    @State private var показатьЗапись = false
    /// Настройки: открываются из меню «…», шестерёнки в шапке больше нет.
    @State private var показатьНастройки = false
    /// Насколько экран прокручен. Нужно ровно для одного: за 120 pt
    /// появляется компактная строка «время · дальше» (хендофф, «Сегодня»).
    @State private var прокрутка: CGFloat = 0
    /// Показать листалку дня.
    ///
    /// **Листалка уехала за пункт меню «Другой день»** — по кадру 01
    /// её в шапке нет. Но убрать её совсем было нельзя: это
    /// единственный способ записать вчерашнюю еду, и `пишемВоВчера`
    /// ниже на этом стоит. Пункт меню её показывает и прячет.
    @State private var показатьДругойДень = false

    // Три адресата шторок — `MissedDoseTarget`, `GatedDose`, `LockedDose` —
    // переехали в `DayPlanActions.swift`. Это чистые данные, и вложенными
    // в экран они были недостижимы для всего, что вне него.

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Показываемый день и настоящие часы — вместе, но не смешиваясь.
    /// Правило «докуда можно листать» и «что считать отсчётом» живёт
    /// в `ScreenDay`, а не в кнопке: кнопка — одна из поверхностей.
    private var экранДень: ScreenDay {
        ScreenDay(показать: показанныйДень, сейчас: now)
    }

    /// Момент, от которого считается всё «за этот день». Сегодня —
    /// настоящие часы, во вчера — конец тех суток.
    private var отсчёт: Date { экранДень.отсчёт }

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var events: [LogEvent] { dog?.events ?? [] }
    private var activeTrip: Trip? { trips.first { $0.isActive(on: now) } }

    /// Идущий день с собакой.
    private var activeDayOut: DayOut? {
        daysOut.first { $0.dog?.persistentModelID == dog?.persistentModelID && $0.isActive(at: now) }
    }

    /// Собака весь день рядом — поездка это или день по делам, неважно.
    ///
    /// В такой день приложение молчит про «просится»: она выходит
    /// постоянно, промежутки считаются по чужому дню, и вердикт
    /// не помогает, а мешает.
    private var isDogAlongside: Bool { activeDayOut != nil || activeTrip != nil }
    private var dutyMember: FamilyMember? { members.first(where: \.isOnDuty) }

    /// Собаку пропустили на онбординге. Говорим об этом прямо: пустой день
    /// без объяснения читается как сломанное приложение, а не как выбор.
    private var нетСобаки: some View {
        EmptyStateCard(
            subject: .day,
            title: "Собака пока не заведена",
            message: "Отмечать некого: еда, выходы и дозы считаются по собаке. Заведи её — нужны только кличка и вес.",
            actionTitle: "Завести собаку",
            action: onOpenDog
        )
    }

    /// Экран читается сверху вниз одним взглядом: что случилось, что идёт
    /// прямо сейчас, что было за день, что осталось сделать. Раньше здесь
    /// лежала двести одна строка, внутри которой всё это перемешано
    /// с шестью шторками и закрытием дня, — порядок был, но увидеть его
    /// можно было только прочитав всё.
    var body: some View {
        NavigationStack {
            соШторками(сЧасами(
                ZStack {
                    // **Подложка «Сегодня» — та же, что у вкладок
                    // и подэкранов**, и лежит она ПОД прокруткой,
                    // а не в ней. Решение 23.10.2026: индиговый плакат
                    // режима дня отменён вместе с индиго как акцентом
                    // («Кино» заменяет Graphite), а фотографию человека
                    // показывает один хозяин — `BackgroundStore`.
                    //
                    // Здесь стояли два слоя, и оба сняты:
                    //
                    // ```
                    // Token.Surface.screen           чёрное полотно — его
                    //                                рисует сам CinemaBackdrop
                    // PosterPaint.background(режим)  полоса под статус-баром,
                    //                                #2A3670 на кадре 01
                    // ```
                    //
                    // Полоса существовала потому, что снимок рисовала
                    // панель показания ВНУТРИ `ScrollView`, где
                    // `.ignoresSafeArea` за обрезку прокрутки не выходит
                    // (кадр 07.10: чёрная полоса над плакатом). Снаружи
                    // прокрутки обрезки нет, и закрашивать вырез отдельным
                    // цветом больше нечем: до верха доходит сама подложка.
                    CinemaBackdrop(экран: .today)
                        .ignoresSafeArea()
                    ScrollView {
                        // Плакат — ВО ВСЮ ШИРИНУ, поэтому он снаружи
                        // отступов экрана, а не внутри. Это решение
                        // дизайна: верхняя треть — цветной блок, а
                        // не карточка с полями по краям.
                        VStack(alignment: .leading, spacing: 0) {
                            плакат
                            VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                                строкаДальше
                                if dog == nil { нетСобаки }
                                тревоги
                                происходящее
                                деньПозади
                                планНаОстаток
                            }
                            .padding(.horizontal, Token.Spacing.screenPadding)
                            .padding(.top, Token.Spacing.stack)
                            .padding(.bottom, 24)
                        }
                        // Прокрутка меряется ОДНИМ способом и в одном
                        // месте: компактная строка появляется за 120 pt,
                        // и второй замер той же величины разошёлся бы
                        // с этим молча.
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ПрокруткаКлюч.self,
                                    value: -proxy.frame(in: .named("сегодня")).minY
                                )
                            }
                        }
                    }
                    .coordinateSpace(name: "сегодня")
                    .onPreferenceChange(ПрокруткаКлюч.self) { значение in
                        прокрутка = значение
                    }
                    // Компактная строка «время · дальше» — поверх, а не
                    // в потоке: она появляется, когда шапка уже уехала,
                    // и обязана стоять на месте шапки.
                    .overlay(alignment: .top) {
                        if прокрутка > 120 { компактнаяСтрока }
                    }
                    // **Безопасную область здесь НЕ игнорируем.** Так было
                    // в первой редакции — и кадр показал, что под статус-бар
                    // уехала шапка «Стич · 4,1 кг · дежурит Тео» и
                    // обрезалась о часы. Вверх расширяется ПОДЛОЖКА плаката
                    // (внутри `TGPoster`), а содержимое остаётся в безопасной
                    // области. Цвет до верха, текст — нет.
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        // Кнопки записи работают и на прошлом дне —
                        // с 28.09 день доезжает до всех листов через
                        // `AppState.деньЗаписи`, а не через десять
                        // отдельных параметров.
                        //
                        // Фон — на ВСЕЙ полосе, а не только на сетке
                        // кнопок. Своя `.regularMaterial` живёт внутри
                        // `ActionGrid`, и строка над ним оставалась
                        // прозрачной: на кадре 28.09 сквозь неё
                        // просвечивал герой, и читались обе строки разом.
                        if !экранДень.этоСегодня { пишемВоВчера }
                        // Сетка из шести кнопок заменена на три органа:
                        // главная по состоянию, вторая и круглая «+».
                        // Решение Виктории 22.10.2026; состав и цвет —
                        // с кадров 01 и 02.
                        TodayBottomBar(tone: тонЭкрана,
                                       главная: главноеДействие,
                                       вторая: второеДействие,
                                       записать: { показатьЗапись = true })
                    }
                    .background(.regularMaterial)
                }
                // День записи ставится ровно тем, что показано, и
                // снимается возвратом в сегодня. Снимать обязательно:
                // иначе человек уйдёт с экрана и продолжит писать
                // во вчера, сам того не зная.
                .onChange(of: экранДень.начало) { _, _ in обновитьДеньЗаписи() }
                .onAppear { обновитьДеньЗаписи() }
                .onDisappear { appState.деньЗаписи = nil }
                // Заголовок «Сегодня» рисует сама панель показания:
                // по кадру он лежит ПОВЕРХ фотографии и делит строку
                // с пилюлей запаса, чего системный заголовок не умеет.
                // Поэтому панель навигации скрыта, а не настроена.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .usageScreen(.today)
                // Шестерёнки в шапке больше нет — настройки уехали
                // в меню «…» внутри панели показания.
                .navigationDestination(isPresented: $показатьНастройки) {
                    SettingsScreen()
                }
            ))
        }
    }

    /// Куда прокручен экран. Отдельный ключ, а не `@State` в замыкании:
    /// `preference` — единственный способ донести величину снизу вверх,
    /// не считая её дважды.
    private struct ПрокруткаКлюч: PreferenceKey {
        static var defaultValue: CGFloat { 0 }
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private func обновитьДеньЗаписи() {
        appState.деньЗаписи = экранДень.этоСегодня ? nil : экранДень.начало
    }

    /// Полоса над кнопками на прошлом дне.
    ///
    /// **Кнопки работают, и именно поэтому нужна полоса.** Молча
    /// записать вчерашнюю еду опаснее, чем не записать: подтверждение
    /// человек увидит, а куда оно легло — нет. Час подставляется тот же,
    /// что сейчас, и это догадка — она названа и здесь, и в самом
    /// подтверждении.
    private var пишемВоВчера: some View {
        HStack(spacing: Token.Space.s8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: Token.Size.iconSm))
                .accessibilityHidden(true)
            Text("Пишем в этот день")
                .textStyle(AppFont.caption)
                .wraps()
            Spacer(minLength: Token.Space.s8)
            Button("В сегодня") { показанныйДень = now }
                .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
                .fixedSize()
        }
        .foregroundStyle(Token.Status.waitingText)
        .frame(minHeight: Token.Size.tapTarget)
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, Token.Space.s8)
    }

    // MARK: Что случилось — то, из-за чего экран открыли

    /// Порядок внутри не случайный: сначала то, что мешает самому дневнику
    /// работать, потом здоровье, потом расписание. Человек читает сверху.
    @ViewBuilder
    private var тревоги: some View {
        if Persistence.isEphemeral {
            TGBanner(
                tone: .alarm,
                title: "Записи сейчас не сохраняются",
                subtitle: "Дневник не смог открыть хранилище — записанное сейчас пропадёт при перезапуске. Перезапусти приложение; не поможет — напиши в поддержку, старые записи целы.",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        }

        // **Показание переехало в плакат, строка про режим осталась
        // здесь.** `showsReading: false` — не экономия, а отказ от
        // копии: в `support` живут порог `rhythm.isReliable` и правило
        // «`Fmt.plural` возвращает число вместе со словом», на котором
        // здесь уже починен дефект «3 3 выхода за день». Переписать
        // строку рядом с плакатом значило бы завести вторую
        // реализацию, которая разойдётся молча.
        TodayHero(indoors: timeIndoors,
                  lastOutingEndedAt: lastOutingEndedAt,
                  session: appState.session,
                  now: now,
                  rhythm: WalkRhythmAnalyzer.rhythm(events: events, now: now),
                  outingsToday: outingsToday,
                  showsReading: false)

        // Порог тревоги: счёт дошёл сам, и человек должен увидеть это
        // до того, как начнёт гадать в три часа ночи, «уже пора или ещё нет».
        if let threshold = AlarmThresholdAnalyzer.evaluate(events: events, now: now) {
            Button { alarm = threshold } label: {
                TGBanner(tone: .alarm,
                         title: "Похоже, пора звонить",
                         subtitle: .готовая(threshold.headline + String(localized: " · есть готовый текст врачу")),
                         systemImage: "phone.badge.waveform")
            }
            .buttonStyle(.plain)
        }

        if let fasting = fastingWindow {
            TGBanner(
                tone: .waiting,
                title: .готовая(String(localized: "Не кормить до \(Fmt.clock(fasting.freeAt))")),
                subtitle: .готовая(подписьОкна(fasting)),
                systemImage: "clock.badge.exclamationmark"
            )
        }

        if let overdue = overdueDose {
            VStack(alignment: .leading, spacing: Token.Space.s8) {
                TGBanner(
                    tone: .alarm,
                    title: "Доза \(Fmt.clock(overdue.scheduledAt)) не отмечена",
                    subtitle: .готовая(claimSubtitle(overdue)),
                    systemImage: "exclamationmark.triangle"
                )
                if !overdue.claimIsActive(at: now) {
                    TGButton(title: "Беру на себя", variant: .secondary,
                             size: .medium, systemImage: "hand.raised") {
                        claim(overdue)
                    }
                }
            }
        }
    }

    // MARK: Что идёт прямо сейчас

    /// Поездка, выездной день и начатая прогулка. Всё это — состояния,
    /// у которых есть конец, и каждое даёт свою кнопку «закончить».
    @ViewBuilder
    private var происходящее: some View {
        if let trip = activeTrip {
            TripTodayBlock(trip: trip, dog: dog, now: now)
            summaryStrip
        }

        if let day = activeDayOut {
            DayOutCard(day: day, now: now, lastWater: lastWaterOffer) {
                lastWaterOffer = Date()
                Haptics.tap()
            } onFinish: {
                закрытьДень(day)
            }
        }

        if let session = appState.session {
            ActiveSessionCard(
                session: session,
                now: now,
                onOpen: { session.kind == .walk ? (route = .walk) : endOuting() },
                onFinish: { endOuting() }
            )
        }
    }

    // MARK: Что было за день и что осталось

    @ViewBuilder
    private var деньПозади: some View {
        DayTimeline(events: Diary.onDayWithTraces(events, отсчёт, tracing: undoableDeletions),
                    now: отсчёт,
                    showsAuthor: members.count > 1) { event in
            route = .edit(event.id)
        }

        // В поездке сводка уже показана выше, рядом с блоком поездки.
        if activeTrip == nil { summaryStrip }

        // Единственная запись, которая меняет поведение, а не фиксирует
        // его. Показывается, только когда сигналов набралось достаточно.
        // Откат — `Fmt.dogNameOrFallback`, а НЕ местоимение.
        //
        // Здесь стояло `?? String(localized: "Он")`, и у суки без клички
        // карточка говорила «**Он** чаще просит спокойно»: приложение
        // называло пол, которого не спрашивало. `Dog.sex` существует —
        // по нему работает `tracksHeat`, — но у безымянной собаки он
        // чаще всего и не задан, а догадка о поле в дневнике дороже
        // неловкой фразы.
        //
        // Второе, и оно про устройство: «Он» было ЧЕТВЁРТЫМ запасным
        // словом для безымянной собаки — рядом с «Собака»,
        // «собаку», «собакой» — и единственным, которое что-то
        // утверждало о собаке. Остальные три существительные и рода
        // не называют. Теперь их три, и все идут через одну реализацию.
        //
        // Форму по полу не завёл нарочно: ключа «Она» в каталоге нет
        // вовсе, а новый ключ — это четыре языка под заморозкой текстов.
        // Выгода — одна фраза читается естественнее; цена — пробел
        // в трёх языках и ветка, которой нечем ответить при незаданном
        // поле.
        // Показ идёт через `Dog.displayName`, а не через помощника напрямую.
        //
        // **Поведение от этой правки не меняется ни в одном случае,
        // и это проверено:** `displayName` — это буквально
        // `Fmt.dogNameOrFallback(name)` (`Dog.swift:357`), то есть здесь
        // вызывался тот же помощник в обход точки показа. Пустая кличка
        // и до правки доезжала словом, а не пустым местом.
        //
        // Чинится не дефект, а ДОРОГА: сторож на подстановки держит
        // «показ человеку идёт одной точкой», и смысл этого — чтобы
        // следующая правка точки доехала до всех поверхностей сразу.
        // Допиши в `displayName` падеж или род — и строка, звавшая
        // помощника сама, за ним не пойдёт, а сторож на вызов этого
        // не увидит: вызов-то есть.
        //
        // > Третья реализация одного правила живёт независимо и молчит.
        //
        // Падежа здесь не нужно — `AskSignalCard:111` ставит кличку
        // в именительном («… чаще просит спокойно»), и падежный сторож
        // этой поверхности не касается. Проверено до правки: у нас
        // `CaseSlotFallbackTests` и запрет подстановок однажды
        // требовали обратного друг от друга, и оба были правы.
        //
        // Запасное слово берётся у помощника, а не литералом в `??`:
        // литерал справа от `??` в каталог не идёт.
        AskSignalCard(events: events,
                      dogName: dog?.displayName ?? Fmt.dogNameOrFallback(""),
                      now: now)
    }

    private var планНаОстаток: some View {
        DayPlanList(items: planItems, now: отсчёт,
                    onComplete: { complete($0) },
                    onUndo: { uncomplete($0) },
                    onOpen: { open($0) },
                    awaitingDate: careAwaitingDate,
                    onOpenCare: onOpenDog)
    }

    /// Закрыть выездной день.
    ///
    /// Вынесено из замыкания карточки: там это была единственная бизнес-логика
    /// внутри `body`, и её нельзя было ни прочитать рядом с остальными
    /// действиями экрана, ни позвать откуда-то ещё.
    ///
    /// День закрываем сразу: иначе итог считался бы от «сейчас» и рос,
    /// пока человек его читает. Итоговая шторка открывается только после
    /// удачи — под `try?` она показывала итог дня, который в хранилище
    /// остался незакрытым, и назавтра день продолжал идти.
    private func закрытьДень(_ day: DayOut) {
        let былКонец = day.endedAt
        day.endedAt = Date()
        guard context.persist(otherwise: { day.endedAt = былКонец }) else {
            Haptics.warning()
            appState.showFailure("День не закрылся · нажми ещё раз")
            return
        }
        finishingDayOut = day
    }

    // MARK: Время экрана

    /// Всё, что экран делает со временем: тик, возвращение из фона,
    /// пересборка напоминаний. Одна тема — одно место; раньше эти строки
    /// стояли вперемешку с показом шторок.
    ///
    /// Метод, а не отдельный `ViewModifier`: состояние экрана объявлено
    /// `@State private`, и чужой тип в этом же файле до него не дотянется.
    private func сЧасами(_ содержимое: some View) -> some View {
        содержимое
            .onReceive(tick) { date in
                now = date
                LiveActivityController.publishSnapshot(dog: dog, appState: appState, now: date)
            }
            .task {
                LiveActivityController.publishSnapshot(dog: dog, appState: appState, now: now)
                // Отметки приёма на сегодня заводятся лениво: без них
                // эскалация не знает, что дозу пропустили.
                if let dog { DoseScheduler.ensureDoses(for: dog, on: now, context: context) }
                appState.refreshEpisode(from: episodes, at: now)
                // Напоминания пересобираются при каждом открытии: их мало,
                // а разойтись они могут молча.
                await ReminderScheduler.refresh(dog: dog, settings: settings, at: now)
            }
            // `Timer.publish` в фоне не тикает: вернувшись в приложение,
            // человек до следующего тика видит вчерашнее «сейчас».
            // 21.09.2026 это выглядело как метка «сейчас · 14:03», стоящая
            // ПОСЛЕ записей 14:04, — и читалось как сломанная сортировка
            // ленты, хотя лента была в порядке.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                now = Date()
            }
            // Запись приходит с настоящим временем, а `now` — с тика:
            // между ними до тридцати секунд. В этот зазор метка «сейчас»
            // встаёт ПЕРЕД только что записанной строкой, а конец
            // прогулки оказывается в будущем. Кадр тестировщицы 24.09:
            // прогулка до 16:01 и «сейчас · 16:00» под ней.
            .onChange(of: events.count) { _, _ in
                now = Date()
            }
            .onChange(of: episodes.count) { _, _ in
                appState.refreshEpisode(from: episodes, at: now)
            }
    }

    // MARK: Шторки

    /// Шесть отдельных разговоров, которые экран заводит по своим поводам.
    /// В `body` они занимали больше места, чем сам экран.
    private func соШторками(_ содержимое: some View) -> some View {
        содержимое
            .sheet(item: $route) { route in
                TodayRouter(route: route, dog: dog, now: now, onOpenDog: onOpenDog)
            }
            // Тап по живой активности. Флаг снимается здесь же: иначе
            // второй тап при уже стоящем `true` не даст `onChange`,
            // и шторка откроется один раз за запуск.
            //
            // `initial: true` — ссылка приходит ДО появления экрана,
            // когда приложение было выгружено: `onOpenURL` у `RootView`
            // срабатывает на старте сцены, а `TodayScreen` в этот момент
            // ещё не подписан. Без этого холодный запуск по ссылке
            // открывал бы просто приложение — ровно то, что мы и чиним.
            .onChange(of: открытьПрогулку, initial: true) { _, просят in
                guard просят else { return }
                route = .walk
                открытьПрогулку = false
            }
            .sheet(item: $finishingDayOut) { day in
                DayOutSummarySheet(day: day)
            }
            // Шторка «Записать» — та, что открывает круглая «+».
            // Инцидент в ней первым и красным: когда он нужен,
            // его ищут в панике.
            .sheet(isPresented: $показатьЗапись) {
                RecordSheet(порцияГрамм: dog?.servingGrams ?? 0,
                            подзаголовок: подзаголовокЗаписи) { выбор in
                    route = выбор
                }
            }
            .sheet(item: $askingGivenAt) { item in
                // `Date()`, а не экранное `now`: оно тикает раз в тридцать
                // секунд и в фоне стоит вовсе, а здесь «сейчас» попадёт
                // в запись как есть.
                GivenAtSheet(title: item.title, scheduled: item.time,
                             сейчас: экранДень.моментБыстройЗаписи,
                             предел: отсчёт) { момент in
                    complete(item, givenAt: момент)
                }
            }
            .sheet(item: $missedDose) { target in
                MissedDoseSheet(medication: target.medication, missed: target.missed, now: now) {
                    // Нарочно без вопроса «когда дали»: отсюда он открыл бы
                    // шторку поверх закрывающейся, а проверить это кадром
                    // я не могу — сценария пропущенной дозы в `SeedData` нет.
                    // Известная дыра, а не решение: пропущенная доза — как
                    // раз тот случай, где час важнее всего.
                    complete(target.item, givenAt: Date())
                } onSkip: {
                    // Пропуск — тоже запись: иначе в истории останется дыра,
                    // а врач спросит именно про неё.
                    skipDose(target)
                }
            }
            .sheet(item: $gatedDose) { gated in
                DoseGateSheet(medication: gated.medication,
                              state: gated.item.gate, now: now)
            }
            .sheet(item: $alarm) { threshold in
                // Полоса тревоги без собаки не появляется вовсе — заводить
                // ради заглушки пустую модель незачем.
                if let dog {
                    AlarmThresholdScreen(threshold: threshold, dog: dog,
                                         medications: dog.medications, events: events) {
                        Task { await ReminderScheduler.remindToWatch(at: now.addingTimeInterval(3600)) }
                    }
                }
            }
            .sheet(item: $lockedDose) { locked in
                DoseLockSheet(title: locked.item.title,
                              markedBy: locked.givenBy,
                              markedAt: locked.givenAt) {
                    // Другая доза — записываем отдельно, со своим временем.
                    route = .more
                } onUndo: {
                    uncomplete(locked.item)
                }
            }
    }

    // MARK: Шапка

    // MARK: Плакат — верхняя треть

    // **`PosterMode` «Сегодня» больше не спрашивает, и это снятие
    // механизма, а не забытый вызов** (23.10.2026). Здесь жили
    // `состояниеДня` и `режимПлаката`; их единственным читателем была
    // полоса `PosterPaint.background` под статус-баром, то есть цвет
    // индигового плаката режима дня. Индиго как акцент отменено
    // решением Виктории 22.10, подложку рисует `CinemaBackdrop`,
    // и у режима на этом экране не осталось ни одного читателя.
    //
    // Сам тип НЕ ТРОНУТ: его спрашивают виджет, «остров» и «На улице»,
    // а разбор, почему правило живёт в `TogoShared/Domain/PosterMode.swift`,
    // а не во вью, — там же. Что экран показывает вместо режима, решает
    // `ReadingTone` (`TodayStateRouter.tone`), и расхождение двух очередей
    // названо в голове `ReadingTone`.


    /// Показание плаката.
    ///
    /// Правило тишины НЕ дублируется: `TodayHero.silence(…)` статическое
    /// ровно для этого — 24.09 его вынесли из вью, потому что Siri
    /// читала ту же величину мимо потолка и отвечала «дома 434 ч».
    /// **Правила те же, что были у плаката, — изменился только тип
    /// ответа.** Ни одно условие здесь не выведено заново: правило
    /// тишины по-прежнему `TodayHero.silence(…)`, статическое ровно
    /// для этого — 24.09 его вынесли из вью, потому что Siri читала
    /// ту же величину мимо потолка и отвечала «дома 434 ч».
    private var показаниеПанели: ReadingPanel<ШапкаПанели>.Показание {
        if let session = appState.session {
            // `duration(at:)`, а не `now − startedAt`: пауза вычитается
            // внутри. Прототип пишет то же самое —
            // `elapsed = max(0, now − start − paused)`, — и считать это
            // здесь своей рукой значило бы завести вторую реализацию,
            // которая разойдётся на первой же паузе.
            return .минутыСекунды(session.duration(at: now))
        }
        if let тишина = TodayHero.silence(indoors: timeIndoors,
                                          lastOutingEndedAt: lastOutingEndedAt) {
            return .фраза(.готовая(String(localized: "Выходов нет с \(Fmt.shortDay(тишина))")))
        }
        guard let indoors = timeIndoors else {
            return .фраза("Сегодня ещё не выходили")
        }
        return .часыМинуты(indoors)
    }

    /// Подпись показания — прежняя строка состояния.
    ///
    /// **С 22.10.2026 это ЧИП состояния, а не подпись под числом.**
    /// Слот подписи у новой панели упразднён: на кадре 01 слово «Дома»
    /// стоит чипом слева сверху, а не строкой под показанием. Правило
    /// же осталось тем самым и переехало целиком — вместе с разбором,
    /// который его оплатил, потому что оно про **смысл**, а не про
    /// место.
    ///
    /// **Подпись называет ВЕЛИЧИНУ, а не факт дня — и это починка
    /// моей же регрессии часовой давности.**
    ///
    /// У героя до переноса стояло «10 ч 17 мин **назад** · на улице
    /// были», и слово «назад» делало фразу истинной. Перенося показание
    /// в плакат, я его уронил — в макете такого слота нет, — и экран
    /// стал читаться сверху вниз как «десять часов семнадцать минут
    /// были на улице». Величина при этом `timeIndoors`, то есть
    /// **сколько собака ДОМА**. Обратное правде.
    ///
    /// Нашёл `togo-08` чтением по слотам, не прогоном: все проверки
    /// были зелёными, обе строки по отдельности верны, ложным стало
    /// соседство.
    ///
    /// > **Подпись к ЧИСЛУ и подпись к ДНЮ выражены одним слотом.**
    /// > Поэтому каждая строка верна по отдельности, а ложным
    /// > становится соседство — и ничто в коде об этом не скажет:
    /// > строки выбираются разными правилами в разных местах файла.
    ///
    /// Сюда нельзя класть факт дня («сегодня выходили», «два выхода»).
    /// Нужен факт дня — ему отдельная строка ниже, вне слота подписи
    /// к числу.
    ///
    /// **И значок меняется вместе со словом, а не после него.** Идущий
    /// человек над числом «сколько дома» врёт и тому, кто подпись
    /// не прочёл: глиф несёт смысл мимо слов, как цвет мимо зрения,
    /// и починка в одной модальности из двух выглядит законченной.
    ///
    /// Коварство этой инверсии в том, что рядом есть место, где тот же
    /// слот читается как подпись к числу **верно**: во время прогулки
    /// «12:34 · на улице» — правда. Человек выучивает связь там, где
    /// она честная, и применяет там, где она врёт.
    private var чипСостояния: ReadingPanel<ШапкаПанели>.Чип {
        // Верхнее состояние называет себя само — и красит чип.
        // На кадре 02 это «Доза по часам · 17:59» синим.
        switch состояниеВерхнее {
        case .alarm, .threshold:
            return .init(символ: "exclamationmark.triangle",
                         текст: "Похоже, пора звонить", цветной: true)
        case .dose:
            return .init(символ: "pills", текст: "Доза по часам", цветной: true)
        case .fasting:
            return .init(символ: "clock.badge.exclamationmark",
                         текст: "Натощак", цветной: true)
        case .walk:
            return .init(символ: "figure.walk", текст: "На улице", цветной: true)
        case .night:
            return .init(символ: "moon", текст: "Тихие часы")
        case .episode:
            return .init(символ: "waveform.path.ecg", текст: "Наблюдаем", цветной: true)
        case .trip:
            return .init(символ: "car", текст: "Поездка")
        case .sitter:
            return .init(символ: "person.badge.clock", текст: "Ситтер")
        case .away:
            return .init(символ: "figure.walk.motion", текст: "Со мной весь день")
        case .stock:
            return .init(символ: "pills.circle", текст: "Запас кончается")
        case .offline:
            return .init(символ: "icloud.slash", текст: "Дневник не доехал")
        case .first:
            return .init(символ: "sparkles", текст: "Первый день")
        case .silence:
            return .init(символ: "moon.zzz", текст: "Давно не выходили")
        case .normal:
            return обычныйЧип
        }
    }

    /// Чип обычного дня. Здесь и живёт прежнее правило подписи.
    private var обычныйЧип: ReadingPanel<ШапкаПанели>.Чип {
        // **Подпись зависит от ВИДА ПОКАЗАНИЯ, а не от режима дня.**
        //
        // Это обобщение правки, которую сделали часом раньше для одного
        // режима, — и кадр показал, почему одного мало:
        //
        // ```
        // натощак   🕐 Не кормить до 19:36      ← состояние
        //           12 ч 14 мин                 ← ЧИСЛО БЕЗ ИМЕНИ
        //           🕐 Не кормить до 19:36 · после Левотироксин в 18:56
        //                                       ← ДУБЛЬ той же строки
        // ```
        //
        // Строка состояния въехала в слот, принадлежащий подписи
        // показания, вытеснила её — и получилось два одинаковых
        // утверждения и одно число, про которое не сказано, чего
        // оно. Дубль был следствием, а не причиной (разбор
        // `projects-74` по кадру).
        //
        // > **Слот, у которого один смысл, не может потерять его
        // > в одном режиме из пяти.**
        //
        // Состояние при этом не теряется: оно живёт плашкой прямо под
        // блоком, и там у него есть препарат, час и «видят все» —
        // три факта вместо одной строки.
        switch показаниеПанели {
        case .часыМинуты:
            // Единственный вид показания, которому нужно имя: голое
            // число часов. `timeIndoors` — сколько собака ДОМА.
            return .init(символ: "house.fill", текст: "Дома")
        case .минутыСекунды, .фраза:
            // Таймер прогулки называет себя сам; предложение
            // («Сегодня ещё не выходили») — тоже. Слово «Дома»
            // над ними было бы ложью, а не лишним чипом.
            //
            // Чип при этом остаётся: у панели он не опционален,
            // и пустого места на его месте дизайн не рисует.
            // Поэтому здесь называется ДЕНЬ, а не величина, — и это
            // ровно та граница, которую разбор выше и защищает.
            return .init(символ: "pawprint", текст: "Сегодня")
        }
    }

    // MARK: Состояние дня — один тон на весь экран

    /// Что приложение знает о дне.
    ///
    /// **Ни один флаг здесь не выведен заново** — все приходят от тех же
    /// анализаторов, что красят баннеры ниже на экране. Это главное
    /// требование: третья реализация одного правила у Togo уже стоила
    /// дня (виджет считал окно «не кормить» своей арифметикой, сторож
    /// на вызов был к этому слеп).
    ///
    /// ```
    /// isAlarm      appState.isEpisodeActive — острое, «взяли телефон»
    /// isThreshold  AlarmThresholdAnalyzer — счёт дошёл сам
    /// isDoseDue    overdueDose (то же, что у баннера дозы)
    /// isFasting    fastingWindow (то же, что у баннера натощак)
    /// isTrip       activeTrip · isAway activeDayOut
    /// isWalking    appState.session
    /// isNight      settings.isQuietHour — тихие часы, уже настраиваемые
    /// hasNoEntries rhythm.days == 0 — записей НЕ БЫЛО, а не «ритма нет»
    /// isSilent     TodayHero.silence — тот же потолок тишины
    /// ```
    ///
    /// **Три флага не заполнены, и это названо, а не спрятано:**
    /// `isSitter`, `isStockLow`, `isOffline`. У них в проекте нет
    /// готового источника — роль ситтера есть, но «сегодня дежурит
    /// ситтер» из неё не следует; `PillSupply` считает запас, но
    /// из приложения его не зовёт никто (`PillSupply.supply` — ноль
    /// вызовов в Swift, замер 22.10.2026); состояния связи у нас нет
    /// вовсе. Поставить им `false` молча значило бы получить
    /// «механизм без входа»: очередь состояний готова, а три её
    /// ступени недостижимы ни при каком дне. Названо в отчёте.
    private var состояниеПоказания: TodayStateRouter.DayState {
        var s = TodayStateRouter.DayState()
        s.isAlarm = appState.isEpisodeActive
        s.isThreshold = AlarmThresholdAnalyzer.evaluate(events: events, now: now) != nil
        s.isDoseDue = overdueDose != nil
        s.isFasting = fastingWindow != nil
        s.isEpisode = appState.isEpisodeActive
        s.isTrip = activeTrip != nil
        s.isAway = activeDayOut != nil
        s.isWalking = appState.session != nil
        s.isNight = settings.isQuietHour(now)
        s.hasNoEntries = ритм.days == 0
        s.isSilent = TodayHero.silence(indoors: timeIndoors,
                                       lastOutingEndedAt: lastOutingEndedAt) != nil
        return s
    }

    private var ритм: WalkRhythm {
        WalkRhythmAnalyzer.rhythm(events: events, now: now)
    }

    /// «сейчас · 17:54» или дата — подзаголовок шторки «Записать».
    ///
    /// На прошлом дне он обязан сказать, КУДА пишем: молча записать
    /// вчерашнюю еду опаснее, чем не записать, — подтверждение человек
    /// увидит, а куда оно легло, нет.
    private var подзаголовокЗаписи: String {
        экранДень.этоСегодня
            ? String(localized: "сейчас · \(Fmt.clock(now))")
            : Fmt.shortDay(экранДень.начало)
    }

    private var состояниеВерхнее: TodayState {
        TodayStateRouter.top(состояниеПоказания)
    }

    /// Тон экрана. Один на панель, чип, фото и главную кнопку.
    private var тонЭкрана: ReadingTone {
        TodayStateRouter.tone(состояниеПоказания)
    }

    /// Пилюля справа в строке заголовка.
    ///
    /// На кадрах это «Запас 5 дн» терракотом — и она **независима
    /// от тона**: на 01 и 02 она одна и та же при разных тонах.
    /// Источника для неё у нас нет (см. `isStockLow` выше), поэтому
    /// пилюли сейчас нет вовсе. Пустая пилюля лучше выдуманного числа:
    /// «Запас 5 дн» при несчитаемом запасе — это утверждение
    /// приложения о мире, которое врач потом прочтёт.
    private var пилюляЗаголовка: ReadingPanel<ШапкаПанели>.Пилюля? { nil }

    /// «гулял в 15:44» — откуда считаем.
    private var откудаСчитаем: String? {
        guard let конец = lastOutingEndedAt else { return nil }
        return String(localized: "гулял в \(Fmt.clock(конец))")
    }

    /// «обычно до 22:44» — докуда. Говорится только когда ритм
    /// надёжен: до трёх дней записей это была бы выдумка, а не прогноз.
    private var докудаСчитаем: String? {
        guard ритм.isReliable, let конец = lastOutingEndedAt else { return nil }
        let ожидаемый = конец.addingTimeInterval(ритм.averageIndoors)
        return String(localized: "обычно до \(Fmt.clock(ожидаемый))")
    }

    /// Насколько заполнена полоса-косточка.
    ///
    /// Доля считается от **среднего** промежутка дома, который уже
    /// посчитал `WalkRhythmAnalyzer`. Пусто, пока ритм ненадёжен:
    /// полоса без знаменателя показывала бы долю от выдуманного целого.
    private var доляРитма: Double? {
        guard ритм.isReliable, ритм.averageIndoors > 0,
              let дома = timeIndoors else { return nil }
        return дома / ритм.averageIndoors
    }

    // MARK: Низ — главная кнопка по состоянию

    /// Что делать прямо сейчас. Кнопка меняется вместе с тоном.
    ///
    /// **«Вывожу» (здесь — «Просится») остаётся первой во всех исходах
    /// вердикта** — красная линия проекта: приложение не знает лучше
    /// хозяина. Поэтому в обычном дне главная кнопка открывает вердикт,
    /// а не «Гулять»: она спрашивает, а не решает.
    private var главноеДействие: TodayBottomBar.Действие {
        switch состояниеВерхнее {
        case .alarm, .threshold:
            return .init(название: "Позвонить", символ: "phone.badge.waveform") {
                if let threshold = AlarmThresholdAnalyzer.evaluate(events: events, now: now) {
                    alarm = threshold
                }
            }
        case .dose:
            return .init(название: "Дал", символ: "pills") {
                if let item = planItems.first(where: { $0.kind == .dose && !$0.isDone }) {
                    complete(item)
                }
            }
        case .walk:
            return .init(название: "Открыть", символ: "arrow.up.left.and.arrow.down.right") {
                route = .walk
            }
        default:
            return .init(название: isDogAlongside ? "Остановка" : "Просится",
                         символ: isDogAlongside ? "car" : "pawprint") {
                route = isDogAlongside ? .walk : .needs
            }
        }
    }

    /// Второй путь — тоже нормальный, но не основной.
    private var второеДействие: TodayBottomBar.Действие? {
        switch состояниеВерхнее {
        case .alarm, .threshold:
            return .init(название: "Что сказать", символ: "doc.text") {
                if let threshold = AlarmThresholdAnalyzer.evaluate(events: events, now: now) {
                    alarm = threshold
                }
            }
        case .dose:
            // «Беру на себя» — защита между людьми: чтобы двое не дали
            // дозу дважды. Механика живёт в модели, и её надо звать.
            guard let доза = overdueDose, !доза.claimIsActive(at: now) else { return nil }
            return .init(название: "Беру на себя", символ: "hand.raised") {
                claim(доза)
            }
        case .walk:
            return .init(название: "Пописал", символ: "drop") { route = .walk }
        default:
            return .init(название: "Гулять", символ: "figure.walk") { route = .walk }
        }
    }

    // MARK: Строка «Дальше» и компактная строка

    /// «Дальше · через 2 ч 6» и под ней — что именно.
    ///
    /// **Строки две, и вторая красится тоном ВТОРОГО состояния** —
    /// так на кадрах: на 01 «Доза 0,1 мг в 20:00» белым, на 02
    /// «Не кормить до 18:29» янтарём. README про второй цвет молчит
    /// и говорит про одну строку 17 semibold.
    @ViewBuilder
    private var строкаДальше: some View {
        if let второе = TodayStateRouter.second(состояниеПоказания) {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("Дальше")
                    .textStyle(AppFont.caption, color: Token.Ink.secondary)
                Text(подписьСостояния(второе))
                    .textStyle(AppFont.bodyEmphasis, color: цветВторого(второе))
                    .wraps()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// Чем называется состояние в строке «Дальше».
    private func подписьСостояния(_ состояние: TodayState) -> LocalizedStringKey {
        switch состояние {
        case .dose:
            if let доза = overdueDose {
                return .готовая(String(localized: "Доза в \(Fmt.clock(доза.scheduledAt))"))
            }
            return "Доза по часам"
        case .fasting:
            if let окно = fastingWindow {
                return .готовая(String(localized: "Не кормить до \(Fmt.clock(окно.freeAt))"))
            }
            return "Натощак"
        case .alarm, .threshold: return "Похоже, пора звонить"
        case .episode: return "Наблюдаем"
        case .trip: return "Поездка"
        case .sitter: return "Ситтер"
        case .away: return "Со мной весь день"
        case .stock: return "Запас кончается"
        case .offline: return "Дневник не доехал"
        case .walk: return "На улице"
        case .first: return "Первый день"
        case .silence: return "Давно не выходили"
        case .night: return "Тихие часы"
        case .normal: return "Обычный день"
        }
    }

    /// Цвет второй строки — тон ВТОРОГО состояния, а не экрана.
    private func цветВторого(_ состояние: TodayState) -> Color {
        switch состояние.tone {
        case .fasting: Token.Status.waitingText
        case .dose: Token.Action.primary
        case .alarm: Token.Status.overdueText
        case .normal, .night, .walk: Token.Ink.primary
        }
    }

    /// Компактная строка «время · дальше» — появляется за 120 pt
    /// прокрутки, когда шапка уже уехала наверх.
    private var компактнаяСтрока: some View {
        HStack(spacing: Token.Space.s8) {
            Text(Fmt.clock(now))
                .textStyle(AppFont.captionEmphasis, color: Token.Ink.primary)
            if let второе = TodayStateRouter.second(состояниеПоказания) {
                Text(verbatim: "·").foregroundStyle(Token.Ink.secondary)
                Text(подписьСостояния(второе))
                    .textStyle(AppFont.caption, color: Token.Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Token.Space.s8)
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .frame(minHeight: Token.Size.tapTarget)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .accessibilityIdentifier("компактная-строка")
    }

    /// Шапка панели: кличка, «вес · дежурит» и единственная кнопка «…».
    private var шапкаПанели: ШапкаПанели {
        ШапкаПанели(dog: dog,
                    duty: dutyMember,
                    день: показатьДругойДень ? экранДень : nil,
                    листать: { шаг in показанныйДень = экранДень.сдвинуть(на: шаг).начало },
                    настройки: { показатьНастройки = true },
                    другойДень: { показатьДругойДень.toggle() })
    }

    private var плакат: some View {
        ReadingPanel(tone: тонЭкрана,
                     чип: чипСостояния,
                     пилюля: пилюляЗаголовка,
                     показание: показаниеПанели,
                     откуда: откудаСчитаем,
                     докуда: докудаСчитаем,
                     доля: доляРитма) {
            шапкаПанели
        }
        // Опознаётся приёмкой, чтобы точку замера брать по РАМКЕ блока,
        // а не по доле экрана.
        //
        // **Доля экрана уже промахнулась.** Первая редакция приёмки
        // мерила точку на 92 % ширины и 9 % высоты — и попадала
        // в шестерёнку настроек, акцентную и светлую. Три сценария дали
        // `#96B2EC`, `#96B2EC`, `#9BBAF5`: два совпали, тест покраснел,
        // и покраснел он **правдиво про замер и ложно про плакат**.
        //
        // > Координата, посчитанная от края экрана, измеряет экран.
        // > Рамка элемента измеряет элемент.
        //
        // `children: .contain` — дети остаются доступными: внутри блока
        // живёт шапка с кнопками листания дня, и `.combine` отняло бы
        // у них и нажатие, и голос.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("плакат-главный")
    }

    // Свойство `header` снято 22.10.2026: его единственным читателем
    // был `TGPoster`, а шапка панели несёт теперь ещё и кнопку «…».
    // Её тип — `ШапкаПанели`, объявлен внизу файла.

    /// Сколько собака дома прямо сейчас.
    private var timeIndoors: TimeInterval? {
        TimelineBuilder.timeIndoorsNow(TimelineBuilder.blocks(Diary.active(events)),
                                       now: now, threshold: 0)
    }

    /// Конец последнего записанного выхода. Герою нужен, чтобы за потолком
    /// тишины сказать «записей нет с такого-то», а не печатать число часов,
    /// которое отвечает уже не на тот вопрос.
    private var lastOutingEndedAt: Date? {
        TimelineBuilder.blocks(Diary.active(events)).last(where: \.isOuting)?.endedAt
    }

    /// Сколько раз сегодня выходили. Правило — в
    /// `TimelineBuilder.outingsCount`: вторая копия этого счёта стояла
    /// в карточке сводки и давала на том же экране другое число.
    private var outingsToday: Int {
        TimelineBuilder.outingsCount(events, on: отсчёт)
    }

    /// Какие удалённые записи ещё можно вернуть.
    ///
    /// Зачёркнутая строка в ленте — это не память об удалении, а вторая
    /// половина кнопки «Отменить». Уехал тост — ушла и строка.
    private var undoableDeletions: Set<UUID> {
        if case .restoreDeleted(let ids) = appState.undo?.action { return Set(ids) }
        return []
    }

    private var summaryStrip: some View {
        TodaySummaryStrip(summary: Diary.summary(events, day: отсчёт, dog: dog),
                          outings: outingsToday)
    }

    // MARK: Данные экрана

    /// Окно натощак — единственное, что имеет право стоять выше всего
    /// на экране.
    ///
    /// Считается тем же `FeedingGate`, что и на экране питания. Раньше
    /// здесь был свой расчёт, `DoseScheduler.fastingEnds`, и он знал
    /// только окно ПОСЛЕ отметки приёма. Значит окно ДО дозы — то самое,
    /// ради которого эутирокс и дают натощак, — на главном экране
    /// не показывалось вовсе, и сдвиг часа приёма на нём ничего не менял.
    /// Два расчёта одного правила расходятся молча: проверять один
    /// наблюдениями за другим нельзя.
    private var fastingWindow: FeedingGate.Block? {
        guard let dog, dog.isOnTreatment else { return nil }
        return FeedingGate.block(for: dog.medications, now: now)
    }

    /// Выбор вынесен в `DoseScheduler.overdue` — здесь остались только
    /// права и наличие курса. Пока он жил тут, проверить его было нечем:
    /// приватное свойство вью тестом не достать, и баннер «Доза 21:30
    /// не отмечена» вставал насовсем, потому что перебирались дозы всех
    /// прошлых дней.
    private var overdueDose: DoseRecord? {
        guard let dog, dog.isOnTreatment, appState.can(.seeMedical) else { return nil }
        return DoseScheduler.alarmingDose(among: dog.medications, now: now)
    }

    /// Почему нельзя — словами. «Нельзя» без причины человек выполнит
    /// один раз, а на второй обойдёт.
    private func подписьОкна(_ block: FeedingGate.Block) -> String {
        switch block {
        case .before(let лекарство, let doseAt):
            String(localized: "\(лекарство) в \(Fmt.clock(doseAt)) — натощак · видят все")
        case .after(let лекарство, let givenAt, _):
            String(localized: "после \(лекарство) в \(Fmt.clock(givenAt)) · видят все")
        }
    }

    /// Груминг и вес живут в профиле и всплывают на главном только когда подошёл срок.
    /// На главном показываем только то, что правда просится сегодня.
    /// «Через 30 дней» — это не дело на сегодня, это шум.
    /// Сколько дел ухода заведено, но не может напомнить.
    private var careAwaitingDate: Int {
        dog?.careTasks.filter(\.needsDate).count ?? 0
    }

    private var planItems: [DayPlanItem] {
        DayPlanBuilder.items(dog: dog, events: events, now: отсчёт,
                             seesMedical: appState.can(.seeMedical))
    }

    /// «Беру на себя» с запасом в 45 минут — чтобы двое не дали дозу дважды.
    ///
    /// Механика была написана в модели и не вызывалась ниоткуда: то есть
    /// защита между людьми не работала совсем.
    private func claim(_ dose: DoseRecord) { actions.claim(dose) }

    private func claimSubtitle(_ dose: DoseRecord) -> String {
        if dose.claimIsActive(at: now), let who = dose.claimedBy {
            let осталось = DoseRecord.claimTTL - now.timeIntervalSince(dose.claimedAt ?? now)
            return String(localized: "\(who) взяла на себя · \(Fmt.duration(осталось)) осталось")
        }
        return dutyMember.map { String(localized: "Сегодня дежурит \($0.name)") } ?? String(localized: "Кто-то один — отметьте")
    }

    /// Вернуть пункт в невыполненные.
    ///
    /// Отметить не то — обычное дело: сработал свайп, покормила не она,
    /// доза оказалась другой. Раньше отменить это можно было только
    /// найдя запись в ленте и удалив её оттуда — то есть догадавшись,
    /// что «сделано» в режиме дня и запись в ленте это одно и то же.
    /// Какой записью в ленте отмечается пункт плана.
    /// Всё, что план дня делает с хранилищем, живёт в `DayPlanActions`.
    /// Вынесено 28.09: внутри `View` эти двести пятьдесят строк нельзя
    /// было позвать из теста вовсе — чтобы дойти до `complete`, надо
    /// построить экран с `@Query`, `AppState` и хранилищем.
    private var actions: DayPlanActions {
        DayPlanActions(context: context, appState: appState, settings: settings,
                       dog: dog, день: отсчёт, сейчас: now, careUndo: $lastCareDone)
    }

    private func logKind(of item: DayPlanItem) -> LogKind { actions.logKind(of: item) }

    /// Закрыть выход.
    ///
    /// В тихие часы результат не спрашиваем — это обещание из настроек,
    /// и до сих пор оно не выполнялось: шторка «Как сходил?» открывалась
    /// в три часа ночи наравне с днём. Выход закрывается молча, запись
    /// остаётся без результата, а день соберёт утреннюю сводку.
    private func endOuting() {
        guard !settings.isQuietHour(now) else {
            // В журнале это должно быть видно отдельно от «пропустил»:
            // человек ничего не пропускал, его просто не спросили.
            UsageLog.note(.record, "outcome", outcome: .empty)
            OutingFinisher.finish(outcome: nil, dog: dog, appState: appState, context: context)
            return
        }
        route = .walkResult
    }

    private func uncomplete(_ item: DayPlanItem) { actions.uncomplete(item) }

    /// Тап по тексту строки: открыть запись, а не отметить.
    ///
    /// Повторный тап по **кругу** уже закрытой дозы открывает замок —
    /// он объясняет, кто дал и когда, вместо второй отметки.
    private func open(_ item: DayPlanItem) {
        // Доза ждёт таймера от еды — объясняем, чего ждём.
        if item.kind == .dose, !item.gate.isOpen, let medication = item.medication {
            gatedDose = GatedDose(item: item, medication: medication)
            return
        }

        // Доза просрочена и не отмечена — предлагаем три выхода
        // без единого упрёка.
        if item.kind == .dose, !item.isDone, let medication = item.medication,
           let missed = MissedDoseAdvisor.evaluate(medication: medication,
                                                   scheduledAt: item.time, now: now) {
            missedDose = MissedDoseTarget(item: item, medication: medication, missed: missed)
            return
        }

        guard item.isDone else { return }
        if item.kind == .dose, let medication = item.medication,
           let dose = medication.doses.first(where: {
               Calendar.current.isDate($0.scheduledAt, equalTo: item.time, toGranularity: .minute)
           }), dose.isGiven {
            lockedDose = LockedDose(item: item, givenBy: dose.givenBy ?? "кто-то",
                                    givenAt: dose.givenAt ?? item.time)
            return
        }
        // Остальное открывается своей записью в ленте.
        if let event = Diary.onDay(events, отсчёт)
            .filter({ $0.kind == logKind(of: item) })
            .min(by: { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }) {
            route = .edit(event.id)
        }
    }

    /// Отметить дозу пропущенной.
    ///
    /// Пропуск записывается, а не просто исчезает: врач спросит именно
    /// про него, а в истории иначе останется необъяснённая дыра.
    private func skipDose(_ target: MissedDoseTarget) { actions.skipDose(target) }

    /// Тап по пункту плана. Опоздали — спрашиваем, когда дали; успели —
    /// записываем в один тап, как было.
    ///
    /// Права проверяются **до** шторки, а не после: спросить «когда дали»
    /// и на «Записать» ответить «тебе не разрешено» — это заставить
    /// человека сделать работу, которую всё равно выбросят.
    private func complete(_ item: DayPlanItem) {
        guard actions.checkPermission(for: item) else { return }
        // В прошлом дне «сейчас» не существует, и записывать им нельзя:
        // листая вчера, человек записал бы сегодняшний час во вчерашнюю
        // еду. У ухода часа нет вовсе — он ложится концом показанных
        // суток, и это честнее выдуманного времени.
        guard item.kind != .care,
              LateMarking.asksWhenGiven(scheduled: item.time, now: отсчёт,
                                        hasTime: item.showsTime) else {
            complete(item, givenAt: экранДень.моментБыстройЗаписи ?? отсчёт)
            return
        }
        askingGivenAt = item
    }

    private func complete(_ item: DayPlanItem, givenAt момент: Date) {
        actions.complete(item, givenAt: момент)
    }
}



// `DogAvatar` переехал в `TodayHeader.swift` — туда, где его и рисуют.

/// Шапка панели показания: кличка, «вес · дежурит», кнопка «…».
///
/// Отдельный тип, а не замыкание внутри экрана, по той же причине,
/// по которой 28.09 вынесли `TodayHeader`: вью внутри вью нельзя
/// ни собрать в превью, ни снять кадром, а у Togo записано, что
/// поверхность, которую нельзя снять кадром, никто не проверял.
///
/// Листалку дня держит **`TodayHeader`**, и она показывается только
/// когда её попросили пунктом «Другой день»: на кадре 01 в шапке её
/// нет. Убрать совсем было нельзя — это единственный путь записать
/// вчерашнее.
struct ШапкаПанели: View {
    let dog: Dog?
    let duty: FamilyMember?
    var день: ScreenDay?
    var листать: (Int) -> Void = { _ in }
    var настройки: () -> Void = {}
    var другойДень: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s8) {
            TodayHeader(dog: dog, duty: duty, день: день, листать: листать)
            // Единственная кнопка шапки. «Семья» сюда не кладётся:
            // по хендоффу она пункт меню ВКЛАДКИ СОБАКИ, а не
            // «Сегодня».
            HeaderMenu(настройки: настройки, другойДень: другойДень)
        }
    }
}
