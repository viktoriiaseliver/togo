import SwiftUI
import SwiftData

/// Уход. Три разных сорта дел, и путать их нельзя:
/// зубы чистят каждый день, когти стригут раз в три недели, прививку делают
/// в конкретный день. Раньше всё лежало одной кучей — и приложение в первый
/// же день кричало «сегодня» про всё сразу.
struct CareScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    /// Запросом, а не через связь: только что добавленное дело в обратной
    /// связи появляется не сразу, и список выглядит неизменившимся.
    @Query private var allTasks: [CareTask]

    @State private var editing: CareTask?
    @State private var isAdding = false
    @State private var isChoosing = false
    @State private var now = Date()

    private var tasks: [CareTask] {
        guard let dog else { return [] }
        return allTasks.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Уход", отступы: false)
            if tasks.isEmpty {
                emptyState
            } else {
                if !withoutDate.isEmpty { needsDateCard }
                ForEach(CareKind.allCases, id: \.self) { kind in
                    section(kind)
                }
                footer
            }
        }
        .navigationTitle("Уход")
        .cinemaScreen()
        .usageScreen(.care)
        .toolbar {
            if dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Выбрать из списка", systemImage: "checklist") { isChoosing = true }
                        Button("Своё дело", systemImage: "plus") { isAdding = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить дело")
                }
            }
        }
        .sheet(isPresented: $isAdding) { CareTaskEditorSheet(dog: dog) }
        .sheet(isPresented: $isChoosing) { CareSuggestionsSheet(dog: dog) }
        .sheet(item: $editing) { task in CareTaskEditorSheet(task: task, dog: dog) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Token.Spacing.stack) {
            EmptyStateCard(
                subject: .care,
                title: "Уход настраивается под собаку",
                message: "У каждой собаки он свой: шипперке не купают часто, а зубы чистят всем и каждый день. Выбери из списка то, что делаешь, — или заведи своё.",
                actionTitle: dog == nil ? nil : "Выбрать из списка",
                action: dog == nil ? nil : { isChoosing = true }
            )
            if dog != nil {
                TGButton(title: "Завести своё дело", variant: .secondary,
                         size: .medium, systemImage: "plus") { isAdding = true }
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: CareKind) -> some View {
        let group = tasks.filter { $0.kind == kind && !$0.needsDate }
        if !group.isEmpty {
            TGCard(spacing: 0) {
                TGSectionHeader(title: .готовая(kind.sectionTitle), subtitle: subtitle(for: kind, group: group).map { .готовая($0) })
                ForEach(sorted(group)) { task in
                    CareTaskRow(task: task, now: now,
                                onToggle: { toggle(task) },
                                // Ежедневное не откладывают — его просто
                                // не делают сегодня, и «Потом» у него нет.
                                onSnooze: kind == .daily ? nil : { snooze(task) },
                                onEdit: { editing = task })
                    if task.id != sorted(group).last?.id { TGDivider() }
                }
            }
        }
    }

    /// Дела, у которых нет даты последнего раза.
    ///
    /// Без неё регулярное дело не становится сроком — то есть заведённое
    /// напоминание не напоминает ни о чём. Раньше это было тихой дырой:
    /// человек завёл девять дел, и все они молчали навсегда.
    private var withoutDate: [CareTask] {
        tasks.filter(\.needsDate)
    }

    private var needsDateCard: some View {
        TGCard {
            TGSectionHeader(
                title: "нужна дата",
                subtitle: "пока её нет, приложение не может напомнить"
            )
            ForEach(withoutDate) { task in
                VStack(alignment: .leading, spacing: Token.Space.s8) {
                    Text(task.title).textStyle(AppFont.bodyEmphasis)
                    Text(task.kind == .dated ? "Когда назначено?" : "Когда делали последний раз?")
                        .textStyle(AppFont.caption)
                    TGChipGroup(
                        items: task.kind == .dated ? DateGuess.forDated : DateGuess.forPeriodic,
                        title: \.title,
                        isSelected: { _ in false },
                        minimumWidth: 96
                    ) { guess in
                        setDate(guess, for: task)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Token.Space.s6)
                if task.id != withoutDate.last?.id { TGDivider() }
            }
            TGExplainer(text: "Точность здесь не нужна: приложению хватит примерной даты, чтобы посчитать следующий срок. Поправить можно в любой момент.")
        }
    }

    /// Варианты «когда» — намеренно грубые: точной даты человек не помнит,
    /// а требовать её значит не получить никакой.
    private enum DateGuess: String, CaseIterable {
        case today, weekAgo, monthAgo, longAgo, soon

        var title: String {
            switch self {
            case .today: String(localized: "Сегодня")
            case .weekAgo: String(localized: "Неделю назад")
            case .monthAgo: String(localized: "Месяц назад")
            case .longAgo: String(localized: "Давно")
            case .soon: String(localized: "Через месяц")
            }
        }

        func date(from now: Date) -> Date? {
            let calendar = Calendar.current
            switch self {
            case .today: return now
            case .weekAgo: return calendar.date(byAdding: .day, value: -7, to: now)
            case .monthAgo: return calendar.date(byAdding: .month, value: -1, to: now)
            case .longAgo: return calendar.date(byAdding: .month, value: -6, to: now)
            case .soon: return calendar.date(byAdding: .month, value: 1, to: now)
            }
        }

        static var forPeriodic: [DateGuess] { [.today, .weekAgo, .monthAgo, .longAgo] }
        static var forDated: [DateGuess] { [.today, .soon] }
    }

    private func setDate(_ guess: DateGuess, for task: CareTask) {
        guard let date = guess.date(from: now) else { return }
        let былаДата = task.scheduledDate
        let былоСделано = task.lastDone
        if task.kind == .dated {
            task.scheduledDate = date
        } else {
            task.lastDone = date
        }
        guard context.persist(otherwise: {
            task.scheduledDate = былаДата
            task.lastDone = былоСделано
        }) else { return неСохранилось() }
        Haptics.tap()
        appState.showUndo("\(task.title) · \(guess.title.lowercased())")
    }

    /// Отказ хранилища виден человеку: экран уже показал бы «отложено»,
    /// а напоминание пришло бы в прежний срок.
    private func неСохранилось() {
        Haptics.warning()
        appState.showFailure("Не сохранилось · попробуй ещё раз")
    }

    private func subtitle(for kind: CareKind, group: [CareTask]) -> String? {
        switch kind {
        case .daily:
            let done = group.filter { $0.isDoneToday(on: now) }.count
            return String(localized: "сегодня \(done) из \(group.count)")
        case .periodic:
            let overdue = group.filter { $0.isOverdue(on: now) }.count
            return overdue > 0 ? String(localized: "просрочено: \(overdue)") : nil
        case .dated:
            return String(localized: "напомним заранее")
        }
    }

    private func sorted(_ group: [CareTask]) -> [CareTask] {
        group.sorted { left, right in
            (left.daysUntilDue(from: now) ?? 9999) < (right.daysUntilDue(from: now) ?? 9999)
        }
    }

    private var footer: some View {
        TGExplainer(text: "Всё это приходит одним сообщением в выбранный час, а не восемью подряд. Прерывают только доза и окно натощак.")
    }

    private func toggle(_ task: CareTask) {
        // Ежедневное можно снять, если отметили по ошибке: у привычки
        // нет долга, но и врать себе незачем.
        if task.kind == .daily, task.isDoneToday(on: now) {
            task.lastDone = nil
            task.streak = max(0, task.streak - 1)
            Haptics.warning()
            UsageLog.note(.care, "undone")
            appState.showUndo("Снято · \(task.title)")
            return
        }

        task.markDone()
        EventLog(context: context, appState: appState)
            .record(.care, dog: dog, confirmation: confirmation(for: task)) { event in
                event.note = task.title
                event.careTaskID = task.id
            }
    }

    /// Отложить на завтра. Счётчик нужен не для укора: отложенное дважды
    /// подсвечивается в сводке, но в тревогу не переходит.
    private func snooze(_ task: CareTask) {
        let calendar = Calendar.current
        let былоСделано = task.lastDone
        let былаДата = task.scheduledDate
        switch task.kind {
        case .daily:
            // Ежедневное не откладывают: строка «Потом» ему и не выдаётся.
            return
        case .periodic:
            task.lastDone = calendar.date(byAdding: .day,
                                          value: -(task.intervalDays - 1),
                                          to: now)
        case .dated:
            task.scheduledDate = calendar.date(byAdding: .day, value: 1,
                                               to: task.scheduledDate ?? now)
        }
        task.snoozeCount += 1
        guard context.persist(otherwise: {
            task.lastDone = былоСделано
            task.scheduledDate = былаДата
            task.snoozeCount -= 1
        }) else { return неСохранилось() }
        UsageLog.note(.care, "snooze")
        Haptics.tap()
        appState.showUndo("\(task.title) · до завтра")
    }

    private func confirmation(for task: CareTask) -> String {
        if task.kind == .daily, task.streak > 1 {
            return String(localized: "\(task.title) · \(Fmt.days(task.streak)) подряд")
        }
        return String(localized: "Записано · \(task.title)")
    }
}

/// Строка дела. Ежедневное — с кружком-галочкой, остальное — со сроком.
private struct CareTaskRow: View {
    let task: CareTask
    let now: Date
    var onToggle: () -> Void
    var onSnooze: (() -> Void)?
    var onEdit: () -> Void

    private var isDoneToday: Bool { task.isDoneToday(on: now) }

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            if task.kind == .daily {
                Button(action: onToggle) {
                    Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isDoneToday ? Token.Action.doneText : Token.Ink.secondary)
                        .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDoneToday ? "Снять отметку: \(task.title)" : "Отметить: \(task.title)")
            }

            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(task.title)
                    .textStyle(AppFont.bodyEmphasis.color(
                        isDoneToday && task.kind == .daily ? Token.Ink.secondary : Token.Ink.primary
                    ))
                    .strikethrough(isDoneToday && task.kind == .daily, color: Token.Ink.secondary)
                Text(task.detail)
                    .textStyle(AppFont.caption)
                    .wraps()
            }

            Spacer(minLength: Token.Space.s8)

            VStack(alignment: .trailing, spacing: Token.Space.s4) {
                Text(task.statusText(on: now))
                    .textStyle(AppFont.micro.color(statusColor))
                    .multilineTextAlignment(.trailing)
                if task.snoozeCount >= 2 {
                    Text("откладывали \(Fmt.times(task.snoozeCount))")
                        .textStyle(AppFont.micro.color(Token.Ink.secondary))
                }
            }

            if task.kind != .daily {
                Button(action: onToggle) {
                    Text("Сделали")
                        .textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
                        .frame(minHeight: Token.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "Поправить", onEdit)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onSnooze {
                Button("Потом", action: onSnooze).tint(Token.Status.waitingText)
            }
        }
        // Действие предлагается, только если строку правда можно отложить:
        // пункт в ротере, который ничего не делает, хуже отсутствующего.
        .accessibilityActions {
            if let onSnooze {
                Button("Отложить до завтра", action: onSnooze)
            }
        }
    }

    private var statusColor: Color {
        if !task.isInSeason(on: now) { return Token.Ink.secondary }
        if task.isOverdue(on: now) { return Token.Status.overdueText }
        if task.isNeverDone { return Token.Ink.secondary }
        if task.isDue(on: now) { return Token.Status.waitingText }
        return Token.Ink.secondary
    }
}

/// Выбор из готового списка. Отмечаешь то, что делаешь, — и только оно
/// попадает в приложение.
struct CareSuggestionsSheet: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [CareTask]
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    private var existing: Set<String> {
        guard let dog else { return [] }
        return Set(allTasks
            .filter { $0.dog?.persistentModelID == dog.persistentModelID }
            .map(\.title))
    }

    var body: some View {
        TGSheet(title: "Что делаешь", subtitle: "интервалы потом можно поправить", closeTitle: "Отмена") {
            ForEach(CareKind.allCases, id: \.self) { kind in
                let group = SeedData.careSuggestions.filter { $0.kind == kind }
                TGCard(spacing: 0) {
                    TGSectionHeader(title: .готовая(kind.sectionTitle))
                    ForEach(group) { suggestion in
                        row(suggestion)
                        if suggestion.id != group.last?.id { TGDivider() }
                    }
                }
            }
            TGExplainer(text: "Ничего обязательного здесь нет. Зубы отмечены потому, что налёт твердеет за сутки — остальное у каждой собаки своё.")
        } footer: {
            TGButton(title: chosen.isEmpty ? "Ничего не добавлять" : "Добавить · \(chosen.count)") {
                add()
            }
        }
        .presentationDetents([.large])
        .task {
            guard !loaded else { return }
            chosen = Set(SeedData.careSuggestions.filter(\.isDefault).map(\.id))
                .subtracting(existing)
            loaded = true
        }
    }

    private func row(_ suggestion: SeedData.CareSuggestion) -> some View {
        let already = existing.contains(suggestion.title)
        return Button {
            guard !already else { return }
            if chosen.contains(suggestion.id) { chosen.remove(suggestion.id) } else { chosen.insert(suggestion.id) }
            Haptics.tap()
        } label: {
            HStack(spacing: Token.Space.s12) {
                Image(systemName: already ? "checkmark.circle.fill"
                                          : (chosen.contains(suggestion.id) ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 22))
                    .foregroundStyle(already ? Token.Ink.secondary
                                             : (chosen.contains(suggestion.id) ? Token.Action.doneText : Token.Ink.secondary))
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(suggestion.title).textStyle(AppFont.body)
                    Text(already ? "уже заведено" : suggestion.detail)
                        .textStyle(AppFont.caption)
                        .wraps()
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
            .opacity(already ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private func add() {
        if let dog { SeedData.addCare(chosen, to: dog, context: context) }
        if !chosen.isEmpty { Haptics.success() }
        dismiss()
    }
}
