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

    /// Записать событие.
    ///
    /// - Parameters:
    ///   - confirmation: что показать в тосте. Пусто — тост не показываем
    ///     (например, когда экран сам скажет о результате крупнее).
    ///   - configure: заполнение полей, специфичных для вида записи.
    /// Насколько близко две одинаковые записи считаются одним тапом.
    ///
    /// Не выдумано: в живом дневнике нашлись три записи еды по 65 г
    /// с интервалом в две секунды — человек жал кнопку, не получая отклика,
    /// а потом удалял всё три. Отклик починен, но защита нужна всё равно:
    /// палец соскакивает, и кнопку жмут дважды.
    static let duplicateWindow: TimeInterval = 90

    @discardableResult
    func record(
        _ kind: LogKind,
        dog: Dog?,
        at date: Date = .now,
        confirmation: String?,
        haptic: Haptic = .success,
        allowDuplicate: Bool = false,
        configure: (LogEvent) -> Void = { _ in }
    ) -> LogEvent? {
        guard let dog else { return nil }

        // Права проверяются здесь, а не на каждом экране: это единственная
        // дверь, через которую в дневник попадает запись. Раньше `logBasics`
        // и `giveDose` не проверялись вовсе — то есть выданная роль
        // «только смотреть» всё равно позволяла записывать что угодно.
        guard appState.can(kind.requiredPermission) else {
            appState.showUndo("Это записывает тот, кому разрешено")
            Haptics.warning()
            return nil
        }

        if !allowDuplicate, let recent = recentDuplicate(of: kind, dog: dog, at: date) {
            appState.showUndo(duplicateMessage(kind, at: recent.date))
            Haptics.warning()
            return nil
        }

        let event = LogEvent(kind: kind, date: date, authorName: appState.currentUserName)
        configure(event)
        event.dog = dog
        context.insert(event)

        // Сохраняем сразу: у SwiftData связи применяются не мгновенно,
        // и экран, который читает их запросом, иначе покажет старое.
        try? context.save()

        haptic.play()
        if let confirmation {
            appState.showUndo(confirmation, eventID: event.id)
        }
        return event
    }

    /// Такая же запись минуту назад — почти наверняка второй тап,
    /// а не второе кормление.
    private func recentDuplicate(of kind: LogKind, dog: Dog, at date: Date) -> LogEvent? {
        // Повторяемое по смыслу не ловим: собака и правда писает трижды
        // за прогулку, а воду пьёт когда хочет.
        guard Self.deduplicated.contains(kind) else { return nil }

        return Diary.active(dog.events)
            .filter { $0.kind == kind && abs(date.timeIntervalSince($0.date)) < Self.duplicateWindow }
            .max { $0.date < $1.date }
    }

    /// Виды записей, где два тапа подряд почти наверняка ошибка.
    private static let deduplicated: Set<LogKind> = [.meal, .walk, .care, .dose, .weight]

    private func duplicateMessage(_ kind: LogKind, at date: Date) -> String {
        "\(kind.title) уже записана в \(Fmt.clock(date))"
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
