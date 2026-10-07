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
        // Девять полей ленты с 07.10.2026. `askSignal` — «как попросил»,
        // заглавная строка продукта: второй человек видел «просится»
        // и не видел, чем именно.
        record["askSignal"] = payload.askSignal
        record["enteredAt"] = payload.enteredAt
        record["editedBy"] = payload.editedBy
        record["origin"] = payload.origin
        record["reactionTrigger"] = payload.reactionTrigger
        record["reactionDistance"] = payload.reactionDistance
        record["trainingSessionID"] = payload.trainingSessionID?.uuidString
        // Логическое — числом, как `fromPortion` строкой выше, и через
        // `nil`, а не через `0`: у записи от прежней версии поля нет
        // вовсе, и ноль был бы прочитан как «точное время», то есть
        // как ответ, которого никто не давал.
        record["isDayOnly"] = payload.isDayOnly.map { $0 ? 1 : 0 }
        record["toldFamily"] = payload.toldFamily.map { $0 ? 1 : 0 }
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
            askSignal: record["askSignal"] as? String,
            isDayOnly: (record["isDayOnly"] as? Int).map { $0 == 1 },
            enteredAt: record["enteredAt"] as? Date,
            editedBy: record["editedBy"] as? String,
            origin: record["origin"] as? String,
            reactionTrigger: record["reactionTrigger"] as? String,
            reactionDistance: record["reactionDistance"] as? String,
            toldFamily: (record["toldFamily"] as? Int).map { $0 == 1 },
            trainingSessionID: (record["trainingSessionID"] as? String).flatMap(UUID.init),
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

    /// Запись профиля для ОТПРАВКИ — или `nil`, если отправлять нечего.
    ///
    /// **Четвёртая поверхность дефекта «пустые собаки» (отзыв
    /// 06.10.2026), и единственная, где мы не получаем мусор,
    /// а рассылаем его другому человеку.** Безымянная собака, уже
    /// лежащая в базе, публиковалась в общую зону, и на втором телефоне
    /// её принимал тот самый `accept`, который мы только что закрыли
    /// на входе.
    ///
    /// **Уборка этого не закрыла бы, а сузила.** Удаляется только
    /// безымянное, которое ничего за собой не тянет; безымянную
    /// с прицепленной историей мы храним нарочно — как улику о семени,
    /// которого не нашли. Ровно она и публиковалась бы дальше, то есть
    /// дыра осталась бы на самых ценных записях.
    ///
    /// **Почему ворота здесь, а не у вызывающего.** В `FamilySync`
    /// их место — `private func record(for:)`, которому нужны
    /// `context` и `outbox`: проверить тестом нечем. Решение, вынесенное
    /// в чистую функцию, проверяется одной строкой без двух телефонов
    /// и без сетевого стека.
    ///
    /// `nil` — законный ответ сборщику пачки
    /// (`CKSyncEngine.RecordZoneChangeBatch` просит запись
    /// по идентификатору и умеет её не получить), тем же `nil`
    /// отвечает ветка «такой записи у нас больше нет».
    static func record(_ payload: DogPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord? {
        guard DogPayload.hasUsableName(payload.name) else { return nil }
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
        // Прививка — шаг 0, 07.10.2026. Клиника и по id, и по имени:
        // промах по id норма, а имя — то, что человек прочтёт.
        record["clinicID"] = payload.clinicID?.uuidString
        record["clinicName"] = payload.clinicName
        record["vaccineBatch"] = payload.vaccineBatch
        record["vaccineValidUntil"] = payload.vaccineValidUntil
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
            clinicID: (record["clinicID"] as? String).flatMap(UUID.init),
            clinicName: record["clinicName"] as? String,
            vaccineBatch: record["vaccineBatch"] as? String,
            vaccineValidUntil: record["vaccineValidUntil"] as? Date,
            changedAt: changedAt
        )
    }

    // MARK: Медкнижка

    static func record(_ payload: LabResultPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.labResult.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = labResultPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: LabResultPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["sampledOn"] = payload.sampledOn
        record["sampledAt"] = payload.sampledAt
        record["laboratory"] = payload.laboratory
        record["reportNumber"] = payload.reportNumber
        record["section"] = payload.section
        record["indicator"] = payload.indicator
        // Три формы значения — порознь. Свести их в одно поле значило бы
        // превратить «<0,1» в число 0,1: тихо неверное значение вместо
        // видимо неизвестного.
        record["value"] = payload.value
        record["belowLimit"] = payload.belowLimit
        record["aboveLimit"] = payload.aboveLimit
        record["textValue"] = payload.textValue
        record["unit"] = payload.unit
        record["referenceLow"] = payload.referenceLow
        record["referenceHigh"] = payload.referenceHigh
        record["method"] = payload.method
        record["labMark"] = payload.labMark
        record["note"] = payload.note
        record["changedAt"] = payload.changedAt
    }

    static func labResultPayload(_ record: CKRecord) -> LabResultPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let sampledOn = record["sampledOn"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return LabResultPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            sampledOn: sampledOn,
            sampledAt: record["sampledAt"] as? Date,
            laboratory: record["laboratory"] as? String ?? "",
            reportNumber: record["reportNumber"] as? String ?? "",
            section: record["section"] as? String ?? "",
            indicator: record["indicator"] as? String ?? "",
            value: record["value"] as? Double,
            belowLimit: record["belowLimit"] as? Double,
            aboveLimit: record["aboveLimit"] as? Double,
            textValue: record["textValue"] as? String,
            unit: record["unit"] as? String ?? "",
            referenceLow: record["referenceLow"] as? Double,
            referenceHigh: record["referenceHigh"] as? Double,
            method: record["method"] as? String,
            labMark: record["labMark"] as? String ?? "",
            note: record["note"] as? String ?? "",
            changedAt: changedAt
        )
    }

    static func record(_ payload: VetVisitPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.vetVisit.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = vetVisitPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: VetVisitPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["date"] = payload.date
        record["clinicID"] = payload.clinicID?.uuidString
        record["clinicName"] = payload.clinicName
        record["doctor"] = payload.doctor
        record["reason"] = payload.reason
        record["conclusion"] = payload.conclusion
        record["changedAt"] = payload.changedAt
    }

    static func vetVisitPayload(_ record: CKRecord) -> VetVisitPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let date = record["date"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return VetVisitPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            date: date,
            clinicID: (record["clinicID"] as? String).flatMap(UUID.init),
            clinicName: record["clinicName"] as? String,
            doctor: record["doctor"] as? String ?? "",
            // Повод по умолчанию «осмотр», как в модели. Онлайн
            // не теряется: его присылают явно, а умолчание берётся
            // только у записи, где поля нет вовсе.
            reason: record["reason"] as? String ?? VisitReason.checkup.rawValue,
            conclusion: record["conclusion"] as? String ?? "",
            changedAt: changedAt
        )
    }

    static func record(_ payload: DiagnosisPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.diagnosis.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = diagnosisPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: DiagnosisPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["wording"] = payload.wording
        record["status"] = payload.status
        record["madeOn"] = payload.madeOn
        record["madeBy"] = payload.madeBy
        record["evidence"] = payload.evidence
        record["changedAt"] = payload.changedAt
    }

    static func diagnosisPayload(_ record: CKRecord) -> DiagnosisPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let madeOn = record["madeOn"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return DiagnosisPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            wording: record["wording"] as? String ?? "",
            // **Умолчание — ГИПОТЕЗА, а не «подтверждён».** У записи
            // без статуса мы не знаем, что это; назвать её
            // подтверждённой значило бы начать лечить по тому,
            // о чём не спрашивали.
            status: record["status"] as? String ?? DiagnosisStatus.hypothesis.rawValue,
            madeOn: madeOn,
            madeBy: record["madeBy"] as? String ?? "",
            evidence: record["evidence"] as? String ?? "",
            changedAt: changedAt
        )
    }

    static func record(_ payload: PrescriptionPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.prescription.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = prescriptionPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: PrescriptionPayload, to record: CKRecord) {
        record["dogID"] = payload.dogID?.uuidString
        record["number"] = payload.number
        record["date"] = payload.date
        record["clinicID"] = payload.clinicID?.uuidString
        record["clinicName"] = payload.clinicName
        record["doctor"] = payload.doctor
        record["dogWeightKg"] = payload.dogWeightKg
        record["medicationName"] = payload.medicationName
        record["dosage"] = payload.dosage
        record["schedule"] = payload.schedule
        record["duration"] = payload.duration
        record["pharmacyForm"] = payload.pharmacyForm
        record["controlFromWeeks"] = payload.controlFromWeeks
        record["controlToWeeks"] = payload.controlToWeeks
        record["dispensed"] = payload.dispensed
        record["instruction"] = payload.instruction
        record["source"] = payload.source
        record["changedAt"] = payload.changedAt
    }

    static func prescriptionPayload(_ record: CKRecord) -> PrescriptionPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let date = record["date"] as? Date,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return PrescriptionPayload(
            id: id,
            dogID: (record["dogID"] as? String).flatMap(UUID.init),
            number: record["number"] as? String ?? "",
            date: date,
            clinicID: (record["clinicID"] as? String).flatMap(UUID.init),
            clinicName: record["clinicName"] as? String,
            doctor: record["doctor"] as? String ?? "",
            dogWeightKg: record["dogWeightKg"] as? Double,
            medicationName: record["medicationName"] as? String ?? "",
            dosage: record["dosage"] as? String ?? "",
            schedule: record["schedule"] as? String ?? "",
            duration: record["duration"] as? String ?? "",
            pharmacyForm: record["pharmacyForm"] as? String,
            controlFromWeeks: record["controlFromWeeks"] as? Int ?? 0,
            controlToWeeks: record["controlToWeeks"] as? Int ?? 0,
            dispensed: record["dispensed"] as? String ?? "",
            instruction: record["instruction"] as? String ?? "",
            source: record["source"] as? String ?? "",
            changedAt: changedAt
        )
    }

    // MARK: Справочник клиник

    static func record(_ payload: ClinicPayload, base: CKRecord?, in zone: CKRecordZone.ID) -> CKRecord {
        let id = recordID(payload.id, in: zone)
        guard let base, base.recordID == id else {
            let record = CKRecord(recordType: SharedDiary.RecordType.clinic.rawValue, recordID: id)
            apply(payload, to: record)
            return record
        }
        let merged = clinicPayload(base).map { SharedDiaryMerge.resolve(local: payload, remote: $0) } ?? payload
        apply(merged, to: base)
        return base
    }

    static func apply(_ payload: ClinicPayload, to record: CKRecord) {
        record["name"] = payload.name
        record["detail"] = payload.detail
        record["isLab"] = payload.isLab
        record["phone"] = payload.phone
        record["createdAt"] = payload.createdAt
        record["changedAt"] = payload.changedAt
    }

    /// Разбор записи справочника.
    ///
    /// **Безымянную не принимаем**, и это тот же запрет, что у собаки.
    /// Имя клиники — ключ группировки: запись без имени собрала бы
    /// в одну группу всё, что имени не заполнило, и человек увидел бы
    /// «прививки в клинике ———» с чужими записями внутри.
    ///
    /// > **Группировка по полю со значением по умолчанию собирает
    /// > в одну группу всё, что его не заполнило.** В показе пустота
    /// > видна человеку, в ключе — не видна никому.
    static func clinicPayload(_ record: CKRecord) -> ClinicPayload? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let name = record["name"] as? String,
              Fmt.notBlank(name) != nil,
              let changedAt = record["changedAt"] as? Date
        else { return nil }

        return ClinicPayload(
            id: id,
            name: name,
            detail: record["detail"] as? String,
            isLab: record["isLab"] as? Bool ?? false,
            phone: record["phone"] as? String,
            createdAt: record["createdAt"] as? Date ?? changedAt,
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
        record["prescriptionNumber"] = payload.prescriptionNumber
        // Девять полей, не ехавших до 07.10.2026. Самое опасное —
        // `unitRaw`: «0,5» без единицы не значит ничего, и у второго
        // человека схема приезжала без неё.
        record["unitRaw"] = payload.unitRaw
        record["courseEnd"] = payload.courseEnd
        record["expiry"] = payload.expiry
        record["openedAt"] = payload.openedAt
        record["shelfAfterOpenDays"] = payload.shelfAfterOpenDays
        record["remindBeforeExpiry"] = payload.remindBeforeExpiry
        record["canGiveOutside"] = payload.canGiveOutside
        // Слоты — массив структур, и в `CKRecord` такое не кладётся:
        // годятся только скаляры, даты, строки и `Data`. Кодируем JSON,
        // как и в архиве, то есть одним и тем же представлением —
        // второе разошлось бы с первым молча.
        //
        // Тип объявлен явно: у `CKRecord` подписка перегружена,
        // и выводить `Data?` из `flatMap` компилятор отказывается —
        // `ambiguous use of subscript`. Это та самая цена, которую
        // просят вперёд.
        let слотыJSON: Data? = payload.doseSlotsData
            .flatMap { try? JSONEncoder().encode($0) }
        record["doseSlotsData"] = слотыJSON
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
            prescriptionNumber: record["prescriptionNumber"] as? String,
            unitRaw: record["unitRaw"] as? String,
            doseSlotsData: (record["doseSlotsData"] as? Data)
                .flatMap { try? JSONDecoder().decode([DoseSlot].self, from: $0) },
            courseEnd: record["courseEnd"] as? Date,
            expiry: record["expiry"] as? Date,
            openedAt: record["openedAt"] as? Date,
            shelfAfterOpenDays: record["shelfAfterOpenDays"] as? Int,
            remindBeforeExpiry: record["remindBeforeExpiry"] as? Bool,
            canGiveOutside: record["canGiveOutside"] as? Bool,
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
