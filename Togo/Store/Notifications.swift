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

    // MARK: Исход постановки

    /// Чем кончилась постановка одного запроса.
    ///
    /// **Заведено 29.10.2026 вместо трёх `try? await center.add(request)`.**
    /// `try?` здесь был не сокращением, а молчаливым путём: система
    /// отказывала, функция возвращала `Void`, и ни один вызывающий
    /// не мог узнать, что напоминания не будет. У сводки цена этого —
    /// пропущенный груминг; у дозы (`.timeSensitive`) — пропущенное
    /// лекарство, и человек не узнаёт об этом ничем.
    ///
    /// Значение возвращается наружу, а не пишется в лог изнутри,
    /// по той же причине, по которой наружу уходит `fastingEndText`:
    /// **утверждать можно только про то, что вернулось.** Лог читает
    /// разработчик у Xcode, а решить, что сказать человеку, обязано
    /// место вызова.
    enum ИсходЗапроса: Equatable, Sendable {
        /// Запрос в очереди.
        case поставлен
        /// Ставить было нечего — пустая сводка. Это не отказ.
        case нечегоСтавить
        /// `add` бросил. `причина` — слова системы, не наши.
        case отказСистемы(String)
        /// Партия не влезает под потолок: система оставит ближайшие
        /// `потолокОжидающих` и остальные выбросит, ничего не сказав.
        case очередьПолна(ожидает: Int)
    }

    /// Сколько ожидающих запросов iOS держит на одно приложение.
    ///
    /// **Это число нельзя узнать из кода отказа, потому что отказа
    /// нет.** Шестьдесят пятый запрос `add` принимает успехом,
    /// а система молча оставляет ближайшие 64 по времени срабатывания
    /// и выбрасывает остальные. То есть `do/catch` переполнение
    /// не ловит **по устройству** — ловит его только счёт ожидающих,
    /// снятый ПЕРЕД постановкой партии.
    ///
    /// До 29.10.2026 числа 64 в этом файле не было вовсе,
    /// а `pendingNotificationRequests` читал один отладочный список.
    static let потолокОжидающих = 64

    /// Что станет с очередью, если поставить партию.
    ///
    /// **Чистая функция, и это весь шов.** В модульном прогоне очереди
    /// уведомлений не существует: `UNUserNotificationCenter` отдаёт
    /// пусто, и правило, живущее внутри вызова к системе, проверить
    /// было бы нечем — ровно та беда, что была у текста окна натощак
    /// до `fastingEndText`.
    ///
    /// - Parameters:
    ///   - ожидают: идентификаторы запросов, которые уже стоят.
    ///   - ставим: идентификаторы партии, в порядке постановки.
    ///
    /// Повторный идентификатор слот НЕ занимает: `add` с тем же `id`
    /// заменяет стоящий запрос. Наивный счёт «ожидает + размер партии»
    /// объявлял бы переполнение на каждой пересборке — у доз
    /// идентификаторы стабильные (`dose-<uuid>-t+30`), и партия почти
    /// целиком состоит из замен.
    static func планПартии(ожидают: Set<String>,
                           ставим: [String],
                           потолок: Int = потолокОжидающих) -> ПланПартии {
        var новые = Set<String>()
        for идентификатор in ставим where !ожидают.contains(идентификатор) {
            новые.insert(идентификатор)
        }
        return ПланПартии(ожидает: ожидают.count,
                          лишних: max(0, ожидают.count + новые.count - потолок))
    }

    struct ПланПартии: Equatable, Sendable {
        /// Сколько запросов стояло в очереди до партии.
        let ожидает: Int
        /// Сколько запросов не поместится под потолок. **Ноль значит
        /// «в этот раз влезло», а не «переполнения не бывает».**
        let лишних: Int
    }

    /// Идентификаторы запросов, которые сейчас ждут срабатывания.
    ///
    /// Второй читатель `pendingNotificationRequests` за всё время
    /// (первый — `отладочныйСписок`). Отдаёт множество, а не список:
    /// вопрос к нему один — «этот идентификатор уже стоит».
    static func ожидающие() async -> Set<String> {
        Set(await UNUserNotificationCenter.current()
            .pendingNotificationRequests()
            .map(\.identifier))
    }

    /// Ключ `userInfo`, под которым запрос дозы называет свою собаку.
    static let ключСобаки = "dog"

    /// Ждущие запросы доз ОДНОЙ собаки — по метке в `userInfo`.
    ///
    /// Заведено 29.10.2026 вместе с горизонтом доз. Пока ставились
    /// только сегодняшние дозы, лишний запрос жил до вечера; на трое
    /// суток вперёд запрос по передвинутому часу звонил бы трое суток,
    /// а снять его было нечем: идентификатор считается из часа, и
    /// старого часа у планировщика больше нет. Метка отвечает на вопрос
    /// «чьё это» без часа.
    ///
    /// Запросы, поставленные до этой правки, метки не несут и сюда
    /// не попадают. Их снимает прежняя уборка (`снятьНеждущие`) или
    /// замена тем же идентификатором; не снимает ничто только запрос
    /// по часу, который убрали в тот же день, — и он отзвонит один раз.
    static func ожидающиеДозы(собаки собака: UUID) async -> Set<String> {
        let метка = собака.uuidString
        return Set(await UNUserNotificationCenter.current()
            .pendingNotificationRequests()
            .filter { ($0.content.userInfo[ключСобаки] as? String) == метка }
            .map(\.identifier))
    }

    /// Положить запрос в очередь и сказать, что из этого вышло.
    ///
    /// Единственное место во всём приложении, где зовётся `add`.
    /// Собрано в одну функцию нарочно: три копии `try?` разошлись бы
    /// молча, а здесь форма команды одна и чинится один раз.
    private static func поставить(_ запрос: UNNotificationRequest) async -> ИсходЗапроса {
        do {
            try await UNUserNotificationCenter.current().add(запрос)
        } catch {
            log.error("Запрос «\(запрос.identifier)» не встал: \(error.localizedDescription)")
            return .отказСистемы(error.localizedDescription)
        }
        return .поставлен
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

    /// Один пуш на один день со всеми сроками этого дня.
    ///
    /// Возврат **без** `@discardableResult`, и это не стиль: умолчание
    /// на исходе вернуло бы ровно тот дефект, ради которого он заведён —
    /// исход снова можно было бы не прочитать, всё собралось бы,
    /// и тесты остались бы зелёными. Забыть его не даёт компилятор.
    ///
    /// # Почему с 29.10.2026 сводка НЕ повторяется
    ///
    /// Было `UNCalendarNotificationTrigger(…, repeats: true)` с одним
    /// идентификатором `"brief"`. Повторяющийся запрос несёт **один
    /// текст на все дни**, а текст собирался в момент последнего
    /// открытия приложения. Не открывал человек «Togo» неделю — неделю
    /// каждое утро приходило «Когти — сегодня» про когти, которые
    /// подстригли в понедельник. Сводка утверждала то, чего уже нет.
    ///
    /// Теперь это обычный разовый запрос на конкретную минуту,
    /// а дни раскладывает `ReminderScheduler.scheduleBrief` — по запросу
    /// на день, у каждого свой текст. Пустой день не ставится вовсе:
    /// сводка без строк — это пуш «ничего», и его честнее не слать.
    ///
    /// Идентификатор приходит снаружи (`brief-ГГГГММДД`). Старый
    /// `"brief"` снимает планировщик: у обновившихся он стоит
    /// повторяющимся и иначе звонил бы рядом с новыми вечно.
    static func scheduleMorningBrief(id: String, at date: Date,
                                     lines: [String]) async -> ИсходЗапроса {
        guard !lines.isEmpty else { return .нечегоСтавить }

        let content = UNMutableNotificationContent()
        // Через каталог: `content.title` — это `String`, и присвоение
        // литерала каталог не спрашивает вовсе. Ключ в каталоге при
        // этом есть и переведён — то есть сторож полноты всё это время
        // отвечал «переведено» про строку, которая до перевода
        // не доезжала. Пуш рисуется, когда приложение закрыто, и ни
        // один кадр его не ловит.
        //
        // «Утренняя» снято 28.10.2026: час сводки выбирается от 5 до 21
        // (`NotificationSettingsScreen`, отзыв «хочу выбирать часть дня
        // сама»), и заголовок называл её утренней в 19:00. Имя
        // `Category.morningBrief` и имя функции не тронуты нарочно —
        // `"brief"` остаётся нитью (`threadIdentifier`), и по нему же
        // планировщик снимает запрос старой формы.
        content.title = String(localized: "Togo · сводка по уходу")
        content.body = lines.prefix(4).joined(separator: "\n")
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = Category.morningBrief.rawValue

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date),
                repeats: false)
        )
        return await поставить(request)
    }

    /// Доза — единственное, что имеет право на time-sensitive.
    ///
    /// Исход возвращается и **читается обязательно** (см. запрет
    /// на `@discardableResult` у сводки выше): это напоминание
    /// медицинское, и его молчаливая пропажа дороже всех остальных.
    ///
    /// `собака` кладётся в `userInfo` запроса (`ключСобаки`), и это
    /// единственный способ потом узнать, ЧЕЙ это запрос. Идентификатор
    /// дозы (`dose-<uuid>-t+30`) собаку не называет, а планировщику
    /// с 29.10.2026 надо снимать СВОИ устаревшие запросы — передвинутый
    /// час, снятую схему — и не трогать запросы второй собаки. Без
    /// собаки (`nil`) идёт «Как он сейчас?»: он ни к одной схеме
    /// не привязан, и уборка доз его не касается.
    static func scheduleDose(id: String, at date: Date,
                             title: String, body: String,
                             собака: UUID?) async -> ИсходЗапроса {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.dose.rawValue
        if let собака {
            content.userInfo = [ключСобаки: собака.uuidString]
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        return await поставить(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
    static func scheduleFastingEnd(id: String, at date: Date,
                                   dogName: String) async -> ИсходЗапроса {
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
        return await поставить(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Остановка в дороге — обещана экраном поездки: «Остановки каждые
    /// 2 часа… Приложение напомнит» (`TransportKind.windowsExplainer`).
    /// До 29.10.2026 это обещание было текстом без постановщика.
    ///
    /// `.active`, а не `.timeSensitive`: это совет водителю, а не
    /// назначение врача, и прерывать фокус ради него нельзя.
    static func scheduleTripStop(id: String, at date: Date,
                                 title: String, body: String) async -> ИсходЗапроса {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "trip"
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        return await поставить(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
                Запланированных уведомлений: 0 из \(потолокОжидающих) · право: \(право).

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

        // Потолок печатается РЯДОМ с числом, а не в шапке и не в чужой
        // записи: «запланировано 61» без второго числа не отвечает
        // ни на что, а «61 из 64» — отвечает. Шапку читают один раз,
        // строку с числом — каждый раз.
        return "Запланировано: \(заявки.count) из \(потолокОжидающих) · право: \(право)\n"
            + строки.joined(separator: "\n")
    }
}
