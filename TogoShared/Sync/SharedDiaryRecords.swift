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
        record["passportNumber"] = payload.passportNumber
        record["insuranceNumber"] = payload.insuranceNumber
        record["vetName"] = payload.vetName
        record["vetPhone"] = payload.vetPhone
        record["clinicName"] = payload.clinicName
        record["clinicPhone"] = payload.clinicPhone
        record["distinctiveMarks"] = payload.distinctiveMarks
        record["sitterFood"] = payload.sitterFood
        record["sitterDose"] = payload.sitterDose
        record["sitterWalks"] = payload.sitterWalks
        record["sitterForbidden"] = payload.sitterForbidden
        record["sitterEscalation"] = payload.sitterEscalation
        record["rewards"] = payload.rewards
        record["markerKind"] = payload.markerKind
        record["sessionLengthMinutes"] = payload.sessionLengthMinutes
        record["trainingFoodFromPortion"] = payload.trainingFoodFromPortion ? 1 : 0
        record["changedAt"] = payload.changedAt
    }

    /// Кличка обязательна: собака без клички — это не «пустое имя»,
    /// а запись, которую нечем показать в переключателе. Такую лучше
    /// не заводить вовсе, чем завести безымянной.
    ///
    /// **Полтора месяца здесь стояло `let name = record["name"] as? String`,
    /// и это вопрос «есть ли ключ», а не «есть ли кличка».** Пустая
    /// строка проходила насквозь: ключ есть, тип верен. Отзыв 06.10.2026
    /// по сборке 271 — «Много пустых собак», восемь строк без подписи
    /// с «0,0 г», то есть ровно `Dog` со значениями по умолчанию.
    ///
    /// Опровержение лежало **в двух строках выше дефекта**: абзац над
    /// `guard` прямым текстом различает «без клички» и «пустое имя» —
    /// и `guard` ловил только первое. Тест рядом (`SharedDogTests`)
    /// подтверждал ответ на тот же слабый вопрос: он ставил
    /// `record["name"] = nil`.
    ///
    /// > **Проверка на отсутствие ключа выполняется и при пустом
    /// > значении, то есть при самом дефекте.**
    ///
    /// Правило живёт в одном месте — `DogPayload.hasUsableName`, —
    /// и зовётся отсюда и из `SharedDiaryInbox.accept`. Два вызова
    /// одного правила, а не две независимые реализации: третья
    /// реализация у нас уже молчала в двух случаях из трёх.
    static func dogPayload(_ record: CKRecord) -> DogPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              DogPayload.hasUsableName(name),
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
            passportNumber: record["passportNumber"] as? String,
            insuranceNumber: record["insuranceNumber"] as? String,
            vetName: record["vetName"] as? String,
            vetPhone: record["vetPhone"] as? String,
            clinicName: record["clinicName"] as? String,
            clinicPhone: record["clinicPhone"] as? String,
            distinctiveMarks: record["distinctiveMarks"] as? String,
            // Пусто вместо `nil`: у листа ситтера тип не опциональный,
            // и запись старой сборки, этих ключей не знавшей, должна
            // читаться как «не заполнено», а не падать.
            sitterFood: record["sitterFood"] as? String ?? "",
            sitterDose: record["sitterDose"] as? String ?? "",
            sitterWalks: record["sitterWalks"] as? String ?? "",
            sitterForbidden: record["sitterForbidden"] as? String ?? "",
            sitterEscalation: record["sitterEscalation"] as? String ?? "",
            rewards: record["rewards"] as? [String] ?? [],
            markerKind: record["markerKind"] as? String ?? MarkerKind.clicker.rawValue,
            // Откат — ровно значение по умолчанию у модели (`Dog.swift:75–77`:
            // `true`, `.clicker`, 3), а не «ноль» и не круглое число.
            // У `trainingFoodFromPortion` это решает: модель говорит
            // «лакомства ИЗ порции», и откат в `false` сказал бы гостю
            // обратное — он посчитал бы дневную норму иначе хозяйки,
            // то есть ровно то расхождение, ради которого поле и поехало.
            sessionLengthMinutes: record["sessionLengthMinutes"] as? Int ?? 3,
            trainingFoodFromPortion: (record["trainingFoodFromPortion"] as? Int ?? 1) == 1,
            changedAt: changedAt
        )
    }

    // MARK: Уход и лечение

    static func record(_ payload: CarePayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.care.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = carePayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: CarePayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["title"] = payload.title
        record["detail"] = payload.detail
        record["kind"] = payload.kind
        record["category"] = payload.category
        record["intervalDays"] = payload.intervalDays
        record["scheduledDate"] = payload.scheduledDate
        record["remindDaysBefore"] = payload.remindDaysBefore
        record["lastDone"] = payload.lastDone
        record["streak"] = payload.streak
        record["seasonStartMonth"] = payload.seasonStartMonth
        record["seasonEndMonth"] = payload.seasonEndMonth
        record["snoozeCount"] = payload.snoozeCount
        record["changedAt"] = payload.changedAt
    }

    static func carePayload(_ record: CKRecord) -> CarePayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let title = record["title"] as? String,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return CarePayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            title: title,
            detail: record["detail"] as? String ?? "",
            kind: record["kind"] as? String ?? CareKind.periodic.rawValue,
            category: record["category"] as? String ?? CareCategory.grooming.rawValue,
            intervalDays: record["intervalDays"] as? Int ?? 30,
            scheduledDate: record["scheduledDate"] as? Date,
            remindDaysBefore: record["remindDaysBefore"] as? Int ?? 14,
            lastDone: record["lastDone"] as? Date,
            streak: record["streak"] as? Int ?? 0,
            seasonStartMonth: record["seasonStartMonth"] as? Int,
            seasonEndMonth: record["seasonEndMonth"] as? Int,
            snoozeCount: record["snoozeCount"] as? Int ?? 0,
            changedAt: changedAt
        )
    }

    static func record(_ payload: MedicationPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.medication.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = medicationPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: MedicationPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["name"] = payload.name
        record["doseText"] = payload.doseText
        record["times"] = payload.times
        record["fastingMinutes"] = payload.fastingMinutes
        record["fastingBeforeMinutes"] = payload.fastingBeforeMinutes
        record["minutesAfterMeal"] = payload.minutesAfterMeal
        record["isPaused"] = payload.isPaused ? 1 : 0
        record["prescriber"] = payload.prescriber
        record["cancelledAt"] = payload.cancelledAt
        record["cancelledNote"] = payload.cancelledNote
        record["changedAt"] = payload.changedAt
    }

    /// Имя обязательно: схема без названия — это приём, о котором
    /// человек не знает, что даёт.
    static func medicationPayload(_ record: CKRecord) -> MedicationPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return MedicationPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            name: name,
            doseText: record["doseText"] as? String ?? "",
            times: record["times"] as? [Int] ?? [],
            fastingMinutes: record["fastingMinutes"] as? Int ?? 0,
            fastingBeforeMinutes: record["fastingBeforeMinutes"] as? Int ?? 0,
            minutesAfterMeal: record["minutesAfterMeal"] as? Int ?? 0,
            isPaused: (record["isPaused"] as? Int ?? 0) == 1,
            prescriber: record["prescriber"] as? String,
            cancelledAt: record["cancelledAt"] as? Date,
            cancelledNote: record["cancelledNote"] as? String,
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
