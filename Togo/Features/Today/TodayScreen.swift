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

                        TodayHero(indoors: timeIndoors,
                                  session: appState.session,
                                  now: now,
                                  rhythm: WalkRhythmAnalyzer.rhythm(events: events, now: now),
                                  outingsToday: outingsToday)

                        // Порог тревоги: счёт дошёл сам, и человек должен
                        // увидеть это до того, как начнёт гадать в три часа
                        // ночи, «уже пора или ещё нет».
                        if let threshold = AlarmThresholdAnalyzer.evaluate(events: events, now: now) {
                            Button { alarm = threshold } label: {
                                TGBanner(tone: .alarm,
                                         title: "Похоже, пора звонить",
                                         subtitle: threshold.headline + " · есть готовый текст врачу",
                                         systemImage: "phone.badge.waveform")
                            }
                            .buttonStyle(.plain)
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
                                onOpen: { session.kind == .walk ? (route = .walk) : endOuting() },
                                onFinish: { endOuting() }
                            )
                        }

                        DayTimeline(events: Diary.onDayWithTraces(events, now, tracing: undoableDeletions),
                                    now: now,
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
                                    onOpen: { open($0) },
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
            .usageScreen(.today)
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
            .sheet(item: $missedDose) { target in
                MissedDoseSheet(medication: target.medication, missed: target.missed, now: now) {
                    complete(target.item)
                } onSkip: {
                    // Пропуск — тоже запись: иначе в истории останется
                    // дыра, а врач спросит именно про неё.
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
                TGStat(value: "\(summary.meals)", caption: Fmt.plural(summary.meals, "кормление", "кормления", "кормлений").replacingOccurrences(of: "\(summary.meals) ", with: ""))
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
        DayPlanBuilder.items(dog: dog, events: events, now: now,
                             seesMedical: appState.can(.seeMedical))
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

    /// Закрыть выход.
    ///
    /// В тихие часы результат не спрашиваем — это обещание из настроек,
    /// и до сих пор оно не выполнялось: шторка «Как сходил?» открывалась
    /// в три часа ночи наравне с днём. Выход закрывается молча, запись
    /// остаётся без результата, а день соберёт утренний бриф.
    private func endOuting() {
        guard !settings.isQuietHour(now) else {
            // В журнале это должно быть видно отдельно от «пропустил»:
            // человек ничего не пропускал, его просто не спросили.
            UsageLog.note(.record, "outcome", outcome: .empty)
            OutingFinisher.finish(outcome: nil, dog: dog, appState: appState)
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
        DoseScheduler.markSkipped(target.medication, scheduledAt: target.item.time,
                                  by: appState.currentUserName, context: context)
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
            tint: Token.Action.doneQuiet
        )
    }
}
