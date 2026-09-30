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
    ///
    /// Это ступень лестницы эскалации, а не доза: до 30.09 она шла
    /// путём дозы и категорией `dose`, а категория `escalation` не
    /// использовалась нигде.
    static func remindToWatch(at date: Date) async {
        guard await isAllowed() else { return }
        await NotificationCenterService.scheduleEscalation(
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

        return dog.careTasks
            .filter { $0.isDue(on: tomorrow) }
            .sorted { ($0.daysUntilDue(from: tomorrow) ?? 0) < ($1.daysUntilDue(from: tomorrow) ?? 0) }
            .prefix(4)
            .map { task in
                let status = task.statusText(on: tomorrow)
                let snoozed = task.snoozeCount >= 2 ? " · откладывали \(Fmt.times(task.snoozeCount))" : ""
                return "\(task.title) — \(status)\(snoozed)"
            }
    }

    // MARK: Доза по часам

    /// Кому на этом телефоне звенеть лестницей доз.
    ///
    /// Ставит экран, который знает семью (`TodayScreen`), до пересборки.
    /// Хранится здесь, а не передаётся аргументом: пересборку зовут
    /// и из отметки пункта плана, и из обмена — и каждый такой вызов
    /// без аудитории вернул бы звон на все телефоны.
    static var audience: DoseReminderAudience = .все

    /// Единственное, что имеет право на time-sensitive, плюс эскалация.
    ///
    /// **Пересобирается по хранилищу целиком, а не дополняется.** До 30.09
    /// здесь только добавляли: доза, отмеченная на другом телефоне,
    /// оставляла на этом запланированные t+30 и t+60, и через полчаса
    /// человек получал «Доза не отмечена» про данную таблетку. Теперь
    /// ступени каждого препарата собаки снимаются и ставятся заново —
    /// только для доз, решения по которым ещё нет.
    ///
    /// **Завтра — тоже.** Отметки приёма заводятся на день при открытии
    /// экрана, и доза в 07:00 не напоминала, пока приложение не открыли
    /// утром. Ступени считаются от расписания на сегодня и завтра;
    /// ключ — препарат и минута, а не id отметки, поэтому отметка,
    /// заведённая утром, дубля не даёт.
    static func scheduleDoses(dog: Dog?, at now: Date = Date()) async {
        guard let dog else { return }
        await cancelDoseReminders(of: dog)
        guard dog.isOnTreatment else { return }

        for planned in plannedDoses(dog: dog, at: now) {
            let medication = planned.medication
            let at = planned.at
            for stage in DoseReminderStage.allCases where audience.получает(stage) {
                let fire = at.addingTimeInterval(stage.offset)
                guard fire > now else { continue }
                let текст = text(stage, medication: medication, at: at)
                await NotificationCenterService.scheduleDose(
                    id: doseID(medicationID: medication.id, at: at, stage: stage),
                    at: fire, title: текст.title, body: текст.body
                )
            }
        }
    }

    /// Какие дозы ждут решения: по расписанию на сегодня и завтра.
    ///
    /// Пропущенная доза уведомлений не заводит — по той же причине,
    /// по которой она не поднимает лестницу эскалации
    /// (`DoseRecord.escalationStage`): пропуск это решение и запись,
    /// а не пустота. Без этой оговорки человек нажимал
    /// «пропустить» и всё равно получал пуш «Доза 21:30 не отмечена».
    static func plannedDoses(dog: Dog, at now: Date,
                             calendar: Calendar = .current) -> [(medication: Medication, at: Date)] {
        guard dog.isOnTreatment else { return [] }
        let today = calendar.startOfDay(for: now)
        let days = [today, calendar.date(byAdding: .day, value: 1, to: today) ?? today]
        var planned: [(medication: Medication, at: Date)] = []

        for medication in dog.medications where !medication.isPaused {
            for day in days {
                for minute in Set(medication.times).sorted() {
                    let at = calendar.date(minuteOfDay: minute, on: day)
                    // Любая отметка на эту минуту, а не первая: у каждого
                    // телефона своя отметка дня (`ensureDoses`), и чужое
                    // «дано» приезжает рядом с нашей открытой, с другим id.
                    // С `first` пересборка находила нашу открытую и снова
                    // ставила «Доза не отмечена» про данную таблетку.
                    let решена = medication.doses.contains {
                        calendar.isDate($0.scheduledAt, equalTo: at, toGranularity: .minute)
                            && ($0.isGiven || $0.skippedAt != nil || $0.cancelledAt != nil)
                    }
                    if решена { continue }
                    planned.append((medication: medication, at: at))
                }
            }
        }
        return planned
    }

    /// Тексты ступеней. Строками, как и раньше: каталог их пока не знает
    /// (долг вне этой правки).
    private static func text(_ stage: DoseReminderStage, medication: Medication,
                             at: Date) -> (title: String, body: String) {
        switch stage {
        case .before:
            return ("Через 10 минут доза",
                    "\(medication.name) \(medication.doseText) в \(Fmt.clock(at))")
        case .late:
            return ("Доза \(Fmt.clock(at)) не отмечена",
                    "Кто-то один — отметьте. Если дали, поправьте время.")
        case .missed:
            // Запись «пропуск». Не ругаем, предлагаем поправить.
            return ("Доза \(Fmt.clock(at)) пропущена",
                    "Отметь в Togo: дали или пропустили.")
        }
    }

    /// Снять напоминания по дозе: её отметили или отменили.
    ///
    /// **Точка входа для обмена.** Отметку дозы, пришедшую с другого
    /// телефона, снимать можно и этим вызовом, но надёжнее пересборкой:
    /// `TodayScreen` делает её сам на каждое сохранение, затронувшее
    /// дозы или семью (`ModelContext.didSave`), в том числе на
    /// сохранение обмена.
    static func cancelDose(_ dose: DoseRecord) {
        var ids = DoseReminderStage.allCases.map { legacyDoseID(dose, stage: $0) }
        if let medicationID = dose.medication?.id {
            ids += DoseReminderStage.allCases.map {
                doseID(medicationID: medicationID, at: dose.scheduledAt, stage: $0)
            }
        }
        NotificationCenterService.cancel(ids: ids)
    }

    /// Снять все ступени по препаратам собаки — и нынешние, и старого
    /// образца (по id отметки, до 30.09): иначе после обновления
    /// приложения старые дублировали бы новые.
    private static func cancelDoseReminders(of dog: Dog) async {
        let prefixes = dog.medications.map { "dose-\($0.id.uuidString)-" }
        let legacy = Set(dog.medications.flatMap(\.doses).flatMap { dose in
            DoseReminderStage.allCases.map { legacyDoseID(dose, stage: $0) }
        })
        let pending = await NotificationCenterService.pendingIDs()
        let stale = pending.filter { id in
            legacy.contains(id) || prefixes.contains { id.hasPrefix($0) }
        }
        if !stale.isEmpty { NotificationCenterService.cancel(ids: stale) }
    }

    private static func doseID(medicationID: UUID, at: Date, stage: DoseReminderStage) -> String {
        "dose-\(medicationID.uuidString)-\(Int(at.timeIntervalSince1970 / 60))-\(stage.rawValue)"
    }

    private static func legacyDoseID(_ dose: DoseRecord, stage: DoseReminderStage) -> String {
        "dose-\(dose.id.uuidString)-\(stage.rawValue)"
    }

    // MARK: Окно натощак

    /// Не ошибка, а «подожди»: одно уведомление на конец окна.
    ///
    /// Сначала снимаем уже поставленное: отметку дозы могли снять,
    /// и «Можно кормить» по её окну стало неправдой. До 30.09 оно
    /// приходило всё равно — окно считалось от дозы, которой не было.
    static func scheduleFasting(dog: Dog?, at now: Date = Date()) async {
        let stale = await NotificationCenterService.pendingIDs().filter { $0.hasPrefix("fasting-") }
        if !stale.isEmpty { NotificationCenterService.cancel(ids: stale) }
        guard let dog, let window = DoseScheduler.fastingEnds(for: dog, at: now) else { return }
        await NotificationCenterService.scheduleFastingEnd(
            id: "fasting-\(Int(window.until.timeIntervalSince1970))",
            at: window.until,
            dogName: dog.name
        )
    }
}

/// Ступень лестницы напоминаний о дозе.
nonisolated enum DoseReminderStage: String, CaseIterable, Sendable {
    /// За десять минут — дежурному.
    case before = "t-10"
    /// Через полчаса — если так и не отметили.
    case late = "t+30"
    /// Через час — пропуск.
    case missed = "t+60"

    var offset: TimeInterval {
        switch self {
        case .before: -10 * 60
        case .late: 30 * 60
        case .missed: 60 * 60
        }
    }
}

/// Кому на этом телефоне звенеть лестницей доз.
///
/// Лестница обещана так: т−10 дежурному, т+30 со-владельцам, т+60 всем
/// (`DoseRecord.escalationStage`, карточка дежурства). Уведомления
/// локальные, и до 30.09 каждый телефон звенел всеми тремя ступенями —
/// «напоминания идут дежурному» было неправдой. Разослать адресно с сервера
/// нечем, поэтому каждый телефон решает сам, по роли человека за ним.
///
/// **Не знаем, кто за телефоном, — звеним всем, как раньше.** Промолчать
/// о дозе из-за неопознанной карточки хуже лишнего звонка.
nonisolated struct DoseReminderAudience: Equatable, Sendable {
    /// Опознан ли человек за телефоном. Нет — остальное не читается.
    var знаемКтоЯ: Bool
    var яДежурный: Bool
    var дежурныйНазначен: Bool
    /// Владелец или со-владелец.
    var яВладелец: Bool
    /// Есть ли право давать дозу.
    var даюДозу: Bool

    static let все = DoseReminderAudience(знаемКтоЯ: false, яДежурный: false,
                                          дежурныйНазначен: false, яВладелец: false,
                                          даюДозу: false)

    /// Собрать по семье и своей карточке.
    ///
    /// - Parameters:
    ///   - я: своя карточка на этом телефоне; пусто — не опознали.
    ///   - дежурный: кто сейчас дежурит; пусто — никто.
    ///   - даюДозу: право текущего человека (`AppState.can(.giveDose)`).
    @MainActor
    static func по(я: FamilyMember?, дежурный: FamilyMember?, даюДозу: Bool) -> DoseReminderAudience {
        guard let я else { return .все }
        return DoseReminderAudience(
            знаемКтоЯ: true,
            яДежурный: дежурный?.id == я.id,
            дежурныйНазначен: дежурный != nil,
            яВладелец: я.role == .owner || я.role == .coOwner,
            даюДозу: даюДозу
        )
    }

    /// Звенит ли эта ступень на этом телефоне.
    func получает(_ stage: DoseReminderStage) -> Bool {
        guard знаемКтоЯ else { return true }
        switch stage {
        // Дежурному; дежурного нет — каждому, кто может дать дозу.
        case .before: return яДежурный || (!дежурныйНазначен && даюДозу)
        // Дежурному и владельцам.
        case .late: return яДежурный || яВладелец
        // Всем, кто может дать дозу.
        case .missed: return яДежурный || яВладелец || даюДозу
        }
    }
}
