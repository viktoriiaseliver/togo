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
        // `showFailure`, а не `showUndo`: ветка кончается `return false`,
        // то есть действие не состоялось. Здесь вибрации предупреждения
        // нет вовсе — поэтому ось «Haptics.warning выше вызова», которой
        // искали такие места, это место не нашла по устройству.
        //
        // **Вторая дверь того же отказа — 14.10.2026.** Адрес действия
        // дописан здесь тем же приёмом, что в `EventLog.swift:85`:
        // человеку мало знать, что нельзя, ему нужно знать, куда идти.
        // У второго человека права берутся из карточки на ЕГО телефоне
        // (`FamilyResolver.меня:53`), и до неё надо добраться.
        //
        // Путь собран из существующих ключей «Семья» и «Это я» —
        // новых строк каталога ноль, переводы на fr целы.
        //
        // **Чего эта правка НЕ делает, и это названо нарочно.** Тексты
        // двух отказов остались разными: «Записывать может тот, кому это
        // разрешено» здесь и «Это записывает тот, кому разрешено»
        // в `EventLog`. Один запрет, два текста — человек, наткнувшийся
        // на оба, решит, что это разные правила. Свести их значит
        // осиротить ключ с готовым французским переводом ради
        // единообразия; решение продуктовое, вынесено менеджеру,
        // а не принято здесь молча.
        guard appState.can(permission(for: item)) else {
            let путь = "\n \(String(localized: "Семья")) → \(String(localized: "Это я"))"
            appState.showFailure((item.kind == .dose
                                  ? String(localized: "Дозы отмечает тот, кому это разрешено")
                                  : String(localized: "Записывать может тот, кому это разрешено"))
                                 + путь)
            return false
        }
        return true
    }

    // MARK: Право на уведомления — повод и запрет

    /// Давали ли дозу когда-нибудь раньше.
    ///
    /// Считается по хранилищу, а не по флагу в настройках: флаг пришлось
    /// бы заводить и поддерживать, а хранилище и так знает ответ. Запрос
    /// идёт по ВСЕМ собакам нарочно — «первая доза в жизни дневника»,
    /// а не «первая у этой собаки»: правило про человека и его согласие,
    /// а не про питомца.
    ///
    /// Отказ запроса читается как «давали», а не «не давали». Ошибка
    /// в эту сторону молчит: мы не спросим про уведомления. Ошибка
    /// в другую показала бы системное окно поверх первой же отметки
    /// у человека, который дозы отмечает годами.
    private func дозыДавалиРаньше() -> Bool {
        var запрос = FetchDescriptor<DoseRecord>(predicate: #Predicate { $0.givenAt != nil })
        запрос.fetchLimit = 1
        guard let сколько = try? context.fetchCount(запрос) else { return true }
        return сколько > 0
    }

    /// Правило нового дизайна: право на уведомления спрашиваем
    /// в момент первой дозы, после отказа больше не спрашиваем.
    ///
    /// **Решение принимает домен, а не этот метод.** Здесь только повод,
    /// системное состояние и память — три входа
    /// `NotificationPriming.shouldPrime`. Положить правило сюда значило
    /// бы завести вторую его реализацию: у Togo так было с «не кормить»
    /// — три реализации, две молчали.
    ///
    /// **Чего здесь НЕТ, и это названо, а не забыто.** Правило просит
    /// своё окно ДО системного, с объяснением. Окна нет: его рисуют,
    /// а не пишут, и завести его своей рукой значило бы выдать свой
    /// набросок за дизайн. Подключены две части правила из трёх —
    /// повод («первая доза») и запрет («после отказа не спрашиваем»);
    /// третья ждёт экрана. Пока его нет, системное окно показывается
    /// сразу, то есть ровно так, как было в онбординге, но в верный
    /// момент.
    ///
    /// **Достижимость этой ветки измерена, а не предположена, и она
    /// УЖЕ окном онбординга, но только наполовину.** Шаг онбординга
    /// (`OnboardingSteps.swift:346-361`) даёт две кнопки:
    ///
    /// ```
    /// «Разрешить уведомления»  → системное окно · granted/denied
    ///                            → сюда НЕ дойдёт, и верно: iOS
    ///                              показывает своё окно один раз
    ///                              на установку
    /// «Не сейчас»              → системного окна не было вовсе
    ///                            → notAsked → первая доза спросит
    /// ```
    ///
    /// То есть ветка живая и покрывает ровно тех, кто отложил. Снять
    /// шаг онбординга — **решение дизайна**: правило нового дизайна
    /// называет единственным поводом первую дозу, но «сколько людей
    /// после этого останутся без напоминаний вовсе» измеряется
    /// не кодом. Названо вслух, чтобы следующий не прочёл вызов здесь
    /// как доказательство, что правило работает целиком.
    ///
    /// > **Вид, принятый кадром, доказан только для тех входов,
    /// > которые в кадр попали.** Поэтому достижимость считалась
    /// > по местам вызова и по тому, что они передают, а не чтением
    /// > этой функции.
    private func спроситьПроУведомления(этоПерваяДоза: Bool) {
        // Дешёвые запреты до любого `await`: без них каждая первая доза
        // будила бы системный фреймворк ради заведомо известного «нет».
        guard этоПерваяДоза else { return }
        guard !settings.notificationsPrimed, !settings.notificationsDeclined else { return }

        Task { @MainActor in
            let система = await NotificationCenterService.primingState()
            guard NotificationPriming.shouldPrime(occasion: .firstDose,
                                                  system: система,
                                                  memory: settings.primingMemory) else { return }
            let разрешил = await NotificationCenterService.requestAuthorization()
            // Память пишется из ответа домена, а не руками: `remember`
            // возвращает новое значение, и его некуда девать, кроме как
            // записать, — поэтому вызов нельзя забыть.
            settings.primingMemory = NotificationPriming.remember(settings.primingMemory,
                                                                  accepted: разрешил)
            // `.blocked`, а не `.failed`: приложение справилось, права
            // не дали. Журнал заводился ровно ради этой разницы —
            // «не дали» чинится, «сбой» ищется не там.
            UsageLog.note(.setting, "notificationPriming",
                          outcome: разрешил ? .done : .blocked)
            guard разрешил, let dog else { return }
            // Разрешение без перепланирования — право, которым никто
            // не пользуется: напоминания считались при закрытой двери
            // и не встали.
            await ReminderScheduler.refresh(dog: dog, settings: settings, at: Date())
        }
    }

    // MARK: Отметить

    func complete(_ item: DayPlanItem, givenAt момент: Date) {
        guard let dog else { return }

        // Повод спросить про уведомления считается ДО отметки.
        //
        // Правило нового дизайна («спрашиваем в момент первой дозы»)
        // смотрит на то, давали ли дозу когда-нибудь раньше. После
        // `markGiven` ответ уже «давали» — свой же, и повод исчез бы
        // ровно в тот момент, когда наступил. Это та же форма, что
        // «проверка предусловия верна по смыслу и бесполезна по месту»:
        // между вопросом и ответом успевает вклиниться то, о чём
        // спрашивают.
        let этоПерваяДоза = item.kind == .dose && !дозыДавалиРаньше()

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
                appState.showFailure("Доза не отметилась · нажми ещё раз")
                return
            }
            отметка = dose
        }

        EventLog(context: context, appState: appState)
            .record(logKind(of: item),
                    dog: dog,
                    at: момент,
                    confirmation: "Записано · \(item.title)") { event in
                switch item.kind {
                case .meal:
                    // **Выдуманных граммов в ЗАПИСИ быть не может:
                    // запись потом читает врач.** `grams` опционально
                    // нарочно, и «не знаем сколько» пишется нулевой
                    // ссылкой, а не нулём. Нормы нет — порции нет,
                    // и отметка о кормлении остаётся честной отметкой
                    // о кормлении.
                    event.grams = dog.servingGrams > 0 ? dog.servingGrams : nil
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
                appState.showFailure("Срок не пересчитался · нажми ещё раз")
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
            // Спрашиваем ПОСЛЕ того, как доза легла в хранилище.
            // Спросить раньше значило бы просить право на напоминания
            // о событии, которого может не случиться: `markGiven`
            // возвращает пусто, и тогда никакой первой дозы не было.
            спроситьПроУведомления(этоПерваяДоза: этоПерваяДоза)
        }
    }

    // MARK: Снять отметку

    func uncomplete(_ item: DayPlanItem) {
        guard dog != nil else { return }

        // Убираем ту запись, которая этот пункт и закрыла, — ближайшую
        // к его времени.
        let kind = logKind(of: item)
        let candidates = Diary.onDay(events, день)
            .filter { $0.kind == kind }
            .sorted { abs($0.date.timeIntervalSince(item.time)) < abs($1.date.timeIntervalSince(item.time)) }

        // Что вернуть, если сохранить не выйдет. `try?` здесь стоял ровно
        // перед тостом «Снова в списке»: не сохранилось — а человек уже
        // уверен, что отметку снял, и отмечает заново поверх.
        var вернуть: [() -> Void] = []

        // У ухода часа нет, и сверять с ним нечего: убираем сегодняшнюю
        // запись про это же дело.
        if item.kind == .care {
            candidates.first { $0.careTaskID == item.careTask?.id }.map { event in
                вернуть.append { event.deletedAt = nil; event.deletedBy = nil }
                event.deletedAt = Date()
                event.deletedBy = appState.currentUserName
            }
            if let task = item.careTask {
                let было = (task.lastDone, task.streak, task.scheduledDate)
                вернуть.append { (task.lastDone, task.streak, task.scheduledDate) = было }
                task.undoDone(previousDone: careUndo.wrappedValue[task.id] ?? nil)
            }
        } else if let event = candidates.first,
                  abs(event.date.timeIntervalSince(item.time)) <= MealSchedule.doneTolerance {
            вернуть.append { event.deletedAt = nil; event.deletedBy = nil }
            event.deletedAt = Date()
            event.deletedBy = appState.currentUserName
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
            appState.showFailure("Не снялось · нажми ещё раз")
            return
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
            appState.showFailure("Не записалось · нажми ещё раз")
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
            appState.showFailure("Не получилось взять на себя · нажми ещё раз")
            return
        }
        Haptics.tap()
        appState.showUndo("Доза за тобой · 45 минут")
    }
}
