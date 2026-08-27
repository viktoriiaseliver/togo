import Foundation
import SwiftData
import UserNotifications

/// Планировщик напоминаний.
///
/// До этого весь `NotificationCenterService` был написан и не вызывался
/// ни разу: приложение спрашивало разрешение в онбординге и после этого
/// молчало навсегда. Ни утреннего брифа, ни дозы по часам, ни окна
/// натощак — то есть ровно те три вещи, ради которых разрешение и просили.
///
/// Правило из макета зашито здесь: **прерывать человека имеют право только
/// доза, окно натощак и лестница эскалации.** Всё остальное ждёт брифа.
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

    // MARK: Утренний бриф

    /// Всё повторяющееся — одним сообщением в выбранный час.
    static func scheduleBrief(dog: Dog?, settings: Settings, at now: Date = Date()) async {
        let lines = briefLines(dog: dog, at: now)
        await NotificationCenterService.scheduleMorningBrief(at: settings.briefHour, lines: lines)
    }

    /// Что попадёт в бриф. Отложенное дважды подсвечивается, но в тревогу
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
                let snoozed = task.snoozeCount >= 2 ? " · откладывали \(task.snoozeCount) раза" : ""
                return "\(task.title) — \(status)\(snoozed)"
            }
    }

    // MARK: Доза по часам

    /// Единственное, что имеет право на time-sensitive, плюс эскалация.
    static func scheduleDoses(dog: Dog?, at now: Date = Date()) async {
        guard let dog, dog.isOnTreatment else { return }

        for medication in dog.medications where !medication.isPaused {
            for dose in medication.doses where !dose.isGiven && dose.cancelledAt == nil {
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
                    body: "Записано в ленту. Если дали — поправьте время записи."
                )
            }
        }
    }

    /// Снять напоминания по дозе: её отметили или отменили.
    static func cancelDose(_ dose: DoseRecord) {
        NotificationCenterService.cancel(ids: ["t-10", "t+30", "t+60"].map { doseID(dose, stage: $0) })
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
            dogName: dog.name
        )
    }
}
