import Foundation
import SwiftData

/// Перевод между записью дневника и снимком для обмена.
///
/// Скучный слой, и это его достоинство: правила слияния лежат отдельно
/// и проверяются тестами, а здесь только перекладывание полей. Всё, что
/// умнее перекладывания, обязано жить в `SharedDiaryMerge`.
@MainActor
extension LogEvent {
    var payload: EventPayload {
        EventPayload(
            id: id,
            dogID: dog?.id,
            kind: kindRaw,
            date: date,
            authorName: authorName,
            note: note,
            outcome: outcomeRaw,
            durationSeconds: durationSeconds,
            stoolForm: stoolFormRaw,
            stoolFlags: stoolFlagsRaw,
            grams: grams,
            milliliters: milliliters,
            fromPortion: fromPortion,
            incidentKind: incidentKindRaw,
            incidentDetail: incidentDetailRaw,
            walkEventID: walkEventID,
            careTaskID: careTaskID,
            medicationID: medicationID,
            deletedAt: deletedAt,
            deletedBy: deletedBy,
            changedAt: changedAt
        )
    }

    func apply(_ payload: EventPayload) {
        kindRaw = payload.kind
        date = payload.date
        authorName = payload.authorName
        note = payload.note
        outcomeRaw = payload.outcome
        durationSeconds = payload.durationSeconds
        stoolFormRaw = payload.stoolForm
        stoolFlagsRaw = payload.stoolFlags
        grams = payload.grams
        milliliters = payload.milliliters
        fromPortion = payload.fromPortion
        incidentKindRaw = payload.incidentKind
        incidentDetailRaw = payload.incidentDetail
        walkEventID = payload.walkEventID
        careTaskID = payload.careTaskID
        medicationID = payload.medicationID
        deletedAt = payload.deletedAt
        deletedBy = payload.deletedBy
        changedAt = payload.changedAt
    }
}

@MainActor
extension DoseRecord {
    var payload: DosePayload {
        DosePayload(
            id: id,
            medicationID: medication?.id,
            medicationName: medication?.name,
            scheduledAt: scheduledAt,
            givenAt: givenAt,
            givenBy: givenBy,
            skippedAt: skippedAt,
            skippedBy: skippedBy,
            claimedBy: claimedBy,
            claimedAt: claimedAt,
            cancelledAt: cancelledAt,
            cancelReason: cancelReason,
            changedAt: changedAt
        )
    }

    func apply(_ payload: DosePayload) {
        scheduledAt = payload.scheduledAt
        givenAt = payload.givenAt
        givenBy = payload.givenBy
        skippedAt = payload.skippedAt
        skippedBy = payload.skippedBy
        claimedBy = payload.claimedBy
        claimedAt = payload.claimedAt
        cancelledAt = payload.cancelledAt
        cancelReason = payload.cancelReason
        changedAt = payload.changedAt
    }
}

/// Приём чужих изменений в свой дневник.
///
/// Одно место, через которое всё приходящее попадает в базу — ровно так же,
/// как `EventLog` единственная дверь для своих записей. Иначе правила
/// слияния расползутся по экранам и разойдутся.
@MainActor
enum SharedDiaryInbox {

    /// Принять запись дневника с другого телефона.
    ///
    /// Возвращает `true`, если после слияния наша версия изменилась —
    /// то есть её надо отправить обратно.
    @discardableResult
    static func accept(_ payload: EventPayload, dog: Dog?, context: ModelContext) -> Bool {
        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
        ).first

        guard let local = existing else {
            let event = LogEvent(kind: .note, date: payload.date, authorName: payload.authorName)
            event.id = payload.id
            event.apply(payload)
            event.dog = dog
            context.insert(event)
            try? context.save()
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            local.apply(merged)
            try? context.save()
        }
        return changed
    }

    /// К какому препарату относится чужая отметка дозы.
    ///
    /// **Промах по id здесь — норма, а не сбой.** Схемы лечения
    /// не обмениваются: у второго человека тот же препарат заведён
    /// своей рукой и с другим UUID. Пока искали только по id, чужая
    /// отметка «дано» приходила с препаратом `nil`, доза оставалась
    /// ни на чём — и второй человек видел её открытой. Это ровно тот
    /// случай, ради которого у дозы вообще заведены свои правила:
    /// не путаница в дневнике, а вторая таблетка.
    static func medication(for payload: DosePayload, context: ModelContext) -> Medication? {
        if let id = payload.medicationID,
           let byID = try? context.fetch(
               FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
           ).first {
            return byID
        }
        guard let name = payload.medicationName else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        return match(name, among: all)
    }

    /// Имя сравнивается без регистра, без диакритики и без лишних
    /// пробелов: «Ветмедин», «ветмедин » и «Вётмедин» — одна схема,
    /// набранная двумя руками. Живая схема предпочитается отменённой
    /// и приостановленной — отметка приходит о той, которую дают.
    static func match(_ name: String, among all: [Medication]) -> Medication? {
        let wanted = folded(name)
        guard !wanted.isEmpty else { return nil }
        let same = all.filter { folded($0.name) == wanted }
        return same.first { $0.cancelledAt == nil && !$0.isPaused } ?? same.first
    }

    private static func folded(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Принять отметку дозы.
    @discardableResult
    static func accept(_ payload: DosePayload, medication: Medication?, context: ModelContext) -> Bool {
        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<DoseRecord>(predicate: #Predicate { $0.id == id })
        ).first

        guard let local = existing else {
            let dose = DoseRecord(scheduledAt: payload.scheduledAt)
            dose.id = payload.id
            dose.apply(payload)
            dose.medication = medication
            context.insert(dose)
            try? context.save()
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        // Доза могла приехать раньше, чем нашёлся препарат, — например
        // до того, как второй человек завёл у себя эту схему. Связываем
        // при первой же возможности: висящая ни на чём доза на экране
        // не показывается вовсе.
        var linked = false
        if local.medication == nil, let medication {
            local.medication = medication
            linked = true
        }
        if merged != local.payload {
            local.apply(merged)
            try? context.save()
        } else if linked {
            try? context.save()
        }
        return changed
    }
}
