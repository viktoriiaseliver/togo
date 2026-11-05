import SwiftUI
import SwiftData

/// Уход и прививки. Три разных сорта дел, и путать их нельзя:
/// зубы чистят каждый день, когти стригут раз в три недели, прививку делают
/// в конкретный день. Раньше всё лежало одной кучей — и приложение в первый
/// же день кричало «сегодня» про всё сразу.
///
/// # Почему экран назван двумя словами, а не одним — отзыв 27.10.2026
///
/// Владелица, дословно: «Почему в прививках и визитах уход?». Разбор
/// показал, что группировка верна, а подпись лгала:
///
/// ```
/// секция  CareKind.dated.sectionTitle   «прививки и визиты»   ВЕРНО
/// экран   CinemaHeader / navigationTitle «Уход»               УЖЕ ПРЕДМЕТА
/// ```
///
/// Прививка — медицина, а не уход, и держать её под словом «Уход»
/// значит отвечать названием на вопрос, которого человек не задавал.
/// Лечится подписью раздела: группировать по `CareKind` правильно,
/// и трогать её незачем.
///
/// Ключ `Уход и прививки` в каталоге **уже лежал переведённым**
/// на четыре языка (`f7f938d`, слияние хендоффа) и не звался из кода
/// ни разу — то есть имя было решено раньше, чем доехало до экрана.
struct CareScreen: View {
    let dog: Dog?
    /// Только одна категория дел. Со «Здоровья» экран открывается
    /// с `.medical`: ссылка там подписана «Прививки», и зубы с ушами
    /// под ней были не к месту (отзыв 27.10: «Почему в прививках
    /// и визитах уход?»). `nil` — весь уход, как со вкладки собаки.
    var только: CareCategory? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    /// Запросом, а не через связь: только что добавленное дело в обратной
    /// связи появляется не сразу, и список выглядит неизменившимся.
    @Query private var allTasks: [CareTask]

    @State private var editing: CareTask?
    @State private var isAdding = false
    @State private var isChoosing = false
    @State private var now = Date()

    /// Заводить, править, откладывать и удалять дела — `editProfile`
    /// («Менять профиль и уход»). Отметить «сделали» — бытовая запись,
    /// её право спрашивает `EventLog` (`logBasics`).
    ///
    /// **До 29.10.2026 прав здесь не спрашивалось вовсе**: помощник
    /// и гость заводили и удаляли дела ухода у всей семьи.
    private var canEdit: Bool { appState.can(.editProfile) }

    /// Имя экрана — то же, что у строки, которая сюда ведёт.
    ///
    /// Голова типа объясняет, почему экран зовётся «Уход и прививки»,
    /// и UI-тест `Янтарь` ждёт панель с этим именем, — а заголовок
    /// оставался «Уход»: решение 27.10 доехало до строки на вкладке
    /// и не доехало до самого экрана.
    private var заголовок: LocalizedStringKey {
        только == .medical ? "Прививки" : "Уход и прививки"
    }

    private var tasks: [CareTask] {
        guard let dog else { return [] }
        // `deletedAt` спрашивается здесь, а не только у `dog.careTasks`:
        // вход другой — `@Query` отдаёт все дела базы, мимо фильтра
        // модели. Опись чтений 26.10.2026 назвала это место и ещё семь
        // таких же.
        return allTasks.filter {
            $0.dog?.persistentModelID == dog.persistentModelID && $0.deletedAt == nil
                && (только == nil || $0.category == только)
        }
    }

    var body: some View {
        TGScreen {
            CinemaHeader(заголовок, надпись: "от последнего раза", отступы: false)
            if !canEdit { ПлашкаПрава(право: .editProfile) }
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
        .navigationTitle(заголовок)
        .cinemaScreen(экран: .sub("care"))
        .usageScreen(.care)
        .toolbar {
            if dog != nil, canEdit {
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
                actionTitle: dog == nil || !canEdit ? nil : "Выбрать из списка",
                action: dog == nil || !canEdit ? nil : { isChoosing = true }
            )
            if dog != nil, canEdit {
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
                                onSnooze: kind == .daily || !canEdit ? nil : { snooze(task) },
                                onEdit: { if canEdit { editing = task } })
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
                    .disabled(!canEdit)
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
        guard canEdit, let date = guess.date(from: now) else { return }
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
        appState.showFailure(String(localized: "Не сохранилось · попробуй ещё раз"))
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
        // Часть дня названа словами: «в выбранный час» не говорит,
        // что выбор вообще есть, — а именно его и не находила
        // владелица («хочу выбирать часть дня сама», 28.10.2026).
        TGExplainer(text: "Всё это приходит одним сообщением — утром, днём или вечером, как настроишь, а не восемью подряд. Прерывают только доза и окно натощак.")
    }

    private func toggle(_ task: CareTask) {
        // Ежедневное можно снять, если отметили по ошибке: у привычки
        // нет долга, но и врать себе незачем.
        if task.kind == .daily, task.isDoneToday(on: now) {
            // Снять отметку может тот же, кто её ставит: право записи
            // (`LogKind.care`). Ставит её `EventLog` со своей проверкой,
            // а снятие шло мимо него — и у гостя галочка снималась.
            guard appState.can(LogKind.care.requiredPermission) else {
                Haptics.warning()
                appState.showFailure(LogKind.care.requiredPermission.отказ)
                return
            }
            // Снятие обязано вернуть ВЧЕРА, а не стереть историю. Здесь
            // было `lastDone = nil`: повторная отметка не узнавала
            // вчерашнюю и начинала серию с единицы — пять дней подряд
            // терялись от одного случайного касания. Серия после снятия
            // больше нуля — значит вчера тоже сделали.
            //
            // И снятие сохраняется: раньше оно жило только в памяти,
            // а тост «Снято» стоял при любом исходе.
            let былоСделано = task.lastDone
            let былаСерия = task.streak
            task.streak = max(0, task.streak - 1)
            task.lastDone = task.streak > 0
                ? Calendar.current.date(byAdding: .day, value: -1, to: now)
                : nil
            guard context.persist(otherwise: {
                task.lastDone = былоСделано
                task.streak = былаСерия
            }) else {
                Haptics.warning()
                appState.showFailure(String(localized: "Не сохранилось · попробуй ещё раз"))
                return
            }
            Haptics.warning()
            UsageLog.note(.care, "undone")
            appState.showUndo(String(localized: "Снято · \(task.title)"))
            return
        }

        // **Отметка дела и запись в дневник — одно действие, и откат
        // у них общий** (29.10.2026). `markDone()` двигает срок до записи,
        // а `EventLog` может отказать: нет права, дубль за минуту,
        // не сохранилось. Тогда в ленте записи нет, а дело стояло
        // сделанным — прививка уезжала на год вперёд без следа в дневнике.
        let былоСделано = task.lastDone
        let былаСерия = task.streak
        let былаДата = task.scheduledDate
        let былоОткладываний = task.snoozeCount
        task.markDone()
        let запись = EventLog(context: context, appState: appState)
            .record(.care, dog: dog, confirmation: confirmation(for: task)) { event in
                event.note = task.title
                event.careTaskID = task.id
            }
        if запись == nil {
            task.lastDone = былоСделано
            task.streak = былаСерия
            task.scheduledDate = былаДата
            task.snoozeCount = былоОткладываний
        }
    }

    /// Отложить на завтра. Счётчик нужен не для укора: отложенное дважды
    /// подсвечивается в сводке, но в тревогу не переходит.
    private func snooze(_ task: CareTask) {
        guard canEdit else { return }
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
        appState.showUndo(String(localized: "\(task.title) · до завтра"))
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
        // Здесь до 24.10.2026 стоял `.swipeActions(edge: .leading)` с кнопкой
        // «Потом». Он не срабатывал НИ РАЗУ по устройству: `.swipeActions`
        // живёт только на строке внутри `List`, а `CareTaskRow` лежит
        // в `TGCard { ForEach }` (:82–92). `List` в этом файле не встречается
        // ни разу (замер 24.10.2026: 0 вхождений при контроле
        // `DayTimelineList.swift` — 9), и попасть в другой контейнер строка
        // не может: `CareTaskRow` объявлен `private` (:269) и за пределами
        // файла не конструируется.
        //
        // Снято, а не переведено на `List`: перевод на `List` — чужая
        // раскладка и отдельное решение. Списочная лента со свайпом
        // (`DayTimelineList.swift`) ждала его с 22.10 и удалена 05.11.2026
        // без подключения. Записано долгом: «жест откладывания на экране
        // ухода» ждёт своего решения про `List`.
        //
        // Функция при этом НЕ ПОТЕРЯНА: ровно то же действие живёт ниже
        // через `.accessibilityActions`, и озвучке оно доступно сегодня.
        // Потерян был только жест — у тех, кто его искал пальцем.
        //
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
    @Environment(AppState.self) private var appState
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [CareTask]
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    /// Какие дела уже заведены — чтобы не предлагать их второй раз.
    ///
    /// **Надгробия отсеиваются, и это решение в пользу человека, а не
    /// симметрии.** Удалённое дело здесь — не «занятое название»:
    /// человек убрал «Капли от клещей» и вправе завести их заново.
    /// Не отсеяв надгробие, мы запретили бы ему это молча — кнопка
    /// просто не появилась бы, и причину прочесть было бы негде.
    ///
    /// Отличие от дедупа «Контроль у врача» в `TreatmentCourse`: там
    /// дело заводит КОД сам по себе, и повтор даёт два одинаковых дела
    /// без участия человека. Здесь заводит человек, нажав на название.
    private var existing: Set<String> {
        guard let dog else { return [] }
        return Set(allTasks
            .filter {
                $0.dog?.persistentModelID == dog.persistentModelID
                    && $0.deletedAt == nil
            }
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
        guard let dog, !chosen.isEmpty else {
            dismiss()
            return
        }
        // `addCare` отвечает нулём, когда не сохранилось, — ответ
        // выбрасывался, и шторка закрывалась с «успехом» без дел.
        guard SeedData.addCare(chosen, to: dog, context: context) > 0 else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не сохранилось · попробуй ещё раз"))
            return
        }
        Haptics.success()
        dismiss()
    }
}
