import Foundation
import SwiftData
import UserNotifications

/// Планировщик напоминаний.
///
/// До этого весь `NotificationCenterService` был написан и не вызывался
/// ни разу: приложение спрашивало разрешение в онбординге и после этого
/// молчало навсегда. Ни утренней сводки, ни дозы по часам, ни окна
/// натощак — то есть ровно те три вещи, ради которых разрешение и просили.
///
/// Правило из макета зашито здесь: **прерывать человека имеют право только
/// доза, окно натощак и лестница эскалации.** Всё остальное ждёт сводки.
@MainActor
enum ReminderScheduler {
    /// Напомнить вернуться к наблюдению.
    ///
    /// Отказ от звонка не должен быть тупиком: человек решил подождать,
    /// и приложение обязано вернуться к разговору само.
    static func remindToWatch(at date: Date) async {
        guard await isAllowed() else { return }
        await NotificationCenterService.scheduleDose(
            id: "watch-\(Int(date.timeIntervalSince1970))",
            at: date,
            title: "Как он сейчас?",
            body: "Час назад было три эпизода подряд. Если повторилось — стоит позвонить."
        )
    }

    /// Пересобрать все напоминания заново.
    ///
    /// Дешевле и надёжнее, чем следить за отдельными изменениями: их мало,
    /// а расходятся они молча.
    static func refresh(dog: Dog?, settings: Settings, at now: Date = Date()) async {
        guard await isAllowed() else { return }

        await scheduleBrief(dog: dog, settings: settings, at: now)
        await scheduleDoses(dog: dog, at: now)
        await scheduleFasting(dog: dog, at: now)
    }

    private static func isAllowed() async -> Bool {
        switch await NotificationCenterService.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: Утренняя сводка

    /// Всё повторяющееся — одним сообщением в выбранный час.
    static func scheduleBrief(dog: Dog?, settings: Settings, at now: Date = Date()) async {
        let lines = briefLines(dog: dog, at: now)
        await NotificationCenterService.scheduleMorningBrief(at: settings.briefHour, lines: lines)
    }

    /// Что попадёт в сводку. Отложенное дважды подсвечивается, но в тревогу
    /// не превращается.
    static func briefLines(dog: Dog?, at now: Date = Date()) -> [String] {
        guard let dog else { return [] }
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now

        // Срок контроля идёт ПЕРВЫМ, а дела — после: сводка обрезается
        // до четырёх строк, и порядок решает, что человек увидит.
        // Груминг, отложенный дважды, переживёт ещё день; окно
        // контроля — это последний день, когда можно сдать анализ.
        //
        // Двумя `let` с явными типами, а не одним выражением через `+`.
        // Первая редакция этой правки склеивала вызов и цепочку
        // `filter → sorted → prefix → map` одним `+`, и это ровно та
        // форма, которую я в этот же вечер мерил в `DuplicateMerge`:
        // 3199 мс типизации на одиннадцати слагаемых. Склейка двух
        // коллекций оператором `+` оставляет компилятору выводить
        // и тип элемента, и перегрузку оператора поверх всей цепочки.
        // Явный тип у каждой половины снимает перебор целиком —
        // а не уменьшает его.
        let контроль: [String] = строкиКонтроля(dog: dog, на: tomorrow, calendar: calendar)
        let дела: [String] = dog.careTasks
            .filter { $0.isDue(on: tomorrow) }
            .sorted { ($0.daysUntilDue(from: tomorrow) ?? 0) < ($1.daysUntilDue(from: tomorrow) ?? 0) }
            .prefix(4)
            .map { task in
                let status = task.statusText(on: tomorrow)
                let snoozed = task.snoozeCount >= 2 ? " · откладывали \(Fmt.times(task.snoozeCount))" : ""
                return "\(task.title) — \(status)\(snoozed)"
            }
        var строки: [String] = контроль
        строки.append(contentsOf: дела)
        return строки
    }

    // MARK: Срок контроля из назначения

    /// Окно контроля в сводке — в день открытия и в последний день.
    ///
    /// **Почему в сводке, а не отдельным пушем, хотя ТЗ говорит
    /// «два напоминания».** Правило макета, зашитое в этом файле,
    /// прямое: прерывать человека имеют право только доза, окно
    /// натощак и лестница эскалации. Срок контроля не из этих трёх.
    /// Завести ему свой пуш значило бы расширить список прерываний
    /// по ходу работы над модулем, а он закрыт решением.
    ///
    /// ТЗ при этом исполнено по существу: **два дня, а не два пуша.**
    /// В день открытия окна сводка говорит «пора на контроль»,
    /// в последний день — «последний день контроля». Это разные
    /// новости, и одним текстом их покрывать нельзя: «можно сдать
    /// до 20-го» и «сегодня последний» — разные действия человека.
    ///
    /// > **Расхождение ТЗ («два напоминания») с правилом прерываний
    /// > («только три вещи») — продуктовый вопрос, а не кодовый.**
    /// > Решено в сторону правила, потому что правило записано
    /// > решением, а «напоминание» в ТЗ не сказано пушем.
    ///
    /// Текст берётся у `ControlWindow.word`, а не пишется здесь:
    /// иначе вторая поверхность — «Здоровье», виджет — напишет своё,
    /// и три формулировки разойдутся молча.
    ///
    /// Чего здесь НЕТ, и это названо: **срок прививки**
    /// (`DogDocument.validUntil`). Поле есть, напоминания нет —
    /// и завести его нельзя, не придумав, за сколько дней напоминать.
    /// Это число не в коде и не в ТЗ: напоминание в день истечения
    /// бесполезно (прививку делают заранее), а любой выбранный запас
    /// был бы придуман за врача — ровно то, из-за чего срок контроля
    /// стал окном, а не датой. Вопрос к Виктории, не к этому файлу.
    static func строкиКонтроля(dog: Dog,
                               на день: Date,
                               calendar: Calendar) -> [String] {
        dog.prescriptions.compactMap { рецепт -> String? in
            guard let назначено = рецепт.prescribedControl,
                  let окно = ControlWindow.window(prescribedAt: рецепт.date,
                                                  назначено,
                                                  calendar: calendar)
            else { return nil }

            let ступень = ControlWindow.stage(окно, now: день, calendar: calendar)
            // Только два дня из всего окна. `.open` в середине окна
            // молчит нарочно: напоминать каждый день две недели —
            // это сторож, который кричит, а такого читать перестанут.
            // `.missed` тоже молчит: напоминание о прошедшем сроке —
            // не напоминание, а упрёк, и о нём говорит экран.
            switch ступень {
            case .lastDay:
                return "\(рецепт.medicationName) — \(ControlWindow.word(ступень))"
            case .open where calendar.isDate(день, inSameDayAs: окно.opens):
                return "\(рецепт.medicationName) — \(ControlWindow.word(ступень))"
            default:
                return nil
            }
        }
    }

    // MARK: Доза по часам

    /// Единственное, что имеет право на time-sensitive, плюс эскалация.
    static func scheduleDoses(dog: Dog?, at now: Date = Date()) async {
        guard let dog else { return }

        // Снятие идёт ПЕРЕД постановкой и до ворот `isOnTreatment`:
        // выключенное лечение — такая же причина снять запрос, как
        // отметка. Иначе ворота возвращают управление раньше уборки,
        // и запросы переживают само лечение.
        снятьНеждущие(dog)

        guard dog.isOnTreatment else { return }

        for medication in dog.medications where !medication.isPaused {
            // Пропущенная доза уведомлений не заводит — по той же причине,
            // по которой она не поднимает лестницу эскалации
            // (`DoseRecord.escalationStage`): пропуск это решение и запись,
            // а не пустота. Без этой оговорки человек нажимал
            // «пропустить» и всё равно получал пуш «Доза 21:30 не отмечена».
            for dose in medication.doses where dose.ждётОтметки {
                guard dose.scheduledAt > now else { continue }

                // За десять минут — дежурному.
                await NotificationCenterService.scheduleDose(
                    id: doseID(dose, stage: "t-10"),
                    at: dose.scheduledAt.addingTimeInterval(-10 * 60),
                    title: "Через 10 минут доза",
                    body: "\(medication.name) \(medication.doseText) в \(Fmt.clock(dose.scheduledAt))"
                )

                // Через полчаса — если так и не отметили.
                await NotificationCenterService.scheduleDose(
                    id: doseID(dose, stage: "t+30"),
                    at: dose.scheduledAt.addingTimeInterval(30 * 60),
                    title: "Доза \(Fmt.clock(dose.scheduledAt)) не отмечена",
                    body: "Кто-то один — отметьте. Если дали, поправьте время."
                )

                // Через час — запись «пропуск». Не ругаем, предлагаем поправить.
                await NotificationCenterService.scheduleDose(
                    id: doseID(dose, stage: "t+60"),
                    at: dose.scheduledAt.addingTimeInterval(60 * 60),
                    title: "Доза \(Fmt.clock(dose.scheduledAt)) пропущена",
                    body: "Отметь в Togo: дали или пропустили."
                )
            }
        }
    }

    /// Снять напоминания по дозе: её отметили или отменили.
    static func cancelDose(_ dose: DoseRecord) {
        NotificationCenterService.cancel(ids: ["t-10", "t+30", "t+60"].map { doseID(dose, stage: $0) })
    }

    /// Снять запросы у доз, которые больше не ждут отметки.
    ///
    /// **Замер 14.10.2026: `cancelDose` во всём проекте звали из одного
    /// места — `DayPlanActions:286`, то есть своей рукой.** Значит
    /// снять запрос мог только тот человек, который и отмечал дозу.
    /// Мама отмечает у себя — у Виктории телефон продолжает звонить
    /// «Доза 21:30 не отмечена» и через час «пропущена».
    ///
    /// Почему починка здесь, а не на приёме чужой отметки. Приём живёт
    /// в `TogoShared/Sync/`, а `TogoShared` синхронизированной группой
    /// входит **в оба таргета** — `Togo` и `TogoWidgetsExtension`,
    /// исключений членства в `project.pbxproj` ноль. `ReminderScheduler`
    /// лежит в `Togo/Store/`, то есть только в приложении: вызов оттуда
    /// не собрался бы в расширении. Это не стиль, это замер.
    ///
    /// И ось вышла лучше заказанной. Событие «приехала чужая отметка» —
    /// один источник из нескольких; **состояние «доза больше не ждёт»**
    /// покрывает их все разом: чужую отметку, восстановление из архива,
    /// отмену схемы, паузу, выключенное лечение. Этого списка никто
    /// не писал — он следует из условия.
    ///
    /// > Постановка уже умеет пропускать то, что не ждёт
    /// > (`scheduleDoses:166`). Пропустить — не то же, что снять:
    /// > пропуск оставляет в очереди запрос, поставленный прошлый раз.
    ///
    /// Снимаем по **всем** препаратам, включая поставленные на паузу:
    /// цикл постановки их отфильтровывает, и значит их запросы иначе
    /// не снял бы никто.
    private static func снятьНеждущие(_ dog: Dog) {
        var снимаем: [String] = []
        let лечениеИдёт = dog.isOnTreatment
        for medication in dog.medications {
            let схемаЖдёт = лечениеИдёт && !medication.isPaused
            for dose in medication.doses {
                // Определение «доза ждёт» переехало в модель
                // (`DoseRecord.ждётОтметки`): его спрашивает ещё и приём
                // чужой отметки в `FamilySync.apply`, а два разбора
                // одного правила расходятся молча.
                guard !(схемаЖдёт && dose.ждётОтметки) else { continue }
                снимаем.append(doseID(dose, stage: "t-10"))
                снимаем.append(doseID(dose, stage: "t+30"))
                снимаем.append(doseID(dose, stage: "t+60"))
            }
        }
        guard !снимаем.isEmpty else { return }
        NotificationCenterService.cancel(ids: снимаем)
    }

    private static func doseID(_ dose: DoseRecord, stage: String) -> String {
        "dose-\(dose.id.uuidString)-\(stage)"
    }

    // MARK: Окно натощак

    /// Не ошибка, а «подожди»: одно уведомление на конец окна.
    static func scheduleFasting(dog: Dog?, at now: Date = Date()) async {
        guard let dog, let window = DoseScheduler.fastingEnds(for: dog, at: now) else { return }
        await NotificationCenterService.scheduleFastingEnd(
            id: "fasting-\(Int(window.until.timeIntervalSince1970))",
            at: window.until,
            dogName: dog.displayName
        )
    }
}
