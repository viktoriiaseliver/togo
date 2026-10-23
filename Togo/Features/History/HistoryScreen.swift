import SwiftUI
import SwiftData

/// История · фильтры-чипы, полоса выходов, ритм, календарь, эпизоды.
///
/// **Переписано под дизайн iOS 28, тема «Кино»** — решение Виктории
/// 22.10.2026. Эталон — `Дизайн/эталонные-кадры/ios28-кино-22.10/10.png`,
/// и ниже исполнен **кадр**, а не проза README: где они расходятся,
/// расхождение названо в отчёте.
///
/// Что поменялось в показе и почему:
///
/// ```
/// было                        стало (кадр 10)
/// шапка-плакат, синяя полоса  фото под шапкой, кикер «ВСЁ · 30 ДНЕЙ»,
///                             заголовок 36 и одна кнопка «…»
/// шестерёнка в баре           её нет: «Настройки» — пункт меню «…»
/// сегментированный выбор      чипы-пилюли с прокруткой вбок
/// график Swift Charts с осями полоса столбиков без осей
/// ```
///
/// **Сегментированный выбор убран не по вкусу.** У него измеренный
/// дефект: он делит ширину поровну и **обрезает**, а не переносит —
/// кадр 28.09 показал «Симпто…». Прежняя починка разводила два органа
/// управления по размеру текста (`.menu` на доступных кеглях). Чипы
/// закрывают тот же дефект одним органом: они не делят ширину,
/// подпись переносится целиком, а лишние уезжают за край прокруткой.
///
/// Точка на дне календаря: сине-зелёная — обычный день, терракот —
/// инцидент или кровь, серо-коричневая — медицинское событие; форма
/// значка разная, потому что цветом одним день не различить.
struct HistoryScreen: View {
    @Query private var dogs: [Dog]
    @Query private var episodes: [Episode]
    @Query private var members: [FamilyMember]
    @Query private var daysOut: [DayOut]

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var closing: Episode?
    /// Эпизод, который человек собрался удалить.
    @State private var удаляемый: Episode?
    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var filter: HistoryFilter = .all
    @State private var selectedDay: Date?
    /// Настройки открываются из меню «…» — шестерёнки в шапке больше нет.
    /// Переход делает хозяин экрана: `NavigationLink` внутри `Menu`
    /// срабатывает непредсказуемо (разбор у `HeaderMenu`).
    @State private var показатьНастройки = false

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var events: [LogEvent] { Diary.active(dog?.events ?? []) }

    var body: some View {
        NavigationStack {
            КиноЭкран(экран: .history,
                      кикер: .готовая(кикер),
                      заголовок: "История",
                      настройки: { показатьНастройки = true }) {
                if events.isEmpty {
                    EmptyStateCard(
                        subject: .history,
                        title: "История начнётся с первой записи",
                        message: "Здесь появятся календарь с точкой на каждый день, графики по стулу и весу и список эпизодов. Заполнять заранее ничего не надо.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    чипыФильтра
                    полосаВыходов
                    ритмВыходов
                    dayOutCard
                    месяцШапкой
                    MonthCalendar(month: $month, events: filtered, onSelect: { selectedDay = $0 })
                    episodesCard
                }
            }
            .usageScreen(.history)
            .navigationDestination(isPresented: $показатьНастройки) {
                SettingsScreen()
            }
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
            .confirmationDialog("Удалить эпизод?",
                                isPresented: Binding(get: { удаляемый != nil },
                                                     set: { if !$0 { удаляемый = nil } }),
                                titleVisibility: .visible,
                                presenting: удаляемый) { episode in
                Button("Удалить", role: .destructive) { удалить(episode) }
                Button("Оставить", role: .cancel) { удаляемый = nil }
            } message: { _ in
                // Говорим ровно то, что случится, и ровно то, что НЕ
                // случится. Человек боится потерять записи — а теряется
                // только объединение их в эпизод.
                Text("Сами записи — инциденты, стул, дозы — останутся: удаляется только объединение их в эпизод. Если инциденты повторятся, приложение поднимет эпизод заново.")
            }
        }
    }

    /// Кикер шапки: что выбрано и за какой срок. На кадре 10 — «ВСЁ · 30 ДНЕЙ».
    ///
    /// Собирается точкой-разделителем, а не грамматикой: склейки фраз
    /// хендофф переносить запрещает, а « · » между двумя готовыми
    /// строками переводить нечем и не нужно.
    private var кикер: String {
        [filter.title, String(localized: "30 дней")].joined(separator: " · ")
    }

    /// Чипы-пилюли с прокруткой вбок. Выбранный — белый с тёмной
    /// подписью, как главная кнопка темы «Кино».
    private var чипыФильтра: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Token.Space.s8) {
                ForEach(HistoryFilter.allCases, id: \.self) { вид in
                    КиноЧип(подпись: .готовая(вид.title),
                            выбран: вид == filter) {
                        filter = вид
                    }
                }
            }
            .padding(.vertical, Token.Space.s2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Фильтр")
    }

    private var filtered: [LogEvent] {
        events.filter(filter.matches)
    }

    // MARK: Полоса за тридцать дней

    /// Кадр 10: заголовок слева, срок справа, столбики без осей,
    /// пояснение под ними.
    ///
    /// **Осей нет нарочно.** У столбика без подписи единственный смысл —
    /// «выше или ниже соседнего», и ось месяца этого не добавляла:
    /// на тридцати днях подписи всё равно рисовались через одну.
    /// Что именно на полосе — говорит строка под ней, а не ось.
    private var полосаВыходов: some View {
        TGCard {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(.готовая(filter.chartName)).textStyle(AppFont.cardTitle).wraps()
                Spacer(minLength: Token.Space.s8)
                Text("30 дней").textStyle(AppFont.caption).wraps()
            }
            КиноСтолбики(значения: chartPoints.map(\.value),
                         тревожные: тревожныеДни)
            Text(filter.chartExplainer).textStyle(AppFont.caption).wraps()
            TGDivider()
            Text("Приложение не ставит диагнозов. Оно умеет показать этот график врачу — вместе с датами еды и препаратов за те же дни.")
                .textStyle(AppFont.caption)
                .wraps()
        }
    }

    private var тревожныеДни: Set<Int> {
        Set(chartPoints.enumerated().compactMap { $1.isAlarm ? $0 : nil })
    }

    /// График строится только по дням без активного эпизода.
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

    // MARK: Ритм

    /// «Как часто гуляете» блоком Metric — кадр 10: крупное число,
    /// единица рядом, зеркало под ним.
    ///
    /// **`WalkRhythmCard` здесь больше не зовётся**, и это названо,
    /// а не скрыто: её полная (не `compact`) ветка осталась без
    /// единственного места вызова. Файл чужой (`Features/Needs`),
    /// решение «переписать её под «Кино» или снять» — не моё.
    @ViewBuilder
    private var ритмВыходов: some View {
        let ритм = WalkRhythmAnalyzer.rhythm(events: events)
        if ритм.isReliable {
            КиноМетрика(
                шапка: "как часто гуляете",
                число: Fmt.decimal(ритм.outingsPerDay),
                единица: .готовая([String(localized: "выходов в день"),
                                   String(localized: "2 недели")].joined(separator: " · ")),
                пояснение: "Это не норма, а зеркало: сравнивать стоит не с чужой собакой, а с собой месяц назад."
            )
        } else {
            TGCard {
                TGSectionHeader(title: "как часто гуляете")
                TGExplainer(text: "Нужно хотя бы \(Fmt.days(WalkRhythm.minimumDays)) с записями — пока их \(ритм.days). Просто продолжай отмечать выходы.")
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
                Text("После долгих дней дома").textStyle(AppFont.cardTitle).wraps()
                Text("по \(String(localized: "\(trace.longDays) дням")), где она была с тобой дольше \(Int(DayOut.longDayHours)) часов")
                    .textStyle(AppFont.caption)
                    .wraps()
                ForEach(trace.findings, id: \.self) { line in
                    Text("• " + line).textStyle(AppFont.caption).wraps()
                }
                TGDivider()
                TGExplainer(text: "Это совпадение, а не причина: приложение не ставит диагнозов. Но показать эту строку врачу полезнее, чем сказать «она иногда вялая».")
            }
        }
    }

    // MARK: Календарь

    /// Месяц прописными над карточкой — кадр 10 («ОКТЯБРЬ 2026 Г»).
    /// Стрелки остались: без них из октября не выйти, а листание месяца
    /// это единственный способ дойти до прошлого года.
    private var месяцШапкой: some View {
        HStack(spacing: Token.Space.s8) {
            Text(verbatim: month.formatted(.dateTime.month(.wide).year()))
                .textStyle(AppFont.caps)
                .textCase(.uppercase)
                .wraps()
            Spacer(minLength: Token.Space.s8)
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Предыдущий месяц")
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Следующий месяц")
            .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Token.Ink.secondary)
    }

    private func shiftMonth(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeInOut(duration: Token.Duration.quick)) { month = next }
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
                            // Эпизод поднимается САМ, по двум инцидентам
                            // за сутки, — и человек не выбирал его заводить.
                            // До 28.09 удалить его было нельзя ничем:
                            // единственный `context.delete(episode)`
                            // в дереве — откат при несохранении.
                            // Заведённое приложением без спроса человек
                            // обязан уметь убрать.
                            Button { удаляемый = episode } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: Token.Size.iconSm))
                                    .frame(width: Token.Size.tapTarget,
                                           height: Token.Size.tapTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Token.Status.overdueText)
                            .accessibilityLabel("Удалить эпизод \(episode.title)")
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

    /// Убрать эпизод целиком.
    ///
    /// Записи не трогаем принципиально: эпизод — это ОБЪЕДИНЕНИЕ
    /// инцидентов, а не они сами. Удалив его вместе с ними, приложение
    /// стёрло бы то, ради чего дневник и ведут.
    ///
    /// `activeEpisode` снимается первым и возвращается при неудаче:
    /// иначе вердикт «просится» остался бы выключенным ссылкой
    /// на эпизод, которого уже нет.
    func удалить(_ episode: Episode) {
        let былоАктивным = appState.activeEpisode?.id == episode.id
        if былоАктивным { appState.activeEpisode = nil }
        context.delete(episode)
        guard context.persist(otherwise: {
            if былоАктивным { appState.activeEpisode = episode }
        }) else {
            Haptics.warning()
            appState.showFailure("Не удалилось · нажми ещё раз")
            return
        }
        Haptics.success()
        appState.showUndo("Эпизод удалён · записи остались")
        удаляемый = nil
    }

    func close(_ episode: Episode) {
        let былЗакрыт = episode.endedAt
        episode.close()
        guard context.persist(otherwise: { episode.endedAt = былЗакрыт }) else {
            Haptics.warning()
            return
        }
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
        case .all: String(localized: "Всё")
        case .stool: String(localized: "Стул")
        case .symptoms: String(localized: "Симптомы")
        case .reactions: String(localized: "Срывы")
        case .weight: String(localized: "Вес")
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

    /// Имя полосы БЕЗ срока: на кадре 10 срок стоит отдельной строкой
    /// справа, а не внутри заголовка.
    ///
    /// `chartTitle` оставлен рядом и не удалён: он склеивает имя
    /// со сроком и годится там, где строка одна (озвучка, отчёт).
    var chartName: String {
        switch self {
        case .all: String(localized: "Выходы")
        case .stool: String(localized: "Стул")
        case .symptoms: String(localized: "Инциденты")
        case .reactions: String(localized: "Срывы")
        case .weight: String(localized: "Вес")
        }
    }

    var chartTitle: String {
        [chartName, String(localized: "30 дней")].joined(separator: " · ")
    }

    var chartExplainer: String {
        switch self {
        case .all: String(localized: "Сколько раз в день выходили. Ровная линия — устоявшийся режим.")
        case .stool: String(localized: "Выше — жиже. Терракотовые столбики — дни с кровью или слизью.")
        case .symptoms: String(localized: "Столбик есть — был инцидент. Пусто — и хорошо.")
        case .reactions: String(localized: "Сколько раз собака срывалась за день. Смотреть надо не на отдельный день, а на то, куда идёт линия за месяц.")
        case .weight: String(localized: "Зелёная полоса — коридор, который назвал врач.")
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

// MARK: - Календарь

/// Месяц с точкой на день. Тап открывает таймлайн этого дня в режиме чтения.
///
/// Шапка с названием месяца уехала наружу (кадр 10: «ОКТЯБРЬ 2026 Г»
/// прописными **над** карточкой) — здесь осталась только сетка.
struct MonthCalendar: View {
    @Binding var month: Date
    let events: [LogEvent]
    var onSelect: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    var body: some View {
        TGCard {
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
        case .ordinary: String(localized: "записи есть")
        case .alarm: String(localized: "тревога")
        case .medical: String(localized: "лечение")
        }
    }
}

private struct DayCell: View {
    let day: Date
    let month: Date
    let marker: DayMarker

    /// Значок маркера растёт вместе с системным кеглем.
    ///
    /// Прибитый `size: 8` был бы новым экземпляром того же дефекта,
    /// ради которого в проекте открыт пункт про Dynamic Type — и завела
    /// бы его правка ПРО доступность. `@ScaledMetric` чинит одну точку,
    /// а не весь каталог стилей, но эту точку чинит по-настоящему.
    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 8

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
                        .font(.system(size: markerSize, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Color.clear
                }
            }
            .frame(height: markerSize + Token.Space.s2)
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
        // День открывается нажатием, и сказать об этом должен трейт:
        // `onTapGesture` снаружи ячейки озвучке не виден, и VoiceOver
        // читал «13 сентября, тревога», умалчивая, что сюда можно зайти.
        .accessibilityAddTraits(.isButton)
    }

    private var color: Color {
        switch marker {
        case .none: .clear
        case .ordinary: Token.Action.doneText
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
        TGSheet(title: .готовая(Fmt.dayTitle(day)), subtitle: "режим чтения") {
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
