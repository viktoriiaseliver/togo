import Foundation
import CloudKit

/// Перевод снимка в запись CloudKit и обратно.
///
/// Отдельным файлом от правил слияния намеренно: здесь нет ни одного
/// решения, только перекладывание полей. Всё, что можно ошибиться,
/// лежит в `SharedDiaryMerge` и проверено тестами.
nonisolated enum SharedDiaryRecords {

    static func zoneID(owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: owner)
    }

    static func recordID(_ id: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone)
    }

    // MARK: Записи дневника

    static func record(_ payload: EventPayload, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SharedDiary.RecordType.event.rawValue,
                              recordID: recordID(payload.id, in: zone))
        apply(payload, to: record)
        return record
    }

    /// Запись для отправки — поверх серверной версии, если она известна.
    ///
    /// Новый `CKRecord` каждый раз означал бы отправку без
    /// `recordChangeTag`, а такую правку сервер отбивает
    /// `serverRecordChanged`. Поэтому вторая и все следующие отправки
    /// идут на том самом объекте, который пришёл с сервера: тег на нём
    /// уже стоит. Заодно здесь же разрешается спор — чужую версию
    /// нельзя просто затереть своей, иначе отметка «дано» с того
    /// телефона пропала бы при первой же нашей правке.
    static func record(_ payload: EventPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        guard let base, base.recordID == recordID(payload.id, in: zone) else {
            return record(payload, in: zone)
        }
        let merged = eventPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: EventPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["kind"] = payload.kind
        record["date"] = payload.date
        record["authorName"] = payload.authorName
        record["note"] = payload.note
        record["outcome"] = payload.outcome
        record["durationSeconds"] = payload.durationSeconds
        record["stoolForm"] = payload.stoolForm
        record["stoolFlags"] = payload.stoolFlags
        record["grams"] = payload.grams
        record["milliliters"] = payload.milliliters
        record["fromPortion"] = payload.fromPortion ? 1 : 0
        record["incidentKind"] = payload.incidentKind
        record["incidentDetail"] = payload.incidentDetail
        record["walkEventID"] = payload.walkEventID?.uuidString
        record["careTaskID"] = payload.careTaskID?.uuidString
        record["medicationID"] = payload.medicationID?.uuidString
        record["deletedAt"] = payload.deletedAt
        record["deletedBy"] = payload.deletedBy
        record["changedAt"] = payload.changedAt
    }

    static func eventPayload(_ record: CKRecord) -> EventPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let kind = record["kind"] as? String,
              let date = record["date"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return EventPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            kind: kind,
            date: date,
            authorName: record["authorName"] as? String ?? "",
            note: record["note"] as? String,
            outcome: record["outcome"] as? String,
            durationSeconds: record["durationSeconds"] as? Int,
            stoolForm: record["stoolForm"] as? String,
            stoolFlags: record["stoolFlags"] as? [String] ?? [],
            grams: record["grams"] as? Int,
            milliliters: record["milliliters"] as? Int,
            fromPortion: (record["fromPortion"] as? Int ?? 0) == 1,
            incidentKind: record["incidentKind"] as? String,
            incidentDetail: record["incidentDetail"] as? String,
            walkEventID: (record["walkEventID"] as? String).flatMap(UUID.init),
            careTaskID: (record["careTaskID"] as? String).flatMap(UUID.init),
            medicationID: (record["medicationID"] as? String).flatMap(UUID.init),
            deletedAt: record["deletedAt"] as? Date,
            deletedBy: record["deletedBy"] as? String,
            changedAt: changedAt
        )
    }

    // MARK: Профиль собаки

    static func record(_ payload: DogPayload, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SharedDiary.RecordType.dog.rawValue,
                              recordID: recordID(payload.id, in: zone))
        apply(payload, to: record)
        return record
    }

    static func record(_ payload: DogPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        guard let base, base.recordID == recordID(payload.id, in: zone) else {
            return record(payload, in: zone)
        }
        let merged = dogPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: DogPayload, to record: CKRecord) {
        record["name"] = payload.name
        record["breed"] = payload.breed
        record["birthDate"] = payload.birthDate
        record["sex"] = payload.sex
        record["isNeutered"] = payload.isNeutered ? 1 : 0
        record["weightKg"] = payload.weightKg
        record["targetWeightLow"] = payload.targetWeightLow
        record["targetWeightHigh"] = payload.targetWeightHigh
        record["foodBrand"] = payload.foodBrand
        record["portionGrams"] = payload.portionGrams
        record["mealsPerDay"] = payload.mealsPerDay
        record["mealTimes"] = payload.mealTimes
        record["dailyNormGrams"] = payload.dailyNormGrams
        record["forbiddenFoods"] = payload.forbiddenFoods
        record["wakeMinuteOfDay"] = payload.wakeMinuteOfDay
        record["sleepMinuteOfDay"] = payload.sleepMinuteOfDay
        record["isOnTreatment"] = payload.isOnTreatment ? 1 : 0
        record["chipNumber"] = payload.chipNumber
        record["vetName"] = payload.vetName
        record["vetPhone"] = payload.vetPhone
        record["clinicName"] = payload.clinicName
        record["clinicPhone"] = payload.clinicPhone
        record["distinctiveMarks"] = payload.distinctiveMarks
        record["changedAt"] = payload.changedAt
    }

    /// Кличка обязательна: собака без клички — это не «пустое имя»,
    /// а запись, которую нечем показать в переключателе. Такую лучше
    /// не заводить вовсе, чем завести безымянной.
    static func dogPayload(_ record: CKRecord) -> DogPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return DogPayload(
            id: id,
            name: name,
            breed: record["breed"] as? String,
            birthDate: record["birthDate"] as? Date,
            sex: record["sex"] as? String ?? DogSex.unknown.rawValue,
            isNeutered: (record["isNeutered"] as? Int ?? 0) == 1,
            weightKg: record["weightKg"] as? Double ?? 0,
            targetWeightLow: record["targetWeightLow"] as? Double,
            targetWeightHigh: record["targetWeightHigh"] as? Double,
            foodBrand: record["foodBrand"] as? String ?? "",
            portionGrams: record["portionGrams"] as? Int ?? 0,
            mealsPerDay: record["mealsPerDay"] as? Int ?? 2,
            mealTimes: record["mealTimes"] as? [Int] ?? [],
            dailyNormGrams: record["dailyNormGrams"] as? Int,
            forbiddenFoods: record["forbiddenFoods"] as? [String] ?? [],
            wakeMinuteOfDay: record["wakeMinuteOfDay"] as? Int ?? 7 * 60,
            sleepMinuteOfDay: record["sleepMinuteOfDay"] as? Int ?? 23 * 60,
            isOnTreatment: (record["isOnTreatment"] as? Int ?? 0) == 1,
            chipNumber: record["chipNumber"] as? String,
            vetName: record["vetName"] as? String,
            vetPhone: record["vetPhone"] as? String,
            clinicName: record["clinicName"] as? String,
            clinicPhone: record["clinicPhone"] as? String,
            distinctiveMarks: record["distinctiveMarks"] as? String,
            changedAt: changedAt
        )
    }

    // MARK: Дозы

    static func record(_ payload: DosePayload, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SharedDiary.RecordType.dose.rawValue,
                              recordID: recordID(payload.id, in: zone))
        apply(payload, to: record)
        return record
    }

    /// То же, что и у записи дневника: вторая отправка идёт поверх
    /// серверной версии, иначе её отбивает `serverRecordChanged`.
    /// Для дозы это дороже всего: именно её второе сохранение —
    /// отметка «дано».
    static func record(_ payload: DosePayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        guard let base, base.recordID == recordID(payload.id, in: zone) else {
            return record(payload, in: zone)
        }
        let merged = dosePayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: DosePayload, to record: CKRecord) {
        record["medicationID"] = payload.medicationID?.uuidString
        record["medicationName"] = payload.medicationName
        record["scheduledAt"] = payload.scheduledAt
        record["givenAt"] = payload.givenAt
        record["givenBy"] = payload.givenBy
        record["skippedAt"] = payload.skippedAt
        record["skippedBy"] = payload.skippedBy
        record["claimedBy"] = payload.claimedBy
        record["claimedAt"] = payload.claimedAt
        record["cancelledAt"] = payload.cancelledAt
        record["cancelReason"] = payload.cancelReason
        record["changedAt"] = payload.changedAt
    }

    static func dosePayload(_ record: CKRecord) -> DosePayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let scheduledAt = record["scheduledAt"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return DosePayload(
            id: id,
            medicationID: (record["medicationID"] as? String).flatMap(UUID.init),
            medicationName: record["medicationName"] as? String,
            scheduledAt: scheduledAt,
            givenAt: record["givenAt"] as? Date,
            givenBy: record["givenBy"] as? String,
            skippedAt: record["skippedAt"] as? Date,
            skippedBy: record["skippedBy"] as? String,
            claimedBy: record["claimedBy"] as? String,
            claimedAt: record["claimedAt"] as? Date,
            cancelledAt: record["cancelledAt"] as? Date,
            cancelReason: record["cancelReason"] as? String,
            changedAt: changedAt
        )
    }
}
