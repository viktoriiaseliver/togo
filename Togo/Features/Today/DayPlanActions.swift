import SwiftUI
import SwiftData

/// Просроченная доза, по которой открыт разбор.
///
/// Эти три адресата шторок были вложены в `TodayScreen` и потому
/// недостижимы снаружи: `DayPlanActions.skipDose` не мог назвать свой
/// же аргумент. Данные, вложенные во вью, привязывают к нему всё,
/// что их касается.
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

/// Доза, по которой открыт замок: кто дал и когда.
struct LockedDose: Identifiable {
    let item: DayPlanItem
    let givenBy: String
    let givenAt: Date
    var id: String { item.id }
}

/// Что происходит с планом дня, когда человек нажимает: отметить, снять
/// отметку, пропустить дозу, взять её на себя.
///
/// **Вынесено из `TodayScreen` 28.09, и не ради длины.** Эти двести
/// пятьдесят строк жили внутри `View` — то есть позвать их из теста
/// было нельзя вовсе. Сторожить там было нечего не потому, что некому,
/// а потому что не за что взяться: чтобы дойти до `complete`, надо
/// построить экран с `@Query`, `AppState` и хранилищем.
///
/// А сторожить есть что, и цена известна. В этих строках живут три
/// уже оплаченных урока:
///
/// 1. **Отметка приёма идёт первой, запись в ленте — второй.** Раньше
///    было наоборот, отметка шла с `try?`, и при несохранении человек
///    видел «Записано · Эутирокс», лента подтверждала его же, а доза
///    оставалась неотмеченной — напоминания на `t+30` и `t+60` уже
///    сняты. Вторая доза давалась с полной уверенностью.
/// 2. **Откат руками, а не `rollback()`.** У каждой ветки свой список
///    «что вернуть»: на iOS 26 `context.rollback()` снимает признак
///    изменений и не возвращает ни значений, ни вставок.
/// 3. **Не сохранилось — не говорим «сделано».** Каждый путь либо
///    доводит до `save()`, либо возвращает всё назад и отвечает
///    тревогой.
///
/// Тип — `struct` с явным входом нарочно: его можно собрать в тесте
/// над контекстом в памяти и позвать любой метод.
@MainActor
struct DayPlanActions {
    let context: ModelContext
    let appState: AppState
    let settings: Settings
    let dog: Dog?
    /// Отсчёт ПОКАЗЫВАЕМОГО дня — только чтобы выбрать записи этого дня.
    ///
    /// Записывать им нельзя, и причин теперь две. Первая старая: экранное
    /// время тикает раз в тридцать секунд, а в фоне стоит вовсе, и 21.09
    /// на границе минуты баннер сказал «после Эутирокс в 14:03», а лента
    /// в ту же секунду — «Доза 14:04». Вторая появилась 28.09 вместе
    /// с листалкой дня: когда показывают вчера, это вообще **не сейчас**.
    /// Момент записи всегда приходит аргументом.
    let день: Date
    /// Настоящие часы. Только для того, что про «сию секунду»:
    /// «взяла на себя · 45 минут» отсчитывается от них, а не от дня,
    /// который человек листает.
    let сейчас: Date
    /// Память для отмены ухода: когда дело делали ДО этой отметки.
    /// Без неё «снять отметку» не может вернуть прежний срок.
    let careUndo: Binding<[UUID: Date?]>

    private var events: [LogEvent] { dog?.events ?? [] }

    func logKind(of item: DayPlanItem) -> LogKind {
        switch item.kind {
        case .meal: .meal
        case .dose: .dose
        case .care: .care
        }
    }

    /// Кому что можно: бытовое и дозы — разные права.
    ///
    /// Оба существовали и не проверялись нигде: выданная роль «только
    /// смотреть» всё равно позволяла отмечать еду, а «нельзя давать
    /// препараты» — отмечать приёмы.
    func permission(for item: DayPlanItem) -> Permission {
        item.kind == .dose ? .giveDose : .logBasics
    }

    @discardableResult
    func checkPermission(for item: DayPlanItem) -> Bool {
        guard appState.can(permission(for: item)) else {
            appState.showUndo(item.kind == .dose
                              ? "Дозы отмечает тот, кому это разрешено"
                              : "Записывать может тот, кому это разрешено")
            return false
        }
        return true
    }

    // MARK: Отметить

    func complete(_ item: DayPlanItem, givenAt момент: Date) {
        guard let dog else { return }

        // Отметка приёма — не то же самое, что запись в ленте: от неё
        // считается окно натощак и на неё смотрит защита от двойной дозы.
        // Она идёт ПЕРВОЙ, и пустой ответ останавливает всё: напоминания
        // остаются, в ленте не появляется ничего, человек слышит тревогу.
        var отметка: DoseRecord?
        if item.kind == .dose, let medication = item.medication {
            guard let dose = DoseScheduler.markGiven(medication, scheduledAt: item.time,
                                                     by: appState.currentUserName, at: момент,
                                                     context: context) else {
                Haptics.warning()
                appState.showUndo("Доза не отметилась · нажми ещё раз")
                return
            }
            отметка = dose
        }

        let запись = EventLog(context: context, appState: appState)
            .record(logKind(of: item),
                    dog: dog,
                    at: момент,
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
                    // не видно, какой препарат отметили, если название
                    // успели поменять.
                    event.medicationID = item.medication?.id
                }
            }

        // Уход — не только строка в ленте: от отметки считается,
        // когда дело понадобится в следующий раз.
        if item.kind == .care, let task = item.careTask {
            let было = (task.lastDone, task.streak, task.scheduledDate)
            careUndo.wrappedValue[task.id] = task.lastDone
            task.markDone(at: момент)
            do {
                try context.save()
            } catch {
                // Запись в ленте уже легла — она сохранилась своим
                // сохранением выше. Не легло само «когда делали
                // в последний раз», а от него считается следующий срок.
                (task.lastDone, task.streak, task.scheduledDate) = было
                careUndo.wrappedValue[task.id] = nil
                Haptics.warning()
                appState.showUndo("Срок не пересчитался · нажми ещё раз")
                return
            }
        }

        if let доза = отметка {
            // Отметка легла в хранилище — вот теперь догонять не надо.
            // Снимать напоминания раньше сохранения было бы тем же самым,
            // что и `try?`: уверенностью без основания.
            ReminderScheduler.cancelDose(доза)
            // Напоминания считаются от НАСТОЯЩЕГО сейчас, а не от момента
            // записи: отметив дозу задним числом в 07:00, человек остаётся
            // в девяти утра. `момент` годится записать и не годится
            // планировать будущее.
            Task { await ReminderScheduler.refresh(dog: dog, settings: settings, at: Date()) }
        }

        // «Отменить» на тосте должно значить то же, что повторный тап
        // по кругу. Раньше тост знал только запись в ленте: строка
        // уходила, а доза оставалась отмеченной, окно натощак живым,
        // срок ухода сдвинутым — и повторить дозу было нельзя.
        if let запись {
            let id = запись.id
            appState.откатыватьПунктом(запись: id) { [self] in
                uncomplete(item, запись: id)
            }
        }
    }

    // MARK: Снять отметку

    /// - Parameter запись: какая запись в ленте закрыла пункт, если это
    ///   известно точно — так бывает у «Отменить» на тосте отметки. Пусто —
    ///   ищем ближайшую к часу пункта, как при повторном тапе по кругу.
    func uncomplete(_ item: DayPlanItem, запись точная: UUID? = nil) {
        guard let dog else { return }

        // Убираем ту запись, которая этот пункт и закрыла, — ближайшую
        // к его времени.
        let kind = logKind(of: item)
        let candidates: [LogEvent]
        if let точная {
            // Отмечали задним числом через «когда дали» — запись может
            // лежать дальше допуска от часа пункта; поиск по близости
            // её бы не нашёл.
            // Из хранилища, а не из связи `dog.events`: связь применяется
            // не мгновенно, а запись создана секунды назад.
            let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == точная })
            candidates = ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
        } else {
            candidates = Diary.onDay(events, день)
                .filter { $0.kind == kind }
                .sorted { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }
        }

        // Какую запись в ленте снимаем. У ухода часа нет, и сверять с ним
        // нечего: берём сегодняшнюю запись про это же дело.
        let снимаем: LogEvent?
        if item.kind == .care {
            снимаем = candidates.first { $0.careTaskID == item.careTask?.id }
        } else if let event = candidates.first,
                  точная != nil || abs(event.date.timeIntervalSince(item.time)) <= MealSchedule.doneTolerance {
            снимаем = event
        } else {
            снимаем = nil
        }

        // Снять отметку — это удалить запись, и право у него то же, что
        // у удаления из ленты: `canEdit`, со сроком роли. До 30.09 повторный
        // тап по кругу удалял запись любой давности и любого автора — мимо
        // проверки, которую честно держал редактор записи.
        //
        // «Отменить» на тосте своей же отметки (`точная`) проходит всегда:
        // человек отменяет то, что сделал секунду назад. Проверять его
        // через `canEdit` нельзя дважды: у помощника права `editRecords`
        // нет вовсе, а отметка задним числом через «когда дали» может
        // оказаться старше суток ухаживающего.
        if точная == nil, let снимаем, !appState.canEdit(снимаем, at: сейчас) {
            Haptics.warning()
            appState.showUndo(appState.can(.editRecords)
                              ? "Отметка старше суток · снять её может владелец"
                              : "Снять отметку может тот, кому разрешено править записи")
            return
        }

        // Что вернуть, если сохранить не выйдет. `try?` здесь стоял ровно
        // перед тостом «Снова в списке»: не сохранилось — а человек уже
        // уверен, что отметку снял, и отмечает заново поверх.
        var вернуть: [() -> Void] = []

        if let event = снимаем {
            вернуть.append { event.deletedAt = nil; event.deletedBy = nil }
            event.deletedAt = Date()
            event.deletedBy = appState.currentUserName
        }
        if item.kind == .care, let task = item.careTask {
            let было = (task.lastDone, task.streak, task.scheduledDate)
            вернуть.append { (task.lastDone, task.streak, task.scheduledDate) = было }
            task.undoDone(previousDone: careUndo.wrappedValue[task.id] ?? nil)
        }

        // Доза — не только запись в ленте: от неё считается окно натощак
        // и защита от второй дозы. Сохранение у неё своё, внутри `unmark`.
        let получилось: Bool
        if item.kind == .dose, let medication = item.medication {
            получилось = DoseScheduler.unmark(medication, scheduledAt: item.time, context: context)
        } else {
            do { try context.save(); получилось = true } catch { получилось = false }
        }

        guard получилось else {
            вернуть.reversed().forEach { $0() }
            Haptics.warning()
            appState.showUndo("Не снялось · нажми ещё раз")
            return
        }

        if item.kind == .dose {
            // Доза снова не дана — значит «можно кормить» по её окну
            // натощак уже неправда, а догоняющие t+30 и t+60 снова нужны:
            // `complete` их снял. Пересборка делает и то и другое —
            // по состоянию хранилища, а не по памяти о том, что ставили.
            // Часы настоящие: снимают отметку сейчас, а не в листаемом дне.
            Task { await ReminderScheduler.refresh(dog: dog, settings: settings, at: Date()) }
        }

        Haptics.warning()
        appState.showUndo("Снова в списке · \(item.title)")
    }

    // MARK: Пропустить и взять на себя

    /// Пропуск записывается, а не просто исчезает: врач спросит именно
    /// про него, а в истории иначе останется необъяснённая дыра.
    func skipDose(_ target: MissedDoseTarget) {
        guard DoseScheduler.markSkipped(target.medication, scheduledAt: target.item.time,
                                        by: appState.currentUserName, context: context) != nil else {
            // Пропуск заводили ради врача: «отмечено» без записи
            // в истории — та же необъяснённая дыра, только с алиби.
            Haptics.warning()
            appState.showUndo("Не записалось · нажми ещё раз")
            return
        }
        Haptics.warning()
        appState.showUndo("Доза отмечена пропущенной")
    }

    /// «Беру на себя» с запасом в 45 минут — чтобы двое не дали дозу дважды.
    ///
    /// Механика была написана в модели и не вызывалась ниоткуда: защита
    /// между людьми не работала совсем.
    func claim(_ dose: DoseRecord) {
        guard appState.can(.giveDose) else { return }
        let было = (dose.claimedBy, dose.claimedAt)
        dose.claimedBy = appState.currentUserName
        dose.claimedAt = сейчас
        // Договорённость видна только через хранилище. Не сохранилась —
        // второй человек её не увидит и даст дозу, а первый уверен,
        // что взял её на себя.
        do {
            try context.save()
        } catch {
            (dose.claimedBy, dose.claimedAt) = было
            Haptics.warning()
            appState.showUndo("Не получилось взять на себя · нажми ещё раз")
            return
        }
        Haptics.tap()
        appState.showUndo("Доза за тобой · 45 минут")
    }
}
