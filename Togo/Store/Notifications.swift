import Foundation
import UserNotifications

/// Всё повторяющееся собирается в одну сводку в выбранный час.
/// Прерывают только доза по расписанию, окно натощак и лестница эскалации.
enum NotificationCenterService {
    enum Category: String {
        case morningBrief = "brief"
        case dose = "dose"
        case fasting = "fasting"
        case escalation = "escalation"
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        } catch {
            log.error("Не удалось запросить разрешение: \(error.localizedDescription)")
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Системное состояние в том виде, в каком его ждёт правило
    /// `NotificationPriming`.
    ///
    /// Перевод живёт здесь, а не в домене, нарочно: домен не ходит
    /// в `UserNotifications` и потому проверяется тестом без
    /// симулятора и без разрешений. Если бы он спрашивал систему сам,
    /// мы проверяли бы одну реализацию наблюдениями за другой.
    ///
    /// `.provisional` считается разрешением: тихие уведомления уже
    /// доставляются, и спрашивать второй раз незачем. `.ephemeral` —
    /// App Clip, которого у Togo нет; обрабатывается как разрешение,
    /// чтобы не спрашивать там, где системное окно не появится.
    static func primingState() async -> NotificationPriming.SystemState {
        switch await authorizationStatus() {
        case .notDetermined:
            return .notAsked
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .granted
        @unknown default:
            // Незнакомое состояние — НЕ `.notAsked`. Ошибка в эту
            // сторону показала бы наше окно там, где системное уже
            // отработало, то есть дала бы обещание, которого
            // приложение выполнить не может.
            return .granted
        }
    }

    /// Один пуш в выбранный час со всеми сроками сразу.
    static func scheduleMorningBrief(at hour: Int, lines: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Category.morningBrief.rawValue])
        guard !lines.isEmpty else { return }

        let content = UNMutableNotificationContent()
        // Через каталог: `content.title` — это `String`, и присвоение
        // литерала каталог не спрашивает вовсе. Ключ в каталоге при
        // этом есть и переведён — то есть сторож полноты всё это время
        // отвечал «переведено» про строку, которая до перевода
        // не доезжала. Пуш рисуется, когда приложение закрыто, и ни
        // один кадр его не ловит.
        content.title = String(localized: "Togo · утренняя сводка")
        content.body = lines.prefix(4).joined(separator: "\n")
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = Category.morningBrief.rawValue

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: Category.morningBrief.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    /// Доза — единственное, что имеет право на time-sensitive.
    static func scheduleDose(id: String, at date: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.dose.rawValue

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Текст уведомления об окне натощак — отдельно от его отправки.
    ///
    /// Кличка приходит параметром и пустой быть может: место вызова
    /// её защищает (`ReminderScheduler` передаёт `dog.displayName`),
    /// а функция — нет, и этого достаточно, чтобы однажды сломалось.
    /// Без отката текст выходил «Окно натощак закончилось.  может
    /// есть.» — с двойным пробелом на месте подлежащего.
    ///
    /// **Это одно из трёх уведомлений с `.timeSensitive`.** Оно будит,
    /// человек читает его один раз с экрана блокировки, и переспросить
    /// ему некого.
    ///
    /// **Шов заведён 07.10.2026 ради проверяемости, и только ради неё.**
    /// Откат `Fmt.dogNameOrFallback` чинит дефект — и не делает строку
    /// утверждаемой: пока она собиралась внутри `scheduleFastingEnd`,
    /// она никуда не возвращалась, уходила в
    /// `UNMutableNotificationContent` и дальше в систему. Ни кадра,
    /// ни значения. Это разные вещи, и вторая не следует из первой:
    /// **починить и дать проверить — два дела.**
    ///
    /// Поверхность была не «непроверенной», а НЕПРОВЕРЯЕМОЙ, и первое
    /// лечится взглядом, второе только переделкой входа. У Timer ровно
    /// из-за этого отзыв про виджет жил незамеченным — смотреть было
    /// не на что.
    ///
    /// `String(localized:)` стоит ВНУТРИ: наружу уходит значение типа
    /// `String`, а литерал на месте вызова прошёл бы мимо каталога.
    static func fastingEndText(dogName: String) -> (title: String, body: String) {
        let кличка = Fmt.dogNameOrFallback(dogName)
        return (title: String(localized: "Можно кормить"),
                body: String(localized: "Окно натощак закончилось. \(кличка) может есть."))
    }

    /// Окно натощак: не ошибка, а «подожди». Одно уведомление на конец окна.
    static func scheduleFastingEnd(id: String, at date: Date, dogName: String) async {
        let текст = fastingEndText(dogName: dogName)
        let content = UNMutableNotificationContent()
        content.title = текст.title
        content.body = текст.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.fasting.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Что сейчас реально запланировано — списком, который можно
    /// прочесть глазами.
    ///
    /// **Заводится вместе с подключением правила, а не после, и это
    /// не вежливость к будущему.** Уведомления и разрешения кадром
    /// не проверяются: экрана у них нет. Без пути, который смотрит
    /// мимо показа, «запланировано» и «не запланировано» дают один
    /// зелёный — ровно как у Togo «скрыто» и «не существует», где
    /// решение «пустые записи не удаляем, а не показываем» сделало
    /// любую проверку через интерфейс бессильной.
    ///
    /// Печатает и системное состояние: ноль запланированных при
    /// `denied` — это «права нет», а при `granted` — находка. Одно
    /// число без второго не отвечает ни на что.
    static func отладочныйСписок() async -> String {
        // День и час отдельными вызовами: `Fmt.dateTime` в проекте нет,
        // и заводить его ради отладочной строки значило бы добавить
        // формат, который завтра разойдётся с остальными.
        func момент(_ дата: Date) -> String {
            Fmt.shortDay(дата) + " " + Fmt.clock(дата)
        }
        let центр = UNUserNotificationCenter.current()
        let состояние = await primingState()
        let заявки = await центр.pendingNotificationRequests()

        let право: String
        switch состояние {
        case .notAsked: право = "система ещё не спрашивала"
        case .granted: право = "разрешено"
        case .denied: право = "отказано"
        }

        guard !заявки.isEmpty else {
            return """
                Запланированных уведомлений: 0 · право: \(право).

                Ноль при отказе — это «права нет», а не «не запланировали».
                Ноль при разрешении — находка.
                """
        }

        let строки = заявки
            .map { заявка -> String in
                let когда: String
                if let t = заявка.trigger as? UNCalendarNotificationTrigger,
                   let дата = t.nextTriggerDate() {
                    когда = момент(дата) + (t.repeats ? " · повторяется" : "")
                } else if let t = заявка.trigger as? UNTimeIntervalNotificationTrigger,
                          let дата = t.nextTriggerDate() {
                    когда = момент(дата)
                } else {
                    когда = "без срока"
                }
                return "\(заявка.identifier) · \(когда) · \(заявка.content.title)"
            }
            .sorted()

        return "Запланировано: \(заявки.count) · право: \(право)\n"
            + строки.joined(separator: "\n")
    }
}
