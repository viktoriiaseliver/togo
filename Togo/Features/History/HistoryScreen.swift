import SwiftUI
import SwiftData
import Charts

/// История · календарь, день, графики.
/// Точка на дне: сине-зелёная — обычный день, терракот — инцидент или кровь,
/// серо-коричневая — медицинское событие.
struct HistoryScreen: View {
    @Query private var dogs: [Dog]
    @Query private var episodes: [Episode]
    @Query private var members: [FamilyMember]
    @Query private var daysOut: [DayOut]

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var closing: Episode?
    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var filter: HistoryFilter = .all
    @State private var selectedDay: Date?

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var events: [LogEvent] { Diary.active(dog?.events ?? []) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if events.isEmpty {
                    EmptyStateCard(
                        systemImage: "calendar",
                        title: "История начнётся с первой записи",
                        message: "Здесь появятся календарь с точкой на каждый день, графики по стулу и весу и список эпизодов. Заполнять заранее ничего не надо.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    filterPicker
                    WalkRhythmCard(rhythm: WalkRhythmAnalyzer.rhythm(events: events))
                    dayOutCard
                    MonthCalendar(month: $month, events: filtered, onSelect: { selectedDay = $0 })
                    chartCard
                    episodesCard
                }
            }
            .navigationTitle("История")
            .usageScreen(.history)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { SettingsToolbarItem() }
            .sheet(item: Binding(get: { selectedDay.map(DayRef.init) },
                                 set: { selectedDay = $0?.date })) { ref in
                DayReadingScreen(day: ref.date, events: events,
                                 showsAuthor: members.count > 1)
            }
            .confirmationDialog("Закрыть эпизод?",
                                isPresented: Binding(get: { closing != nil },
                                                     set: { if !$0 { closing = nil } }),
                                titleVisibility: .visible,
                                presenting: closing) { episode in
                Button("Закрыть") { close(episode) }
                Button("Ещё рано", role: .cancel) { closing = nil }
            } message: { _ in
                Text("Записи останутся в истории. Вердикт «просится» снова начнёт считаться по обычным промежуткам — во время эпизода он не считается совсем.")
            }
        }
    }

    /// Что бывает после долгих дней с собакой.
    ///
    /// Причинность приложение не утверждает: оно показывает совпадение
    /// и оставляет вывод человеку. Этого хватает, чтобы прийти к врачу
    /// не с «ей плохо», а с «после долгих дней у неё вот что».
    @ViewBuilder
    private var dayOutCard: some View {
        let mine = daysOut.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
        let trace = DayOutAnalyzer.trace(daysOut: mine, events: events,
                                         norm: dog?.dailyGrams ?? 0)
        if !trace.findings.isEmpty {
            TGCard {
                TGSectionHeader(title: "после долгих дней",
                                subtitle: "по \(Fmt.plural(trace.longDays, "дню", "дням", "дням")), где она была с тобой дольше \(Int(DayOut.longDayHours)) часов")
                ForEach(trace.findings, id: \.self) { line in
                    Text("• " + line).textStyle(AppFont.caption).wraps()
                }
                TGDivider()
                TGExplainer(text: "Это совпадение, а не причина: приложение не ставит диагнозов. Но показать эту строку врачу полезнее, чем сказать «она иногда вялая».")
            }
        }
    }

    private var filtered: [LogEvent] {
        events.filter(filter.matches)
    }

    private var filterPicker: some View {
        Picker("Фильтр", selection: $filter) {
            ForEach(HistoryFilter.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: График

    /// График строится только по дням без активного эпизода.
    private var chartCard: some View {
        TGCard {
            Text(filter.chartTitle).textStyle(AppFont.cardTitle)
            HistoryChart(points: chartPoints, filter: filter)
                .frame(height: 140)
            Text(filter.chartExplainer).textStyle(AppFont.caption)
            TGDivider()
            Text("Приложение не ставит диагнозов. Оно умеет показать этот график врачу — вместе с датами еды и препаратов за те же дни.")
                .textStyle(AppFont.caption)
        }
    }

    private var chartPoints: [HistoryPoint] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) ?? .now
        return (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayEvents = Diary.onDay(filtered, day)
            return HistoryPoint(day: day, value: filter.value(for: dayEvents),
                                isAlarm: dayEvents.contains(where: \.raisesAlarm))
        }
    }

    // MARK: Эпизоды

    private var episodesCard: some View {
        TGCard {
            TGSectionHeader(title: "эпизоды")
            if episodes.isEmpty {
                TGExplainer(text: "Пока ни одного. Эпизод поднимается сам: два инцидента за сутки или несколько дней подряд с жидким стулом.")
            } else {
                ForEach(episodes.sorted { $0.startedAt > $1.startedAt }) { episode in
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        HStack {
                            Text(episode.title).textStyle(AppFont.bodyEmphasis)
                            Spacer()
                            Text(Fmt.shortDay(episode.startedAt)).textStyle(AppFont.micro)
                        }
                        Text(episode.detail).textStyle(AppFont.caption).wraps()
                        if episode.isActive() { activeEpisodeFooter(episode) }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    if episode.id != episodes.last?.id { TGDivider() }
                }
            }
        }
    }
}

extension HistoryScreen {
    /// Пока эпизод идёт, вердикт «просится» не считается вовсе — а человек
    /// не видел ни того, что эпизод ещё идёт, ни когда он кончится.
    /// Закрыть его руками было нельзя: метод в модели был, вызывать его
    /// было неоткуда.
    @ViewBuilder
    func activeEpisodeFooter(_ episode: Episode) -> some View {
        Text("Идёт. Закроется сам \(Fmt.shortDay(episode.quietUntil)), если больше ничего не случится.")
            .textStyle(AppFont.micro.color(Token.Status.waitingText))
            .wraps()
        TGButton(title: "Собаке лучше — закрыть", variant: .finish, size: .medium,
                 systemImage: "checkmark") {
            closing = episode
        }
    }

    func close(_ episode: Episode) {
        episode.close()
        try? context.save()
        Haptics.success()
        closing = nil
    }
}

/// Обёртка, чтобы дату можно было отдать в `.sheet(item:)`.
private struct DayRef: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Фильтр

nonisolated enum HistoryFilter: String, CaseIterable, Sendable {
    case all, stool, symptoms, reactions, weight

    var title: String {
        switch self {
        case .all: "Всё"
        case .stool: "Стул"
        case .symptoms: "Симптомы"
        case .reactions: "Срывы"
        case .weight: "Вес"
        }
    }

    /// Фильтр меняет и календарь, и список эпизодов, и график — одно состояние на экран.
    func matches(_ event: LogEvent) -> Bool {
        switch self {
        case .all: true
        case .stool: event.kind == .stool || (event.kind == .outing && event.outcome != .urine)
        case .symptoms: event.kind == .incident || event.raisesAlarm
        case .reactions: event.kind == .reaction || event.incidentKind == .reaction
        case .weight: event.kind == .weight
        }
    }

    var chartTitle: String {
        switch self {
        case .all: "Выходы · 30 дней"
        case .stool: "Стул · 30 дней"
        case .symptoms: "Инциденты · 30 дней"
        case .reactions: "Срывы · 30 дней"
        case .weight: "Вес · 30 дней"
        }
    }

    var chartExplainer: String {
        switch self {
        case .all: "Сколько раз в день выходили. Ровная линия — устоявшийся режим."
        case .stool: "Выше — жиже. Терракотовые столбики — дни с кровью или слизью."
        case .symptoms: "Столбик есть — был инцидент. Пусто — и хорошо."
        case .reactions: "Сколько раз собака срывалась за день. Смотреть надо не на отдельный день, а на то, куда идёт линия за месяц."
        case .weight: "Зелёная полоса — коридор, который назвал врач."
        }
    }

    func value(for events: [LogEvent]) -> Double {
        switch self {
        case .all: Double(events.filter { $0.kind == .outing }.count)
        case .stool: events.compactMap { $0.stoolForm?.bristolScore }.map(Double.init).max() ?? 0
        case .symptoms: Double(events.filter { $0.kind == .incident }.count)
        case .reactions: Double(events.filter { $0.kind == .reaction || $0.incidentKind == .reaction }.count)
        case .weight: 0
        }
    }
}

nonisolated struct HistoryPoint: Identifiable, Sendable {
    let day: Date
    let value: Double
    let isAlarm: Bool
    var id: Date { day }
}

/// Столбиковый график на системном Charts — своей отрисовки не пишем.
struct HistoryChart: View {
    let points: [HistoryPoint]
    let filter: HistoryFilter

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("День", point.day, unit: .day),
                y: .value(filter.title, point.value)
            )
            .foregroundStyle(point.isAlarm ? Token.Status.overdueText : Token.Ink.silhouette)
            .cornerRadius(2)
        }
        .tgChartAxes()
    }
}

// MARK: - Календарь

/// Месяц с точкой на день. Тап открывает таймлайн этого дня в режиме чтения.
struct MonthCalendar: View {
    @Binding var month: Date
    let events: [LogEvent]
    var onSelect: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    var body: some View {
        TGCard {
            header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Token.Space.s4), count: 7),
                      spacing: Token.Space.s6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).textStyle(AppFont.micro.color(Token.Ink.secondary))
                }
                ForEach(gridDays, id: \.self) { day in
                    DayCell(day: day, month: month, marker: marker(for: day))
                        .onTapGesture { onSelect(day) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).textStyle(AppFont.cardTitle)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Следующий месяц")
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .tint(Token.Ink.secondary)
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeInOut(duration: Token.Duration.quick)) { month = next }
    }

    /// Сетка всегда начинается с понедельника — чтобы недели не разъезжались.
    private var gridDays: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = calendar.startOfMonth(for: month)
        let weekday = (calendar.component(.weekday, from: first) + 5) % 7
        let leading = (0..<weekday).compactMap { calendar.date(byAdding: .day, value: -(weekday - $0), to: first) }
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        return leading + days
    }

    private func marker(for day: Date) -> DayMarker {
        let dayEvents = Diary.onDay(events, day)
        if dayEvents.isEmpty { return .none }
        if dayEvents.contains(where: { $0.raisesAlarm || $0.kind == .incident }) { return .alarm }
        if dayEvents.contains(where: { $0.kind.isMedical }) { return .medical }
        return .ordinary
    }
}

nonisolated enum DayMarker: Sendable {
    case none, ordinary, alarm, medical

    /// Значок, а не только цвет.
    ///
    /// Три вида дня отличались ТОЛЬКО оттенком точки в пять пунктов.
    /// Для человека, который не различает красный и зелёный, календарь
    /// был одинаковым насквозь: «найди день, когда была кровь» на нём
    /// не решается вовсе. Форма отвечает на тот же вопрос, не спрашивая
    /// про цвет.
    var symbol: String? {
        switch self {
        case .none: nil
        case .ordinary: "circle.fill"
        case .alarm: "exclamationmark.triangle.fill"
        case .medical: "cross.fill"
        }
    }

    /// Чем день кончился — словами. Идёт в метку озвучки: до этого
    /// метка была датой и только датой, то есть незрячему календарь
    /// не сообщал ничего, кроме чисел месяца.
    var spoken: String? {
        switch self {
        case .none: nil
        case .ordinary: "записи есть"
        case .alarm: "тревога"
        case .medical: "лечение"
        }
    }
}

private struct DayCell: View {
    let day: Date
    let month: Date
    let marker: DayMarker

    private var isInMonth: Bool { Calendar.current.isDate(day, equalTo: month, toGranularity: .month) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: Token.Space.s2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .textStyle(AppFont.captionEmphasis.color(isInMonth ? Token.Ink.primary : Token.Ink.secondary))
            // 8 пунктов вместо пяти: на пяти форма неразличима,
            // и значок выродился бы обратно в цветную точку.
            Group {
                if let symbol = marker.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Color.clear
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        // Ячейку календаря нажимают пальцем — значит, не меньше 44.
        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
        .background(isToday ? Token.Action.doneQuiet : .clear,
                    in: RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        // Маркер ВХОДИТ в метку. Раньше метка была датой и только датой,
        // и весь смысл дня — тревога, лечение, обычные записи — до озвучки
        // не доезжал: экран «найди день, когда была кровь» был пуст.
        .accessibilityLabel(
            [Fmt.shortDay(day), marker.spoken].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private var color: Color {
        switch marker {
        case .none: .clear
        case .ordinary: Token.Action.done
        case .alarm: Token.Status.overdueText
        case .medical: Token.Ink.silhouette
        }
    }
}

/// Таймлайн дня в режиме чтения: правок здесь нет.
struct DayReadingScreen: View {
    let day: Date
    let events: [LogEvent]
    var showsAuthor: Bool = false

    private var dayEvents: [LogEvent] {
        Diary.onDay(events, day)
    }

    var body: some View {
        TGSheet(title: Fmt.dayTitle(day), subtitle: "режим чтения") {
            if dayEvents.isEmpty {
                TGCard { TGExplainer(text: "В этот день записей нет.") }
            } else {
                // Тот же рельс, что и на главном: промежутки между записями
                // в прошлом читают ровно за тем же, зачем и сегодня.
                DayTimeline(events: dayEvents, now: day,
                            showsAuthor: showsAuthor, showsNow: false) { _ in }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

nonisolated extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
