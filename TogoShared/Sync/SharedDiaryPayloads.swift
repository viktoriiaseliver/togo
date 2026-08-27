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
        if merged != local.payload {
            local.apply(merged)
            try? context.save()
        }
        return changed
    }
}
