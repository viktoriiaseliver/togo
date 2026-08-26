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

    @State private var route: TodayRoute?
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var dog: Dog? { dogs.first }
    private var events: [LogEvent] { dog?.events ?? [] }
    private var activeTrip: Trip? { trips.first { $0.isActive(on: now) } }
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

                        if let care = dueCare, !care.isEmpty {
                            CareRow(tasks: care) { onOpenDog() }
                        }

                        if let trip = activeTrip {
                            TripTodayBlock(trip: trip, dog: dog, now: now)
                            summaryStrip
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

                        DayPlanList(items: planItems, now: now) { item in
                            complete(item)
                        }
                    }
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .padding(.bottom, 24)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ActionGrid(
                    portionGrams: dog?.servingGrams ?? 0,
                    isTravelling: activeTrip != nil,
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
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 12) {
            DogAvatar(dog: dog)
            VStack(alignment: .leading, spacing: 2) {
                Text(dog?.name ?? "Собака").textStyle(AppFont.cardTitle).foregroundStyle(Token.Ink.primary)
                Text(dog.map { Fmt.weight($0.weightKg) } ?? "—")
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
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

    private var summaryStrip: some View {
        let summary = Diary.summary(events, day: now, dog: dog)
        return TGCard {
            HStack(alignment: .top, spacing: 0) {
                TGStat(value: "\(summary.eatenGrams) г",
                            caption: summary.dailyGrams > 0 ? "из \(summary.dailyGrams) съел" : "съел")
                TGStat(value: "\(summary.drankMl) мл", caption: "выпил")
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
    private var dueCare: [CareTask]? {
        guard let dog else { return nil }
        let due = dog.careTasks.filter { $0.isDue(on: now) }
        guard !due.isEmpty else { return nil }
        return Array(
            due.sorted { ($0.daysUntilDue(from: now) ?? 0) < ($1.daysUntilDue(from: now) ?? 0) }
                .prefix(3)
        )
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

    private func complete(_ item: DayPlanItem) {
        guard let dog else { return }
        EventLog(context: context, appState: appState)
            .record(item.kind == .meal ? .meal : .dose,
                    dog: dog,
                    confirmation: "Записано · \(item.title)") { event in
                switch item.kind {
                case .meal:
                    event.grams = dog.servingGrams
                    event.note = dog.foodBrand.isEmpty ? nil : dog.foodBrand
                case .dose:
                    event.note = item.title
                }
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
