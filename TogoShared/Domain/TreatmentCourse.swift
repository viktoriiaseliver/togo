import Foundation
import SwiftData

/// Курс лечения — это эпизод поверх обычного ухода, а не отдельный продукт.
///
/// Собака болеет две недели в году, а живёт все триста шестьдесят пять.
/// Поэтому медицина не занимает вкладку постоянно: она приходит вместе
/// с курсом и уходит вместе с ним. Правило одно и то же в обе стороны —
/// **есть активный курс, есть «Здоровье»; курс завершён — вкладки нет.**
///
/// Завершение курса ничего не стирает: дозы, вес, симптомы и отчёт врачу
/// остаются в истории. Уходит только вкладка и напоминания. Иначе человек
/// боится нажать «Курс завершён» — и вкладка висит месяцами с мёртвой
/// схемой, где половина препаратов уже отменена.
nonisolated enum TreatmentCourse {

    /// Идёт ли курс сейчас.
    @MainActor
    static func isActive(_ dog: Dog?) -> Bool {
        dog?.isOnTreatment == true
    }

    /// Что уйдёт вместе с курсом — показывается до подтверждения,
    /// а не после.
    @MainActor
    static func activeMedications(_ dog: Dog) -> [Medication] {
        dog.medications.filter { $0.cancelledAt == nil }
    }

    /// Завершить курс.
    ///
    /// Препараты не удаляются, а помечаются отменёнными датой: в отчёте
    /// врачу должно быть видно, что давали и до какого числа.
    @MainActor
    static func finish(
        _ dog: Dog,
        at now: Date = Date(),
        by person: String?,
        context: ModelContext
    ) {
        for medication in activeMedications(dog) {
            medication.cancelledAt = now
            medication.isPaused = true
            if medication.cancelledNote?.isEmpty ?? true {
                medication.cancelledNote = "Курс завершён \(Fmt.shortDay(now))"
            }
        }

        // Незакрытые отметки будущих доз — мусор: они бы всплыли завтра
        // в плане дня уже после конца курса.
        for medication in dog.medications {
            for dose in medication.doses
            where dose.givenAt == nil && dose.skippedAt == nil && dose.scheduledAt > now {
                context.delete(dose)
            }
        }

        dog.isOnTreatment = false
        // Курс закончен — вкладка «Здоровье» исчезнет. Если это
        // не записалось, она вернётся при следующем запуске, и человек
        // решит, что приложение её «не отпускает».
        _ = context.persist(otherwise: { dog.isOnTreatment = true })
    }

    /// Контрольный приём — единственное, что переживает курс.
    ///
    /// «Врач ждёт через две недели» — это дело в уходе, а не фраза
    /// на экране прощания. Иначе про приём вспоминают в день приёма.
    static let checkupTitle = "Контрольный приём"
    static let checkupDelayDays = 14

    @MainActor
    @discardableResult
    static func scheduleCheckup(
        for dog: Dog,
        after days: Int = checkupDelayDays,
        from now: Date = Date(),
        context: ModelContext
    ) -> CareTask? {
        let date = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        // Второй раз то же дело не заводим: экран прощания можно открыть
        // и закрыть несколько раз подряд.
        if let existing = dog.careTasks.first(where: { $0.title == checkupTitle && $0.lastDone == nil }) {
            let былаДата = existing.scheduledDate
            existing.scheduledDate = date
            // Не записалось — не отдаём дело наружу: экран покажет
            // «врач через 10 дней», а напоминания не будет.
            guard context.persist(otherwise: { existing.scheduledDate = былаДата }) else {
                return nil
            }
            return existing
        }

        let task = CareTask(title: checkupTitle,
                            detail: "После курса — врач смотрит результат",
                            kind: .dated,
                            category: .medical,
                            scheduledDate: date)
        task.remindDaysBefore = 3
        task.dog = dog
        context.insert(task)
        guard context.persist(otherwise: { context.delete(task) }) else { return nil }
        return task
    }

    /// Вернуть курс — врач продлил, или нажали не туда.
    ///
    /// Отмена решения обязана быть такой же дешёвой, как решение: без неё
    /// «Курс завершён» становится кнопкой, которую боятся нажимать.
    @MainActor
    static func resume(_ dog: Dog, context: ModelContext) {
        for medication in dog.medications where medication.cancelledAt != nil {
            medication.cancelledAt = nil
            medication.cancelledNote = nil
            medication.isPaused = false
        }
        dog.isOnTreatment = true
        // Возврат курса — отмена решения, и она обязана быть надёжной:
        // иначе вкладка «Здоровье» исчезнет при следующем запуске.
        _ = context.persist(otherwise: { dog.isOnTreatment = false })
    }

    /// Итог курса: сколько шло, сколько доз и какая доля вовремя.
    ///
    /// Считается по уже записанному — ни одного поля «заполните для
    /// отчёта». Единственное место в лечении, где уместна похвала,
    /// и она обязана быть заслуженной: цифры настоящие.
    struct Summary: Equatable {
        var span: TimeInterval
        var dosesGiven: Int
        var dosesOnTime: Int
        var skipped: Int

        /// Доля вовремя. Без доз процента не бывает — иначе экран
        /// поздравляет со стопроцентным результатом при нуле отметок.
        var onTimeShare: Double? {
            guard dosesGiven > 0 else { return nil }
            return Double(dosesOnTime) / Double(dosesGiven)
        }

        /// «Шесть недель позади» — неделями, пока это правда неделя.
        var headline: String {
            let days = Int(span / 86400)
            if days >= 14 {
                let weeks = days / 7
                return "\(String(localized: "\(weeks) недель")) позади"
            }
            if days >= 1 { return "\(Fmt.days(days)) позади" }
            return "Курс закончен"
        }
    }

    /// Насколько поздняя отметка ещё считается «вовремя».
    static let onTimeWindow: TimeInterval = 3600

    @MainActor
    static func summary(_ dog: Dog, now: Date = Date()) -> Summary {
        let doses = dog.medications.flatMap(\.doses)
        let given = doses.filter(\.isGiven)
        let onTime = given.filter { dose in
            guard let givenAt = dose.givenAt else { return false }
            return givenAt.timeIntervalSince(dose.scheduledAt) <= onTimeWindow
        }
        let first = doses.map(\.scheduledAt).min()
        return Summary(
            span: first.map { max(0, now.timeIntervalSince($0)) } ?? 0,
            dosesGiven: given.count,
            dosesOnTime: onTime.count,
            skipped: doses.filter(\.isSkipped).count
        )
    }

    /// Что сказать человеку перед подтверждением.
    @MainActor
    static func farewell(_ dog: Dog) -> String {
        let names = activeMedications(dog).map(\.name)
        let tail = "Записи останутся в истории и в отчёте врачу."
        switch names.count {
        case 0: return "Вкладка «Здоровье» спрячется. \(tail)"
        case 1: return "«\(names[0])» уйдёт из плана дня, вкладка «Здоровье» спрячется. \(tail)"
        default:
            return "\(names.joined(separator: ", ")) уйдут из плана дня, вкладка «Здоровье» спрячется. \(tail)"
        }
    }
}
