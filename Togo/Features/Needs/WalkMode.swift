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

    @State private var now = Date()
    @State private var summary: ActiveSession?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var session: ActiveSession? { appState.session }

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
                ForEach(ActiveSession.Mark.Kind.allCases, id: \.self) { kind in
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
                TGExplainer(text: "Время каждой отметки запишется само. Телефон можно убрать в карман — секунды считаются от начала, а не тикают на экране.")
            }
        } footer: {
            TGButton(title: "Пошли", systemImage: "figure.walk") { start() }
        }
    }

    private func start() {
        appState.startWalk(by: appState.currentUserName)
        if let dog {
            LiveActivityController.startWalk(dogName: dog.name,
                                             by: appState.currentUserName,
                                             at: Date())
        }
        Haptics.success()
    }

    // MARK: Прогулка идёт

    private func walkSheet(_ session: ActiveSession) -> some View {
        TGSheet(
            title: Fmt.stopwatch(session.duration(at: now)),
            subtitle: (session.isPaused ? session.kind.pausedTitle : session.kind.runningTitle)
                + " · " + session.tally,
            closeTitle: "Свернуть"
        ) {
            markGrid
            if !session.marks.isEmpty { marksList(session) }
        } footer: {
            HStack(spacing: Token.Space.s10) {
                TGButton(title: session.isPaused ? "Продолжить" : "Пауза",
                         variant: .secondary, size: .medium,
                         systemImage: session.isPaused ? "play.fill" : "pause.fill",
                         fullWidth: true) {
                    togglePause()
                }
                TGButton(title: "Закончить", variant: .secondary, size: .medium,
                         systemImage: "checkmark", fullWidth: true) {
                    finish()
                }
            }
        }
    }

    @ViewBuilder
    private var markGrid: some View {
        if session?.isPaused == true {
            TGBanner(tone: .waiting, title: "Прогулка на паузе",
                     subtitle: "Время не идёт. Нажми «Продолжить», когда пойдёте дальше.",
                     systemImage: "pause.circle")
        }
        VStack(spacing: Token.Space.s10) {
            // Самое частое — большой кнопкой: за прогулку это жмут чаще всего.
            Button { mark(.urine) } label: {
                markLabel(.urine, count: session?.count(of: .urine) ?? 0)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Token.Action.primary,
                                in: RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: Token.Space.s10) {
                ForEach([ActiveSession.Mark.Kind.stool, .water, .reaction], id: \.self) { kind in
                    Button { mark(kind) } label: {
                        markLabel(kind, count: session?.count(of: kind) ?? 0)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .background(kind == .reaction ? Token.Status.waitingBg : Token.Surface.sunken,
                                        in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Token.Space.s10) {
                ForEach([ActiveSession.Mark.Kind.treat, .training, .incident, .note], id: \.self) { kind in
                    Button { mark(kind) } label: {
                        VStack(spacing: Token.Space.s4) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .accessibilityHidden(true)
                            Text(kind.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(kind == .incident ? Token.Status.overdueText : Token.Ink.primary)
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget + 8)
                        .background(kind == .incident ? Token.Status.overdueBg : Token.Surface.sunken,
                                    in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                }
            }
        }
        .disabled(session?.isPaused == true)
        .opacity(session?.isPaused == true ? 0.4 : 1)
    }

    private func markLabel(_ kind: ActiveSession.Mark.Kind, count: Int) -> some View {
        VStack(spacing: Token.Space.s2) {
            Image(systemName: kind.symbol)
                .font(.system(size: 20, weight: .medium))
                .accessibilityHidden(true)
            Text(kind.title).textStyle(AppFont.cardTitle.color(Token.Ink.primary))
            if count > 0 {
                Text(count == 1 ? "отмечено" : "\(count) раза")
                    .textStyle(AppFont.micro)
            }
        }
        .foregroundStyle(Token.Ink.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(count > 0 ? "отмечено \(count)" : "не отмечено")
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
        appState.mark(kind)
        Haptics.tap()
        let count = appState.session?.count(of: kind) ?? 1
        appState.showUndo(count > 1 ? "\(kind.title) · \(count)-й раз" : "Отмечено · \(kind.title)")
    }

    private func undoMark() {
        if let removed = appState.undoLastMark() {
            Haptics.warning()
            appState.showUndo("Отметка убрана · \(removed.kind.title)")
        }
    }

    private func togglePause() {
        guard let session else { return }
        if session.isPaused {
            appState.resumeSession()
            Haptics.tap()
        } else {
            appState.pauseSession()
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
            summary = finished
            return
        }

        let log = EventLog(context: context, appState: appState)
        let duration = Int(finished.duration())

        log.record(.walk, dog: dog, at: finished.startedAt,
                   confirmation: "Записано · прогулка \(duration / 60) мин") { event in
            event.durationSeconds = duration
            event.note = finished.marks.isEmpty ? nil : finished.tally
        }

        for entry in finished.marks {
            log.record(entry.kind.logKind, dog: dog, at: entry.at,
                       confirmation: nil, haptic: .none) { event in
                switch entry.kind {
                case .urine: event.outcome = .urine
                case .stool: event.stoolForm = Diary.usualStool(dog.events)
                case .treat: event.grams = 5
                case .water: event.milliliters = 50
                default: break
                }
                event.note = "на прогулке"
            }
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

    var body: some View {
        TGSheet(title: "Погуляли", subtitle: Fmt.duration(session.duration())) {
            statsCard
            if session.reactions > 0 { reactionCard }
            if session.count(of: .stool) > 0 {
                TGExplainer(text: "Стул записан как обычный. Если было что-то не так — тапни по строке в ленте и уточни.")
            }
            if session.marks.isEmpty {
                TGExplainer(text: "Отметок не было — записалась только прогулка. Это нормально: не каждый выход надо разбирать.")
            }
        } footer: {
            TGButton(title: "Готово") {
                saveReactionDetails()
                onDone()
            }
        }
    }

    private var statsCard: some View {
        TGCard {
            HStack(spacing: 0) {
                TGStat(value: Fmt.duration(session.duration()), caption: "в пути", size: 20)
                TGStat(value: "\(session.count(of: .urine))", caption: "раз пописал", size: 20)
                if session.reactions > 0 {
                    TGStat(value: "\(session.reactions)", caption: "срывов", size: 20)
                } else {
                    TGStat(value: session.count(of: .stool) > 0 ? "да" : "нет", caption: "стул", size: 20)
                }
            }
            if !session.marks.isEmpty {
                TGDivider()
                Text(session.tally).textStyle(AppFont.caption)
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
            Text("Собака, которая сорвалась, в этот момент не может учиться, и ругать её бессмысленно. Полезно другое: отойти дальше, дать ей выдохнуть и в следующий раз пройти на той дистанции, где она справляется.")
                .textStyle(AppFont.caption)
        }
    }

    /// Дописываем подробности в уже созданные записи срывов.
    private func saveReactionDetails() {
        guard trigger != nil || distance != nil, let dog else { return }
        let times = Set(session.marks.filter { $0.kind == .reaction }.map(\.at))
        for event in dog.events where event.kind == .reaction && times.contains(event.date) {
            event.reactionTrigger = trigger
            event.reactionDistance = distance
        }
        try? context.save()
    }
}

/// Карточка идущей прогулки или выхода на главном экране.
/// Тап открывает режим обратно — свернуть шторку и потерять прогулку нельзя.
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
                            session.isPaused ? Token.Status.waitingText : Token.Action.primary
                        ))
                    Text(Fmt.stopwatch(session.duration(at: now)))
                        .textStyle(AppFont.display.color(
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
