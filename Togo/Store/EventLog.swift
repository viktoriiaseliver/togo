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

    /// Правило дубля общее с записью голосом и кнопкой «Действие»:
    /// `DuplicateGuard`. Здесь оно раньше и жило — и защищало один путь
    /// из двух.
    static var duplicateWindow: TimeInterval { DuplicateGuard.window }

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
        guard appState.can(kind.requiredPermission) else {
            appState.showUndo("Это записывает тот, кому разрешено")
            Haptics.warning()
            UsageLog.note(.record, kind.rawValue, outcome: .blocked)
            return nil
        }

        // Событие собираем до сверки: чтобы понять, дубль ли это,
        // надо знать, на какое дело или лекарство оно ссылается.
        let event = LogEvent(kind: kind, date: date, authorName: appState.currentUserName)
        configure(event)

        if !allowDuplicate,
           let recent = DuplicateGuard.recent(of: kind, dog: dog, at: date,
                                             like: event, in: context) {
            appState.showUndo(DuplicateGuard.message(kind, at: recent.date))
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
            appState.showUndo("Не записалось · нажми ещё раз")
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
