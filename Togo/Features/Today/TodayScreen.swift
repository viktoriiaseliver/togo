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

    var body: some View {
        NavigationStack {
            ZStack {
                Token.Surface.screen.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                        header

                        if Persistence.isEphemeral {
                            TGBanner(
                                tone: .alarm,
                                title: "Записи сейчас не сохраняются",
                                subtitle: "Дневник не смог открыть своё хранилище и работает во временном режиме. Всё, что запишешь, пропадёт при перезапуске. Перезапусти приложение; если не поможет — напиши в поддержку, старые записи никуда не делись.",
                                systemImage: "externaldrive.badge.exclamationmark"
                            )
                        }

                        if let fasting = fastingWindow {
                            TGBanner(
                                tone: .waiting,
                                title: "Не кормить \(Fmt.duration(fasting.remaining))",
                                subtitle: "после \(fasting.medication) в \(Fmt.clock(fasting.doseAt)) · видят все",
                                systemImage: "clock.badge.exclamationmark"
                            )
                        }

                        if let overdue = overdueDose {
                            VStack(alignment: .leading, spacing: Token.Space.s8) {
                                TGBanner(
                                    tone: .alarm,
                                    title: "Доза \(Fmt.clock(overdue.scheduledAt)) не отмечена",
                                    subtitle: claimSubtitle(overdue),
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

                        if let trip = activeTrip {
                            TripTodayBlock(trip: trip, dog: dog, now: now)
                            summaryStrip
                        }

                        if let day = activeDayOut {
                            DayOutCard(day: day, now: now, lastWater: lastWaterOffer) {
                                lastWaterOffer = Date()
                                Haptics.tap()
                            } onFinish: {
                                // День закрываем сразу: иначе итог считался бы
                                // от «сейчас» и рос, пока человек его читает.
                                day.endedAt = Date()
                                try? context.save()
                                finishingDayOut = day
                            }
                        }

                        if let session = appState.session {
                            ActiveSessionCard(
                                session: session,
                                now: now,
                                onOpen: { route = session.kind == .walk ? .walk : .walkResult },
                                onFinish: { route = .walkResult }
                            )
                        }

                        DayTimeline(events: Diary.onDay(events, now), now: now,
                                    showsAuthor: members.count > 1) { event in
                            route = .edit(event.id)
                        }

                        if activeTrip == nil { summaryStrip }

                        // Единственная запись, которая меняет поведение,
                        // а не фиксирует его. Показывается, только когда
                        // сигналов набралось достаточно.
                        AskSignalCard(events: events, dogName: dog?.name ?? "Он", now: now)

                        DayPlanList(items: planItems, now: now,
                                    onComplete: { complete($0) },
                                    onUndo: { uncomplete($0) },
                                    awaitingDate: careAwaitingDate,
                                    onOpenCare: onOpenDog)
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
            .toolbar { SettingsToolbarItem() }
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
            .onChange(of: episodes.count) { _, _ in
                appState.refreshEpisode(from: episodes, at: now)
            }
            .sheet(item: $route) { route in
                TodayRouter(route: route, dog: dog, now: now, onOpenDog: onOpenDog)
            }
            .sheet(item: $finishingDayOut) { day in
                DayOutSummarySheet(day: day)
            }
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 12) {
            DogAvatar(dog: dog)
            VStack(alignment: .leading, spacing: 2) {
                Text(dog?.name ?? "Собака").textStyle(AppFont.cardTitle).foregroundStyle(Token.Ink.primary)
                // Самый частый вопрос — «давно ли гуляли». Раньше ответ
                // лежал внизу ленты, под всеми записями дня: чтобы его
                // увидеть, надо было прокрутить экран целиком.
                Text(sinceWalkLine)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .wraps()
            }
            Spacer()
            if let duty = dutyMember {
                HStack(spacing: 6) {
                    Text("дежурит \(duty.name)").textStyle(AppFont.micro).foregroundStyle(Token.Ink.secondary)
                    TGAvatar(initial: duty.initial, tint: Token.Action.done)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Сколько прошло с последнего выхода — или что он идёт прямо сейчас.
    private var sinceWalkLine: String {
        let weight = dog.map { Fmt.weight($0.weightKg) } ?? "—"
        if let session = appState.session {
            return weight + " · " + (session.isPaused ? "выход на паузе" : "гуляете сейчас")
        }
        let blocks = TimelineBuilder.blocks(Diary.active(events))
        guard let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: now, threshold: 0) else {
            return weight + " · сегодня ещё не выходили"
        }
        return weight + " · гуляли \(Fmt.gap(indoors)) назад"
    }

    private var summaryStrip: some View {
        let summary = Diary.summary(events, day: now, dog: dog)
        let blocks = TimelineBuilder.blocks(Diary.active(events))
        let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: now, threshold: 0)
        return TGCard {
            HStack(alignment: .top, spacing: 0) {
                TGStat(value: "\(summary.eatenGrams) г",
                            caption: summary.dailyGrams > 0 ? "из \(summary.dailyGrams) съел" : "съел")
                // Здесь стояло «выпил N мл». Ввод воды убран — записывать
                // миллилитры было нечем, — и показатель навсегда застыл
                // на нуле. На его месте то, ради чего в сводку и смотрят.
                TGStat(value: indoors.map(Fmt.gap) ?? "—", caption: "с прогулки")
                TGStat(value: "\(summary.outings)", caption: Fmt.outings(summary.outings).replacingOccurrences(of: "\(summary.outings) ", with: ""))
            }
            if summary.trainingGrams > 0 {
                TGDivider()
                TGExplainer(text: "\(summary.trainingGrams) г ушло на занятие — вечерняя порция уже уменьшена.")
            }
        }
    }

    // MARK: Данные экрана

    private struct FastingWindow {
        var remaining: TimeInterval
        var medication: String
        var doseAt: Date
    }

    /// Окно натощак — единственное, что имеет право стоять выше всего
    /// на экране. Считается от фактической отметки приёма.
    private var fastingWindow: FastingWindow? {
        guard let dog, let window = DoseScheduler.fastingEnds(for: dog, at: now) else { return nil }
        return FastingWindow(remaining: window.until.timeIntervalSince(now),
                             medication: window.medication,
                             doseAt: window.givenAt)
    }

    private var overdueDose: DoseRecord? {
        guard let dog, dog.isOnTreatment, appState.can(.seeMedical) else { return nil }
        return dog.medications
            .flatMap(\.doses)
            .filter { $0.escalationStage(at: now) >= 2 }
            .min { $0.scheduledAt < $1.scheduledAt }
    }

    /// Груминг и вес живут в профиле и всплывают на главном только когда подошёл срок.
    /// На главном показываем только то, что правда просится сегодня.
    /// «Через 30 дней» — это не дело на сегодня, это шум.
    /// Сколько дел ухода заведено, но не может напомнить.
    private var careAwaitingDate: Int {
        dog?.careTasks.filter(\.needsDate).count ?? 0
    }

    private var planItems: [DayPlanItem] {
        guard let dog else { return [] }
        var items: [DayPlanItem] = []
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let doneMealTimes = Diary.onDay(events, now).filter { $0.kind == .meal }.map(\.date)

        // Каждая запись закрывает ровно один пункт — ближайший к себе.
        let mealMinutes = dog.mealTimes.sorted()
        let mealDone = MealSchedule.matchDone(planned: mealMinutes, logged: doneMealTimes,
                                              startOfDay: startOfDay)
        for (index, minute) in mealMinutes.enumerated() {
            let at = startOfDay.addingTimeInterval(Double(minute) * 60)
            items.append(DayPlanItem(id: "meal-\(minute)", time: at,
                                     title: "Еда · \(dog.servingGrams) г",
                                     hint: dog.foodBrand, kind: .meal, isDone: mealDone[index]))
        }
        // Уход — такой же пункт дня, как еда и доза. Отдельной карточкой
        // он говорил, что надо сделать, но сделать оттуда было нельзя:
        // тап уводил на вкладку собаки, где дело приходилось искать
        // руками. Пять шагов на действие в одну секунду.
        for task in dog.careTasks where task.isDue(on: now) {
            items.append(DayPlanItem(
                id: "care-\(task.id)",
                // Уход ставим в конец дня: у него нет часа, и он не должен
                // мешаться между кормлениями.
                time: startOfDay.addingTimeInterval(Double(dog.sleepMinuteOfDay) * 60),
                title: task.title,
                hint: task.detail.isEmpty ? nil : task.detail,
                kind: .care,
                isDone: task.isDoneToday(on: now),
                careTask: task,
                showsTime: false
            ))
        }

        if dog.isOnTreatment, appState.can(.seeMedical) {
            for medication in dog.medications where !medication.isPaused {
                for minute in medication.times.sorted() {
                    let at = startOfDay.addingTimeInterval(Double(minute) * 60)
                    let done = medication.doses.contains { $0.isGiven && cal.isDate($0.scheduledAt, equalTo: at, toGranularity: .minute) }
                    items.append(DayPlanItem(id: "dose-\(medication.id)-\(minute)", time: at,
                                             title: "\(medication.name) · \(medication.doseText)",
                                             hint: medication.fastingMinutes > 0 ? "натощак \(medication.fastingMinutes) мин" : nil,
                                             kind: .dose, isDone: done,
                                             medication: medication))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    /// «Беру на себя» с запасом в 45 минут — чтобы двое не дали дозу дважды.
    ///
    /// Механика была написана в модели и не вызывалась ниоткуда: то есть
    /// защита между людьми не работала совсем.
    private func claim(_ dose: DoseRecord) {
        guard appState.can(.giveDose) else { return }
        dose.claimedBy = appState.currentUserName
        dose.claimedAt = now
        try? context.save()
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

    private func uncomplete(_ item: DayPlanItem) {
        guard let dog else { return }

        // Убираем ту запись, которая этот пункт и закрыла, — ближайшую
        // к его времени.
        let kind = logKind(of: item)
        let candidates = Diary.onDay(events, now)
            .filter { $0.kind == kind }
            .sorted { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }

        // У ухода часа нет, и сверять с ним нечего: убираем сегодняшнюю
        // запись про это же дело.
        if item.kind == .care {
            candidates.first { $0.careTaskID == item.careTask?.id }.map { event in
                event.deletedAt = Date()
                event.deletedBy = appState.currentUserName
            }
            if let task = item.careTask {
                task.undoDone(previousDone: lastCareDone[task.id] ?? nil)
            }
        } else if let event = candidates.first,
                  abs(event.date.timeIntervalSince(item.time)) <= MealSchedule.doneTolerance {
            event.deletedAt = Date()
            event.deletedBy = appState.currentUserName
        }

        // Доза — не только запись в ленте: от неё считается окно натощак
        // и защита от второй дозы.
        if item.kind == .dose, let medication = item.medication {
            DoseScheduler.unmark(medication, scheduledAt: item.time, context: context)
        }

        try? context.save()
        Haptics.warning()
        appState.showUndo("Снова в списке · \(item.title)")
        _ = dog
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
        EventLog(context: context, appState: appState)
            .record(logKind(of: item),
                    dog: dog,
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
            lastCareDone[task.id] = task.lastDone
            task.markDone(at: now)
            try? context.save()
        }

        // Отметка приёма — не то же самое, что запись в ленте: от неё
        // считается окно натощак и на неё смотрит защита от двойной дозы.
        if item.kind == .dose, let medication = item.medication {
            if let dose = DoseScheduler.markGiven(medication, scheduledAt: item.time,
                                                  by: appState.currentUserName, at: now,
                                                  context: context) {
                // Отметили — значит, догонять уже не надо.
                ReminderScheduler.cancelDose(dose)
            }
            Task { await ReminderScheduler.refresh(dog: dog, settings: settings, at: now) }
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
            tint: Token.Action.primaryQuiet
        )
    }
}
