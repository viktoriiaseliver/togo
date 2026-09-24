import SwiftUI
import SwiftData

/// Главный экран. Порядок блоков: натощак → уход, если есть срок → таймлайн → режим дня.
/// В поездке между натощак и таймлайном встаёт блок дороги, а сводка «ел и пил»
/// поднимается выше таймлайна.
struct TodayScreen: View {
    /// Куда уводить, когда речь про собаку целиком: вкладка, а не шторка.
    var onOpenDog: () -> Void = {}

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
    /// Когда в последний раз предлагали воду в режиме «собака со мной».
    @State private var lastWaterOffer: Date?
    /// Когда дело ухода было сделано в прошлый раз — чтобы «вернуть»
    /// возвращало именно туда, а не обнуляло срок.
    @State private var lastCareDone: [UUID: Date?] = [:]
    @State private var lockedDose: LockedDose?
    @State private var missedDose: MissedDoseTarget?
    @State private var gatedDose: GatedDose?
    @State private var alarm: AlarmThreshold?

    /// Просроченная доза, по которой открыт разбор.
    struct MissedDoseTarget: Identifiable {
        let item: DayPlanItem
        let medication: Medication
        let missed: MissedDose
        var id: String { item.id }
    }

    /// Доза, которая ждёт таймера от еды.
    struct GatedDose: Identifiable {
        let item: DayPlanItem
        let medication: Medication
        var id: String { item.id }
    }

    /// Доза, по которой открыт замок.
    struct LockedDose: Identifiable {
        let item: DayPlanItem
        let givenBy: String
        let givenAt: Date
        var id: String { item.id }
    }

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
            systemImage: "pawprint",
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
                    Token.Surface.screen.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                            if dog == nil { нетСобаки }
                            header
                            тревоги
                            происходящее
                            деньПозади
                            планНаОстаток
                        }
                        .padding(.horizontal, Token.Spacing.screenPadding)
                        .padding(.bottom, 24)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ActionGrid(
                        portionGrams: dog?.servingGrams ?? 0,
                        isTravelling: isDogAlongside,
                        canWriteMedical: appState.can(.seeMedical)
                    ) { route = $0 }
                }
                .navigationBarTitleDisplayMode(.inline)
                .usageScreen(.today)
                .toolbar { SettingsToolbarItem() }
            ))
        }
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

        TodayHero(indoors: timeIndoors,
                  lastOutingEndedAt: lastOutingEndedAt,
                  session: appState.session,
                  now: now,
                  rhythm: WalkRhythmAnalyzer.rhythm(events: events, now: now),
                  outingsToday: outingsToday)

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
        DayTimeline(events: Diary.onDayWithTraces(events, now, tracing: undoableDeletions),
                    now: now,
                    showsAuthor: members.count > 1) { event in
            route = .edit(event.id)
        }

        // В поездке сводка уже показана выше, рядом с блоком поездки.
        if activeTrip == nil { summaryStrip }

        // Единственная запись, которая меняет поведение, а не фиксирует
        // его. Показывается, только когда сигналов набралось достаточно.
        AskSignalCard(events: events, dogName: dog?.name ?? "Он", now: now)
    }

    private var планНаОстаток: some View {
        DayPlanList(items: planItems, now: now,
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
            appState.showUndo("День не закрылся · нажми ещё раз")
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
            .sheet(item: $finishingDayOut) { day in
                DayOutSummarySheet(day: day)
            }
            .sheet(item: $missedDose) { target in
                MissedDoseSheet(medication: target.medication, missed: target.missed, now: now) {
                    complete(target.item)
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

    private var header: some View {
        HStack(spacing: 12) {
            DogAvatar(dog: dog)
            VStack(alignment: .leading, spacing: 2) {
                Text(dog?.name ?? "Собака").textStyle(AppFont.cardTitle).foregroundStyle(Token.Ink.primary)
                // В шапке — только то, что не меняется в течение дня.
                // «Давно ли гуляли» переехало в героя: это ответ на главный
                // вопрос, и мелкой строкой рядом с весом он не читался.
                Text(identityLine)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Token.Space.s8)
            // Имя дежурного стоит строкой слева: подпись справа
            // повторяла его слово в слово.
            if let duty = dutyMember {
                TGAvatar(initial: duty.initial, tint: Token.Action.doneQuiet)
            }
        }
        .padding(.top, 4)
    }

    /// Вес и дежурный: две вещи, которые за день не меняются.
    private var identityLine: String {
        let weight = dog.map { Fmt.weight($0.weightKg) } ?? "—"
        guard let duty = dutyMember else { return weight }
        return weight + " · дежурит " + duty.name
    }

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

    /// Сколько раз сегодня выходили. Отметки внутри прогулки —
    /// не отдельные выходы.
    private var outingsToday: Int {
        TimelineBuilder.blocks(Diary.onDay(events, now)).filter(\.isOuting).count
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
        let summary = Diary.summary(events, day: now, dog: dog)
        let blocks = TimelineBuilder.blocks(Diary.active(events))
        let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: now, threshold: 0)
        return TGCard {
            HStack(alignment: .top, spacing: 0) {
                TGStat(value: "\(summary.eatenGrams) г",
                            caption: summary.dailyGrams > 0 ? "из \(summary.dailyGrams) съел" : "съел")
                // «С прогулки» отсюда убрано: на этот вопрос отвечает
                // герой вверху экрана крупной цифрой, и повторять его
                // мелким шрифтом — ровно тот дубль, который аудит
                // и просил вычистить.
                TGStat(value: "\(summary.meals)", caption: .готовая(String(localized: "\(summary.meals) кормлений").replacingOccurrences(of: "\(summary.meals) ", with: "")))
                TGStat(value: "\(summary.outings)", caption: .готовая(Fmt.outings(summary.outings).replacingOccurrences(of: "\(summary.outings) ", with: "")))
            }
            if summary.trainingGrams > 0 {
                TGDivider()
                TGExplainer(text: "\(summary.trainingGrams) г ушло на занятие — вечерняя порция уже уменьшена.")
            }
        }
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
        DayPlanBuilder.items(dog: dog, events: events, now: now,
                             seesMedical: appState.can(.seeMedical))
    }

    /// «Беру на себя» с запасом в 45 минут — чтобы двое не дали дозу дважды.
    ///
    /// Механика была написана в модели и не вызывалась ниоткуда: то есть
    /// защита между людьми не работала совсем.
    private func claim(_ dose: DoseRecord) {
        guard appState.can(.giveDose) else { return }
        let было = (dose.claimedBy, dose.claimedAt)
        dose.claimedBy = appState.currentUserName
        dose.claimedAt = now
        // Та же пара, что и у отметки приёма: договорённость видна только
        // через хранилище. Не сохранилась — второй человек её не увидит
        // и даст дозу, а первый уверен, что взял её на себя.
        do {
            try context.save()
        } catch {
            (dose.claimedBy, dose.claimedAt) = было
            Haptics.warning()
            appState.showUndo("Не получилось взять на себя · нажми ещё раз")
            return
        }
        Haptics.tap()
        appState.showUndo("Доза за тобой · 45 минут")
    }

    private func claimSubtitle(_ dose: DoseRecord) -> String {
        if dose.claimIsActive(at: now), let who = dose.claimedBy {
            let осталось = DoseRecord.claimTTL - now.timeIntervalSince(dose.claimedAt ?? now)
            return "\(who) взяла на себя · \(Fmt.duration(осталось)) осталось"
        }
        return dutyMember.map { "Сегодня дежурит \($0.name)" } ?? "Кто-то один — отметьте"
    }

    /// Вернуть пункт в невыполненные.
    ///
    /// Отметить не то — обычное дело: сработал свайп, покормила не она,
    /// доза оказалась другой. Раньше отменить это можно было только
    /// найдя запись в ленте и удалив её оттуда — то есть догадавшись,
    /// что «сделано» в режиме дня и запись в ленте это одно и то же.
    /// Какой записью в ленте отмечается пункт плана.
    private func logKind(of item: DayPlanItem) -> LogKind {
        switch item.kind {
        case .meal: .meal
        case .dose: .dose
        case .care: .care
        }
    }

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

    private func uncomplete(_ item: DayPlanItem) {
        guard let dog else { return }

        // Убираем ту запись, которая этот пункт и закрыла, — ближайшую
        // к его времени.
        let kind = logKind(of: item)
        let candidates = Diary.onDay(events, now)
            .filter { $0.kind == kind }
            .sorted { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }

        // Что вернуть, если сохранить не выйдет. `try?` здесь стоял ровно
        // перед тостом «Снова в списке»: не сохранилось — а человек уже
        // уверен, что отметку снял, и отмечает заново поверх.
        var вернуть: [() -> Void] = []

        // У ухода часа нет, и сверять с ним нечего: убираем сегодняшнюю
        // запись про это же дело.
        if item.kind == .care {
            candidates.first { $0.careTaskID == item.careTask?.id }.map { event in
                вернуть.append { event.deletedAt = nil; event.deletedBy = nil }
                event.deletedAt = Date()
                event.deletedBy = appState.currentUserName
            }
            if let task = item.careTask {
                let было = (task.lastDone, task.streak, task.scheduledDate)
                вернуть.append { (task.lastDone, task.streak, task.scheduledDate) = было }
                task.undoDone(previousDone: lastCareDone[task.id] ?? nil)
            }
        } else if let event = candidates.first,
                  abs(event.date.timeIntervalSince(item.time)) <= MealSchedule.doneTolerance {
            вернуть.append { event.deletedAt = nil; event.deletedBy = nil }
            event.deletedAt = Date()
            event.deletedBy = appState.currentUserName
        }

        // Доза — не только запись в ленте: от неё считается окно натощак
        // и защита от второй дозы. Сохранение у неё своё, внутри `unmark`.
        let получилось: Bool
        if item.kind == .dose, let medication = item.medication {
            получилось = DoseScheduler.unmark(medication, scheduledAt: item.time, context: context)
        } else {
            do { try context.save(); получилось = true } catch { получилось = false }
        }

        guard получилось else {
            вернуть.reversed().forEach { $0() }
            Haptics.warning()
            appState.showUndo("Не снялось · нажми ещё раз")
            return
        }

        Haptics.warning()
        appState.showUndo("Снова в списке · \(item.title)")
        _ = dog
    }

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
        if let event = Diary.onDay(events, now)
            .filter({ $0.kind == logKind(of: item) })
            .min(by: { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }) {
            route = .edit(event.id)
        }
    }

    /// Отметить дозу пропущенной.
    ///
    /// Пропуск записывается, а не просто исчезает: врач спросит именно
    /// про него, а в истории иначе останется необъяснённая дыра.
    private func skipDose(_ target: MissedDoseTarget) {
        guard DoseScheduler.markSkipped(target.medication, scheduledAt: target.item.time,
                                        by: appState.currentUserName, context: context) != nil else {
            // Пропуск заводили ради врача: «отмечено» без записи
            // в истории — та же необъяснённая дыра, только с алиби.
            Haptics.warning()
            appState.showUndo("Не записалось · нажми ещё раз")
            return
        }
        Haptics.warning()
        appState.showUndo("Доза отмечена пропущенной")
    }

    private func complete(_ item: DayPlanItem) {
        guard let dog else { return }
        // Права на бытовое и на дозы существовали, но не проверялись нигде:
        // выданная роль «только смотреть» всё равно позволяла отмечать еду,
        // а «нельзя давать препараты» — отмечать приёмы.
        let allowed: Permission = item.kind == .dose ? .giveDose : .logBasics
        guard appState.can(allowed) else {
            appState.showUndo(item.kind == .dose
                              ? "Дозы отмечает тот, кому это разрешено"
                              : "Записывать может тот, кому это разрешено")
            return
        }
        // Один поступок — один момент. Раньше их было два: лента писалась
        // свежим `.now` внутри `EventLog.record`, а отметка приёма —
        // экранным `now`, который тикает раз в 30 секунд и в фоне
        // не тикает вовсе. На границе минуты это расходилось на минуту:
        // 21.09.2026 баннер сказал «после Эутирокс в 14:03», а лента
        // в той же секунде — «Доза 14:04». Экранное `now` годится,
        // чтобы показывать, и не годится, чтобы записывать.
        let момент = Date()

        // Отметка приёма — не то же самое, что запись в ленте: от неё
        // считается окно натощак и на неё смотрит защита от двойной дозы.
        //
        // Она идёт **первой**, и это не косметика. Раньше порядок был
        // обратный: лента писала «Записано · Эутирокс», а отметка приёма
        // шла следом с `try?`. Если её сохранение не проходило, человек
        // видел подтверждение, лента подтверждала его же, а доза
        // оставалась неотмеченной — и напоминания на t+30 и t+60 уже
        // были сняты. Приложение выгружают, и о потере не узнаёт никто.
        // Вторая доза при этом даётся с полной уверенностью.
        //
        // Теперь пустой ответ останавливает всё: напоминания остаются,
        // в ленте не появляется ничего, а человек слышит тревогу.
        var отметка: DoseRecord?
        if item.kind == .dose, let medication = item.medication {
            guard let dose = DoseScheduler.markGiven(medication, scheduledAt: item.time,
                                                     by: appState.currentUserName, at: момент,
                                                     context: context) else {
                Haptics.warning()
                appState.showUndo("Доза не отметилась · нажми ещё раз")
                return
            }
            отметка = dose
        }

        EventLog(context: context, appState: appState)
            .record(logKind(of: item),
                    dog: dog,
                    at: момент,
                    confirmation: "Записано · \(item.title)") { event in
                switch item.kind {
                case .meal:
                    event.grams = dog.servingGrams
                    event.note = dog.foodBrand.isEmpty ? nil : dog.foodBrand
                case .care:
                    event.note = item.title
                    event.careTaskID = item.careTask?.id
                case .dose:
                    event.note = item.title
                    // Связь с препаратом писать было некому: поле в модели
                    // есть, а запись оставалась ничьей. Без неё из ленты
                    // не видно, какой именно препарат отметили, если
                    // название успели поменять.
                    event.medicationID = item.medication?.id
                }
            }

        // Уход — не только строка в ленте: от отметки считается,
        // когда дело понадобится в следующий раз.
        if item.kind == .care, let task = item.careTask {
            let было = (task.lastDone, task.streak, task.scheduledDate)
            lastCareDone[task.id] = task.lastDone
            task.markDone(at: момент)
            do {
                try context.save()
            } catch {
                // Запись в ленте уже легла — она сохранилась своим
                // сохранением выше. Не легло само «когда делали
                // в последний раз», а от него считается следующий срок.
                (task.lastDone, task.streak, task.scheduledDate) = было
                lastCareDone[task.id] = nil
                Haptics.warning()
                appState.showUndo("Срок не пересчитался · нажми ещё раз")
                return
            }
        }

        if let доза = отметка {
            // Отметка легла в хранилище — вот теперь догонять не надо.
            // Снимать напоминания раньше сохранения было бы тем же самым,
            // что и `try?`: уверенностью без основания.
            ReminderScheduler.cancelDose(доза)
            Task { await ReminderScheduler.refresh(dog: dog, settings: settings, at: момент) }
        }
    }
}



/// Аватар собаки — тот же `TGAvatar`, только крупнее и в тёплой заливке.
struct DogAvatar: View {
    let dog: Dog?

    var body: some View {
        TGAvatar(
            initial: dog?.initial ?? "?",
            image: dog?.photo,
            size: Token.Size.avatarMd,
            tint: Token.Action.doneQuiet
        )
    }
}
