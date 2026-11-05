import SwiftUI
import SwiftData

/// Единственное место, где в приложении появляется запись в ленте.
///
/// Раньше один и тот же пятистрочный кусок был скопирован в десяти экранах:
/// создать событие, привязать к собаке, вставить, дать вибрацию, показать
/// тост. Копии расходились — где-то забывался отклик, где-то сохранение,
/// и человек видел «нажала, и ничего не произошло».
///
/// Теперь путь один, и в нём три обязательные вещи:
/// **записать, сохранить, ответить человеку.**
@MainActor
struct EventLog {
    let context: ModelContext
    let appState: AppState

    // Правило дубля общее с записью голосом и кнопкой «Действие»:
    // `DuplicateGuard` (`TogoShared/Domain/DuplicateGuard.swift`).
    // Здесь оно раньше и жило — и защищало один путь из двух.
    //
    // Обёртка `static var duplicateWindow: TimeInterval
    // { DuplicateGuard.window }` стояла здесь и удалена 27.10.2026.
    // Замер: переезд правила — `2d412ba` («Голосом можно было покормить
    // дважды»), и обёртка его пережила, не получив ни одного читателя;
    // окно спрашивают у хозяина прямо — `DuplicateGuardTests.swift:71`,
    // `Tools/замер_дублей.py:38`. Сам сторож в этом файле жив
    // и ниже: `DuplicateGuard.recent(…)` на :110 (его наличие
    // стережёт `SingleDoorTests:153`).
    //
    // Почему удалено, а не оставлено «на всякий»: второе имя у одной
    // величины — приглашение развести их молча. Проверка:
    //     git grep -n "duplicateWindow"        ← ожидается ТОЛЬКО эта
    //                                            запись, ни строки кода:
    //                                            ноль не придёт, греп
    //                                            найдёт сам комментарий
    //     git grep -n "DuplicateGuard.window"  ← контроль, обязан найти

    /// Записать событие.
    ///
    /// - Parameters:
    ///   - confirmation: что показать в тосте. Пусто — тост не показываем
    ///     (например, когда экран сам скажет о результате крупнее).
    ///   - configure: заполнение полей, специфичных для вида записи.
    /// - Parameter at: момент записи. Пусто — берётся у `AppState`:
    ///   сегодня это настоящие часы, а на прошлом дне — тот же час
    ///   в том дне. Одна дорога вместо десяти: листы записи о выбранном
    ///   дне не знают и знать не должны.
    @discardableResult
    func record(
        _ kind: LogKind,
        dog: Dog?,
        at date: Date? = nil,
        confirmation: String?,
        haptic: Haptic = .success,
        allowDuplicate: Bool = false,
        configure: (LogEvent) -> Void = { _ in }
    ) -> LogEvent? {
        guard let dog else { return nil }

        // Момент записи: переданный или взятый у состояния.
        let date = date ?? appState.моментЗаписи

        // Права проверяются здесь, а не на каждом экране: это единственная
        // дверь, через которую в дневник попадает запись. Раньше `logBasics`
        // и `giveDose` не проверялись вовсе — то есть выданная роль
        // «только смотреть» всё равно позволяла записывать что угодно.
        // Плашка — `showFailure`, а не `showUndo`: запись НЕ создана,
        // ниже стоит `return nil`. Через `showUndo` это уезжало под
        // галочку «готово» — то есть человек жал «покормила», в дневник
        // не попадало ничего, и приложение подтверждало успех.
        //
        // Путь не краевой: до опознания из `CKShare` гость — `.observer`
        // («читает всё, не пишет»), а `EventLog` — единственная дверь,
        // которой запись попадает в дневник. Значит это основной путь
        // второго человека, и он молча терял всё, что тот отмечал.
        // Отказ назван честно, но до 14.10.2026 он не называл ВЫХОДА,
        // и это основной путь второго человека, а не краевой случай:
        // принявший приглашение до опознания — `.observer`
        // («читает всё, не пишет», `Enums+Family.swift:89`), карточек
        // семьи у него нет вовсе (`FamilyMember` по обмену не ездит,
        // решение 08.10), а права берутся из карточки НА ЕГО телефоне.
        // То есть мама ставит сборку, принимает приглашение, жмёт
        // «покормила» — и упирается в стену без двери.
        //
        // Путь собран из ДВУХ СУЩЕСТВУЮЩИХ ключей — той же формой, что
        // `TogoApp.swift:201` у отказа приёма приглашения. Новой строки
        // здесь нет нарочно: третий текст завёл бы пробелы на en/fr/uk
        // и обнулил бы перевод самой фразы отказа, переведённой на fr.
        //
        // **Граница названа, потому что обратное прочтут как «починено
        // всё».** Эти ворота держат ЗАПИСЬ в дневник на своём телефоне.
        // Они ничего не говорят про обмен. ПРАВКА 14.10.2026, вечер:
        // здесь стояло «семи типов из тринадцати нет в контейнере
        // ни в production, ни в development». Это было верно утром
        // и неверно к вечеру того же дня: схему собрали из кода
        // (`Tools/схема_общего_дневника.py`) и задеплоили — в production
        // **12 типов из 12 и 185 полей из 185**, перемерено
        // `cktool export-schema` с двух сторон.
        //
        // Проверить за минуту, не читая этот комментарий:
        //     make cloudkit-check
        //
        // Что про обмен НЕ закрыто и этими воротами тоже не закрывается:
        // запись, отбитая по любой причине кроме трёх разобранных,
        // уходит в `SharedDiaryOutbox:74 default: continue` и покидает
        // очередь НАВСЕГДА — повтора не будет. А `SharedDiaryScreen:95`
        // печатает человеку размер очереди строкой «Своё не уехало»,
        // то есть ноль, то есть «всё отправлено». Величина и подпись
        // отвечают на разные вопросы. Это отдельная работа, не эта.
        guard appState.can(kind.requiredPermission) else {
            запрещено(kind)
            return nil
        }

        // Событие собираем до сверки: чтобы понять, дубль ли это,
        // надо знать, на какое дело или лекарство оно ссылается.
        let event = LogEvent(kind: kind, date: date, authorName: appState.currentUserName)
        configure(event)

        if !allowDuplicate,
           let recent = DuplicateGuard.recent(of: kind, dog: dog, at: date,
                                             like: event, in: context) {
            // Тот же знак, та же причина: сторож дублей кончается
            // `return nil`, записи нет. «Уже записана в 15:23» под
            // галочкой читается как «записал ещё раз», а не как отказ.
            appState.showFailure(DuplicateGuard.message(kind, at: recent.date))
            Haptics.warning()
            UsageLog.note(.record, kind.rawValue, outcome: .duplicate)
            return nil
        }

        event.dog = dog
        context.insert(event)

        // Сохраняем сразу: у SwiftData связи применяются не мгновенно,
        // и экран, который читает их запросом, иначе покажет старое.
        //
        // Сбой сохранения не проглатываем — и, главное, не отвечаем на него
        // «Записано». Раньше `catch` писал строку в журнал и шёл дальше:
        // человек получал вибрацию успеха и тост, еда считалась записанной,
        // а в базе её не было. Приложение выгружают — и записи нет совсем,
        // притом что человек своими глазами видел подтверждение.
        //
        // Заодно убираем призрака: несохранённое событие иначе остаётся
        // в `dog.events`, и лента показывает еду, которой в хранилище нет.
        // Связь снимаем отдельно от `delete` — до удачного сохранения
        // `delete` из связи не убирает. `context.rollback()` здесь не
        // годится: на iOS 26 он снимает признак изменений, но не
        // возвращает ни значения, ни вставки (проверено тестами
        // в `SilentFailureTests`).
        do {
            try context.save()
        } catch {
            log.notice("Запись не сохранилась: \(error.localizedDescription)")
            UsageLog.note(.record, kind.rawValue, outcome: .failed)
            event.dog = nil
            context.delete(event)
            Haptics.warning()
            appState.showFailure(String(localized: "Не записалось · нажми ещё раз"))
            return nil
        }
        UsageLog.note(.record, kind.rawValue)

        haptic.play()
        if let confirmation {
            // Записали не в сегодня — говорим об этом В подтверждении.
            //
            // Иначе человек, листавший вчера, увидит «Записано · Еда»
            // и решит, что записал сегодняшнюю. Догадка о часе
            // допустима только названной: у Togo уже записано, чем
            // кончается подтверждение, которому нечем соответствовать.
            let текст = appState.записьВПрошлое
                ? confirmation + " · " + Fmt.shortDay(date) + ", " + Fmt.clock(date)
                : confirmation
            appState.showUndo(текст, eventID: event.id)
        }
        return event
    }
    /// Отказ по праву — один текст на обе двери.
    private func запрещено(_ kind: LogKind) {
        appState.showFailure(String(localized: "Это записывает тот, кому разрешено")
                             + "\n " + String(localized: "Семья")
                             + " → " + String(localized: "Это я"))
        Haptics.warning()
        UsageLog.note(.record, kind.rawValue, outcome: .blocked)
    }

    /// Записать законченную прогулку с отметками — ОДНОЙ записью в базу.
    ///
    /// Вставку делает `WalkRecorder.record`, та же дверь, что у прогулки,
    /// законченной на блокировке (`TodayScreen.дописатьПрогулкуСБлокировки`,
    /// `WalkIntents`). До 04.11.2026 режим прогулки писал сам: прогулку
    /// через `record`, а отметки циклом — по `save()` на каждую, и тост
    /// «Записано · прогулка» звучал раньше, чем легла первая отметка.
    /// Отказ на третьей отметке оставлял прогулку с двумя. Теперь либо
    /// записано всё, либо ничего, а дубли отметок отсеиваются там же,
    /// где у блокировки.
    ///
    /// Здесь остаётся то, чего у `WalkRecorder` нет нарочно: право,
    /// тост с отменой и журнал действий — это экран, а не домен.
    @discardableResult
    func recordWalk(_ session: ActiveSession, dog: Dog, confirmation: String) -> LogEvent? {
        guard appState.can(LogKind.walk.requiredPermission) else {
            запрещено(.walk)
            return nil
        }
        guard let walk = WalkRecorder.record(session, dog: dog,
                                             author: appState.currentUserName,
                                             context: context) else {
            log.notice("Прогулка не сохранилась")
            UsageLog.note(.record, LogKind.walk.rawValue, outcome: .failed)
            Haptics.warning()
            appState.showFailure("Не записалось · нажми ещё раз")
            return nil
        }
        UsageLog.note(.record, LogKind.walk.rawValue)
        Haptic.success.play()
        appState.showUndo(confirmation, eventID: walk.id)
        return walk
    }


    enum Haptic {
        case success
        case tap
        case warning
        case none

        func play() {
            switch self {
            case .success: Haptics.success()
            case .tap: Haptics.tap()
            case .warning: Haptics.warning()
            case .none: break
            }
        }
    }
}
