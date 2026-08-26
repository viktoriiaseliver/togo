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

    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var filter: HistoryFilter = .all
    @State private var selectedDay: Date?

    private var dog: Dog? { dogs.first }
    private var events: [LogEvent] { Diary.active(dog?.events ?? []) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if events.isEmpty {
                    EmptyStateCard(
                        systemImage: "calendar",
                        title: "История начнётся с первой записи",
                        message: "Здесь появятся календарь с точкой на каждый день, графики по стулу и весу и список эпизодов. Пока записей нет — и заполнять ничего заранее не надо.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    filterPicker
                    MonthCalendar(month: $month, events: filtered, onSelect: { selectedDay = $0 })
                    chartCard
                    episodesCard
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { SettingsToolbarItem() }
            .sheet(item: Binding(get: { selectedDay.map(DayRef.init) },
                                 set: { selectedDay = $0?.date })) { ref in
                DayReadingScreen(day: ref.date, events: events,
                                 showsAuthor: members.count > 1)
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
                        Text(episode.detail).textStyle(AppFont.caption)
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }
        }
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
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Token.Surface.hairline)
                AxisValueLabel().foregroundStyle(Token.Ink.faint)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Token.Ink.faint)
            }
        }
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
                    Text(day).textStyle(AppFont.micro.color(Token.Ink.faint))
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
                .textStyle(AppFont.captionEmphasis.color(isInMonth ? Token.Ink.primary : Token.Ink.faint))
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .opacity(marker == .none ? 0 : 1)
        }
        // Ячейку календаря нажимают пальцем — значит, не меньше 44.
        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
        .background(isToday ? Token.Action.primaryQuiet : .clear,
                    in: RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityLabel(Fmt.shortDay(day))
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
