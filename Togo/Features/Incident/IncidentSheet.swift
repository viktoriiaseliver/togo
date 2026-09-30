import SwiftUI
import SwiftData

/// Инцидент · два тапа. Первый записывает, второй уточняет.
/// Никаких вопросов «почему» и «чья вина».
struct IncidentSheet: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var recorded: LogEvent?

    var body: some View {
        Group {
            if let recorded {
                IncidentDetailStep(event: recorded, dog: dog) { dismiss() }
            } else {
                pickerStep
            }
        }
        .presentationDetents([.large])
        .usageScreen(.incident)
    }

    private var pickerStep: some View {
        TGSheet(title: "Что случилось", subtitle: .готовая(Fmt.clock(Date()))) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Token.Space.s8), count: 2),
                      spacing: Token.Space.s8) {
                ForEach(IncidentKind.allCases, id: \.self) { kind in
                    Button { record(kind) } label: {
                        VStack(spacing: Token.Space.s8) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Token.Ink.silhouette)
                            Text(kind.title).textStyle(AppFont.bodyEmphasis)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .background(Token.Surface.card,
                                    in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TGExplainer(text: "Запишется сразу, без вопросов «почему» и «чья вина». Уточнить можно потом, тапнув по строке в ленте.")
        }
    }

    private func record(_ kind: IncidentKind) {
        guard let dog else { return }
        // Через `EventLog`, а не мимо. До 23.09.2026 этот экран собирал
        // запись руками и звал `context.insert` — то есть проходил мимо
        // проверки права, сторожа дубля и честного сообщения о том, что
        // сохранить не вышло. Пока роль по умолчанию была «владелец»,
        // разницы не было: дверь стояла открытая, и ходить мимо неё
        // было незачем. Как только у прав появились зубы, обход стал
        // дырой: гость-наблюдатель получал отказ на главном пути
        // и записывал инцидент здесь.
        //
        // Тоста нет намеренно: экран сам показывает записанное
        // и предлагает уточнить.
        guard let event = EventLog(context: context, appState: appState)
            .record(.incident, dog: dog, confirmation: nil, haptic: .warning, configure: {
                $0.incidentKind = kind
                $0.toldFamily = kind.notifiesFamilyByDefault
            })
        else { return }
        raiseEpisodeIfNeeded(for: dog)
        recorded = event
    }

    /// Второй инцидент за сутки поднимает флаг эпизода: вердикты гаснут,
    /// пока не станет понятно, что происходит.
    ///
    /// Это один из двух путей. Второй — жидкий стул два календарных дня
    /// подряд: правило в `EpisodeRules`, заводит `StoolSheet`. Эпизод,
    /// поднятый стулом, здесь продлевается так же, как свой.
    private func raiseEpisodeIfNeeded(for dog: Dog) {
        let recent = Diary.incidentsInLast24h(dog.events)
        guard recent.count >= 2 else { return }

        // Ещё один инцидент — не новый эпизод, а продолжение старого.
        if let running = appState.activeEpisode, running.isActive() {
            let былоПоследним = running.lastIncidentAt
            let былКонец = running.endedAt
            running.extend()
            guard context.persist(otherwise: {
                running.lastIncidentAt = былоПоследним
                running.endedAt = былКонец
            }) else {
                Haptics.warning()
                appState.showUndo("Эпизод не продлился · отметь ещё раз")
                return
            }
            return
        }

        let episode = Episode(
            title: "Эпизод",
            detail: "Два инцидента за сутки. Вердикты «просится» на паузе, пока не станет понятно, что происходит.",
            startedAt: recent.map(\.date).min() ?? Date()
        )
        episode.extend()
        context.insert(episode)

        // `appState.activeEpisode` ставится только после удачного сохранения.
        // Раньше здесь стоял `try?`, и эпизод открывался на экране, не
        // существуя в хранилище: вердикты «просится» гасли, объяснения
        // этому в дневнике не было, а после перезапуска эпизод исчезал
        // вместе с причиной, по которой приложение замолчало.
        guard context.persist(otherwise: { context.delete(episode) }) else {
            Haptics.warning()
            appState.showUndo("Эпизод не завёлся · отметь ещё раз")
            return
        }
        appState.activeEpisode = episode
    }
}

/// Второй шаг: уточнение, предупреждение о наказании и час предыстории.
private struct IncidentDetailStep: View {
    let event: LogEvent
    let dog: Dog?
    var onDone: () -> Void

    @Environment(AppState.self) private var appState

    private var kind: IncidentKind { event.incidentKind ?? .other }

    var body: some View {
        TGSheet(
            title: "\(kind.title) · \(Fmt.clock(event.date))",
            subtitle: "записано · дальше только если хочешь"
        ) {
            if kind == .vomit { vomitDetails }
            if kind.asksReactionDetails { reactionDetails }
            if kind.showsPunishmentWarning { punishmentWarning }
            if let previous = previousIncident { episodeNotice(previous) }
            tellFamilyToggle
        } footer: {
            TGButton(title: "Готово", action: onDone)
        }
    }

    // MARK: Чем именно

    private var vomitDetails: some View {
        TGCard {
            TGSectionHeader(title: "чем именно")
            TGChipGroup(
                items: VomitDetail.allCases,
                title: \.title,
                isSelected: { event.vomitDetail == $0 },
                tone: { $0.raisesAlarm ? .alarm : .neutral }
            ) { detail in
                event.vomitDetail = (event.vomitDetail == detail) ? nil : detail
                Haptics.tap()
            }
            if event.vomitDetail?.raisesAlarm == true {
                TGExplainer(text: "Кровь — единственный флаг, который поднимает запись в терракот и предлагает собрать выписку.")
            }
        }
    }

    // MARK: Срыв

    /// Те же два вопроса, что и после прогулки: на что и как близко.
    /// Ругать собаку за срыв бессмысленно — она в этот момент за порогом.
    private var reactionDetails: some View {
        TGCard {
            TGSectionHeader(title: "на что сорвался")
            TGChipGroup(items: ReactionTrigger.allCases, title: \.title,
                        isSelected: { $0 == event.reactionTrigger }, minimumWidth: 130) { chosen in
                event.reactionTrigger = event.reactionTrigger == chosen ? nil : chosen
                Haptics.tap()
            }
            TGDivider()
            TGSectionHeader(title: "как близко")
            TGChipGroup(items: ReactionDistance.allCases, title: \.title,
                        isSelected: { $0 == event.reactionDistance }, minimumWidth: 110) { chosen in
                event.reactionDistance = event.reactionDistance == chosen ? nil : chosen
                Haptics.tap()
            }
            TGExplainer(text: "Срыв — это порог, а не проступок. Собака в этот момент не может учиться: полезно отойти дальше и дать ей выдохнуть, а не отчитывать.")
        }
    }

    // MARK: Не наказывай

    /// Приложение видит момент записи и обязано в этот момент сказать это.
    /// Один раз, без морали, рядом с записью.
    private var punishmentWarning: some View {
        VStack(alignment: .leading, spacing: Token.Spacing.stack) {
            TGCard {
                Text("Не наказывай").textStyle(AppFont.cardTitle)
                Text("Тыкать носом и ругать учит не чистоплотности, а прятаться и делать лужи там, где не видно. Собака не связывает выговор с тем, что было десять минут назад.")
                    .textStyle(AppFont.caption)
            }
            historyBefore
        }
    }

    private var historyBefore: some View {
        let rows = Diary.hourBefore(dog?.events ?? [], incident: event.date)
        return TGCard {
            TGSectionHeader(title: "что было до")
            if rows.isEmpty {
                TGExplainer(text: "Записей за последние часы нет — поэтому и сказать нечего. Через несколько дней здесь будет вода, одиночество и последний выход.")
            } else {
                ForEach(rows) { row in
                    HStack(spacing: Token.Space.s12) {
                        Text(Fmt.clock(row.date))
                            .textStyle(AppFont.numeric(13, weight: .medium))
                            .fixedSize()
                            .frame(minWidth: 44, alignment: .leading)
                        Text(row.subtitle ?? row.kind.title).textStyle(AppFont.caption)
                        Spacer(minLength: 0)
                    }
                }
                if let lastOuting = Diary.last(dog?.events ?? [], kind: .outing, before: event.date) {
                    TGDivider()
                    Text("Последний выход был \(Fmt.duration(event.date.timeIntervalSince(lastOuting.date))) назад.")
                        .textStyle(AppFont.caption.color(Token.Ink.primary))
                }
            }
        }
    }

    // MARK: Эпизод

    private var previousIncident: LogEvent? {
        Diary.incidentsInLast24h(dog?.events ?? [])
            .filter { $0.id != event.id }
            .max { $0.date < $1.date }
    }

    private func episodeNotice(_ previous: LogEvent) -> some View {
        TGBanner(
            tone: .waiting,
            title: "Второй раз за сутки",
            subtitle: "Первый был в \(Fmt.clock(previous.date)). Приложение поставит на паузу вердикты «просится» до вечера и предложит собрать выписку, если будет третий.",
            systemImage: "exclamationmark.triangle"
        )
    }

    // MARK: Сказать остальным

    private var tellFamilyToggle: some View {
        TGCard {
            Toggle(isOn: Binding(get: { event.toldFamily }, set: { event.toldFamily = $0 })) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Сказать остальным").textStyle(AppFont.body)
                    Text(kind.notifiesFamilyByDefault
                         ? "для рвоты и крови включено по умолчанию"
                         : "для лужи выключено: это не новость для семьи")
                        .textStyle(AppFont.caption)
                }
            }
        }
    }
}
