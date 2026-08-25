import SwiftUI
import SwiftData

/// Главный экран. Порядок блоков: натощак → уход, если есть срок → таймлайн → режим дня.
/// В поездке между натощак и таймлайном встаёт блок дороги, а сводка «ел и пил»
/// поднимается выше таймлайна.
struct TodayScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(Settings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var dogs: [Dog]
    @Query private var members: [FamilyMember]
    @Query private var trips: [Trip]

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
                            TGBanner(
                                tone: .alarm,
                                title: "Доза \(Fmt.clock(overdue.scheduledAt)) не отмечена",
                                subtitle: dutyMember.map { "Сегодня дежурит \($0.name)" } ?? "Кто-то один — отметьте",
                                systemImage: "exclamationmark.triangle"
                            )
                        }

                        if let care = dueCare, !care.isEmpty {
                            CareRow(tasks: care) { route = .care }
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

                        DayTimeline(events: Diary.onDay(events, now), now: now) { event in
                            route = .edit(event.id)
                        }

                        if activeTrip == nil { summaryStrip }

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
                    portionGrams: dog?.portionGrams ?? 0,
                    isTravelling: activeTrip != nil,
                    canWriteMedical: appState.can(.seeMedical)
                ) { route = $0 }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsScreen() } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Настройки")
                    }
                }
            }
            .onReceive(tick) { date in
                now = date
                LiveActivityController.publishSnapshot(dog: dog, appState: appState, now: date)
            }
            .task { LiveActivityController.publishSnapshot(dog: dog, appState: appState, now: now) }
            .sheet(item: $route) { route in
                TodayRouter(route: route, dog: dog, now: now)
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

    /// Окно натощак — единственное, что имеет право стоять выше всего на экране.
    private var fastingWindow: FastingWindow? {
        guard let dog, dog.isOnTreatment else { return nil }
        for medication in dog.medications where medication.fastingMinutes > 0 && !medication.isPaused {
            guard let dose = medication.doses
                .filter({ $0.isGiven })
                .max(by: { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }),
                  let givenAt = dose.givenAt else { continue }
            let ends = givenAt.addingTimeInterval(Double(medication.fastingMinutes) * 60)
            if now < ends {
                return FastingWindow(remaining: ends.timeIntervalSince(now), medication: medication.name, doseAt: givenAt)
            }
        }
        return nil
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

        for minute in dog.mealTimes.sorted() {
            let at = startOfDay.addingTimeInterval(Double(minute) * 60)
            let done = doneMealTimes.contains { abs($0.timeIntervalSince(at)) < 90 * 60 }
            items.append(DayPlanItem(id: "meal-\(minute)", time: at, title: "Еда · \(dog.portionGrams) г",
                                     hint: dog.foodBrand, kind: .meal, isDone: done))
        }
        if dog.isOnTreatment, appState.can(.seeMedical) {
            for medication in dog.medications where !medication.isPaused {
                for minute in medication.times.sorted() {
                    let at = startOfDay.addingTimeInterval(Double(minute) * 60)
                    let done = medication.doses.contains { $0.isGiven && cal.isDate($0.scheduledAt, equalTo: at, toGranularity: .minute) }
                    items.append(DayPlanItem(id: "dose-\(medication.id)-\(minute)", time: at,
                                             title: "\(medication.name) · \(medication.doseText)",
                                             hint: medication.fastingMinutes > 0 ? "натощак \(medication.fastingMinutes) мин" : nil,
                                             kind: .dose, isDone: done))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    private func complete(_ item: DayPlanItem) {
        guard let dog else { return }
        EventLog(context: context, appState: appState)
            .record(item.kind == .meal ? .meal : .dose,
                    dog: dog,
                    confirmation: "Записано · \(item.title)") { event in
                switch item.kind {
                case .meal:
                    event.grams = dog.portionGrams
                    event.note = dog.foodBrand.isEmpty ? nil : dog.foodBrand
                case .dose:
                    event.note = item.title
                }
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
