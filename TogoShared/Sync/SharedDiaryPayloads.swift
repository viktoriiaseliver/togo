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
            askSignal: askSignalRaw,
            isDayOnly: isDayOnly,
            enteredAt: enteredAt,
            editedBy: editedBy,
            origin: originRaw,
            reactionTrigger: reactionTriggerRaw,
            reactionDistance: reactionDistanceRaw,
            toldFamily: toldFamily,
            trainingSessionID: trainingSessionID,
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
        // Девять полей с 07.10.2026. Опциональность значит «прежняя
        // версия этого не прислала» — тогда своё не трогаем. Иначе
        // правка, приехавшая от старого телефона, стёрла бы «как
        // попросил» и оговорку «часа не помню» у того, кто их ввёл.
        if let сигнал = payload.askSignal { askSignalRaw = сигнал }
        if let толькоДень = payload.isDayOnly { isDayOnly = толькоДень }
        enteredAt = payload.enteredAt ?? enteredAt
        editedBy = payload.editedBy ?? editedBy
        if let откуда = payload.origin { originRaw = откуда }
        if let повод = payload.reactionTrigger { reactionTriggerRaw = повод }
        if let расстояние = payload.reactionDistance { reactionDistanceRaw = расстояние }
        if let сказали = payload.toldFamily { toldFamily = сказали }
        trainingSessionID = payload.trainingSessionID ?? trainingSessionID
        changedAt = payload.changedAt
    }
}

extension DogPayload {
    /// Годится ли это в кличку. **Единственная реализация правила** —
    /// её зовут разбор записи (`SharedDiaryRecords.dogPayload`)
    /// и приём (`SharedDiaryInbox.accept`).
    ///
    /// Пробелы снимаются, и это не из осторожности: NBSP (U+00A0)
    /// появляется в поле опечаткой с французской клавиатуры —
    /// у нас им набрана вся французская типографика, — и строка
    /// из одного неразрывного пробела рисуется на экране ровно так же
    /// пусто, как `""`. Четыре значения проверены тестом: `""`, пробел,
    /// перевод строки, NBSP.
    ///
    /// Чего это правило **не** делает: оно не решает, что делать
    /// с уже заведёнными безымянными записями. Их у человека восемь
    /// (отзыв 06.10.2026), и ворота на входе их не убирают.
    /// `nonisolated`, потому что зовут из `nonisolated enum
    /// SharedDiaryRecords`: у файла изоляция по умолчанию главная,
    /// и без этого слова правило не достаёт до разбора записи —
    /// то есть до того конца, которым оно и приехало.
    nonisolated static func hasUsableName(_ name: String) -> Bool { Fmt.dogName(name) != nil }
}

@MainActor
extension Dog {
    var payload: DogPayload {
        DogPayload(
            id: id,
            name: name,
            breed: breed,
            birthDate: birthDate,
            sex: sexRaw,
            isNeutered: isNeutered,
            weightKg: weightKg,
            targetWeightLow: targetWeightLow,
            targetWeightHigh: targetWeightHigh,
            foodBrand: foodBrand,
            portionGrams: portionGrams,
            mealsPerDay: mealsPerDay,
            mealTimes: mealTimes,
            dailyNormGrams: dailyNormGrams,
            forbiddenFoods: forbiddenFoods,
            wakeMinuteOfDay: wakeMinuteOfDay,
            sleepMinuteOfDay: sleepMinuteOfDay,
            isOnTreatment: isOnTreatment,
            chipNumber: chipNumber,
            passportNumber: passportNumber,
            insuranceNumber: insuranceNumber,
            vetName: vetName,
            vetPhone: vetPhone,
            clinicName: clinicName,
            clinicPhone: clinicPhone,
            distinctiveMarks: distinctiveMarks,
            sitterFood: sitterFood,
            sitterDose: sitterDose,
            sitterWalks: sitterWalks,
            sitterForbidden: sitterForbidden,
            sitterEscalation: sitterEscalation,
            rewards: rewards,
            markerKind: markerKindRaw,
            sessionLengthMinutes: sessionLengthMinutes,
            trainingFoodFromPortion: trainingFoodFromPortion,
            changedAt: changedAt
        )
    }

    /// Фото здесь не трогается намеренно: оно не ездит, и затирать
    /// своё чужой пустотой нельзя. Тот же случай, что у `medicationID`
    /// дозы, — поле, которого в снимке нет, остаётся как было.
    func apply(_ payload: DogPayload) {
        name = payload.name
        breed = payload.breed
        birthDate = payload.birthDate
        sexRaw = payload.sex
        isNeutered = payload.isNeutered
        weightKg = payload.weightKg
        targetWeightLow = payload.targetWeightLow
        targetWeightHigh = payload.targetWeightHigh
        foodBrand = payload.foodBrand
        portionGrams = payload.portionGrams
        mealsPerDay = payload.mealsPerDay
        mealTimes = payload.mealTimes
        dailyNormGrams = payload.dailyNormGrams
        forbiddenFoods = payload.forbiddenFoods
        wakeMinuteOfDay = payload.wakeMinuteOfDay
        sleepMinuteOfDay = payload.sleepMinuteOfDay
        isOnTreatment = payload.isOnTreatment
        chipNumber = payload.chipNumber
        passportNumber = payload.passportNumber
        insuranceNumber = payload.insuranceNumber
        vetName = payload.vetName
        vetPhone = payload.vetPhone
        clinicName = payload.clinicName
        clinicPhone = payload.clinicPhone
        distinctiveMarks = payload.distinctiveMarks
        sitterFood = payload.sitterFood
        sitterDose = payload.sitterDose
        sitterWalks = payload.sitterWalks
        sitterForbidden = payload.sitterForbidden
        sitterEscalation = payload.sitterEscalation
        rewards = payload.rewards
        markerKindRaw = payload.markerKind
        sessionLengthMinutes = payload.sessionLengthMinutes
        trainingFoodFromPortion = payload.trainingFoodFromPortion
        changedAt = payload.changedAt
    }
}

@MainActor
extension CareTask {
    var payload: CarePayload {
        CarePayload(
            id: id, dogID: dog?.id, title: title, detail: detail,
            kind: kindRaw, category: categoryRaw,
            intervalDays: intervalDays, scheduledDate: scheduledDate,
            remindDaysBefore: remindDaysBefore, lastDone: lastDone,
            streak: streak, seasonStartMonth: seasonStartMonth,
            seasonEndMonth: seasonEndMonth, snoozeCount: snoozeCount,
            clinicID: clinic?.id, clinicName: clinic?.name,
            vaccineBatch: vaccineBatch, vaccineValidUntil: vaccineValidUntil,
            changedAt: changedAt
        )
    }

    func apply(_ payload: CarePayload) {
        title = payload.title
        detail = payload.detail
        kindRaw = payload.kind
        categoryRaw = payload.category
        intervalDays = payload.intervalDays
        scheduledDate = payload.scheduledDate
        remindDaysBefore = payload.remindDaysBefore
        lastDone = payload.lastDone
        streak = payload.streak
        seasonStartMonth = payload.seasonStartMonth
        seasonEndMonth = payload.seasonEndMonth
        snoozeCount = payload.snoozeCount
        vaccineBatch = payload.vaccineBatch
        vaccineValidUntil = payload.vaccineValidUntil
        // Клиника здесь НЕ ставится: для поиска по id нужен контекст,
        // а у модели до вставки его может не быть. Связь сшивает
        // `SharedDiaryInbox.accept(_:dog:context:)` — там, где контекст
        // есть по устройству. Разделение не стиль: `apply` зовут и из
        // тестов без хранилища.
        changedAt = payload.changedAt
    }
}

@MainActor
extension Medication {
    var payload: MedicationPayload {
        MedicationPayload(
            id: id, dogID: dog?.id, name: name, doseText: doseText,
            times: times, fastingMinutes: fastingMinutes,
            fastingBeforeMinutes: fastingBeforeMinutes,
            minutesAfterMeal: minutesAfterMeal, isPaused: isPaused,
            prescriber: prescriber, cancelledAt: cancelledAt,
            cancelledNote: cancelledNote,
            prescriptionNumber: prescriptionNumber,
            unitRaw: unitRaw, doseSlotsData: doseSlotsData,
            courseEnd: courseEnd, expiry: expiry, openedAt: openedAt,
            shelfAfterOpenDays: shelfAfterOpenDays,
            remindBeforeExpiry: remindBeforeExpiry,
            canGiveOutside: canGiveOutside,
            changedAt: changedAt
        )
    }

    /// Запас таблеток не трогается: он про коробку, которая лежит
    /// у кого-то дома, и у мамы она своя.
    func apply(_ payload: MedicationPayload) {
        name = payload.name
        doseText = payload.doseText
        times = payload.times
        fastingMinutes = payload.fastingMinutes
        fastingBeforeMinutes = payload.fastingBeforeMinutes
        minutesAfterMeal = payload.minutesAfterMeal
        isPaused = payload.isPaused
        prescriber = payload.prescriber
        cancelledAt = payload.cancelledAt
        cancelledNote = payload.cancelledNote
        prescriptionNumber = payload.prescriptionNumber
        // Девять полей с 07.10.2026. Опциональность в нагрузке значит
        // «старый телефон этого не прислал» — тогда своё не трогаем,
        // иначе правка приехавшая от прежней версии стёрла бы единицу
        // дозы у того, кто её уже ввёл.
        if let unitRaw = payload.unitRaw { self.unitRaw = unitRaw }
        if let слоты = payload.doseSlotsData { doseSlotsData = слоты }
        courseEnd = payload.courseEnd ?? courseEnd
        expiry = payload.expiry ?? expiry
        openedAt = payload.openedAt ?? openedAt
        if let дней = payload.shelfAfterOpenDays { shelfAfterOpenDays = дней }
        if let напоминать = payload.remindBeforeExpiry { remindBeforeExpiry = напоминать }
        if let наУлице = payload.canGiveOutside { canGiveOutside = наУлице }
        changedAt = payload.changedAt
    }
}

@MainActor
extension Clinic {
    var payload: ClinicPayload {
        ClinicPayload(
            id: id, name: name, detail: detail, isLab: isLab,
            phone: phone, createdAt: createdAt, changedAt: changedAt
        )
    }

    /// `createdAt` не трогается: это факт о ЗАПИСИ на том телефоне,
    /// где её завели, а не о клинике. Та же причина, по которой
    /// `Dog.createdAt` не ездит вовсе.
    func apply(_ payload: ClinicPayload) {
        name = payload.name
        detail = payload.detail
        isLab = payload.isLab
        phone = payload.phone
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
            // Приехавшая запись, которую не записали, вернётся следующим
            // кругом обмена — но круг станет вечным, если об этом молчать.
            guard context.persist(otherwise: { context.delete(event) }) else {
                log.error("общий дневник: запись не записалась")
                return false
            }
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !context.persist(otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние записи не записалось")
            }
        }
        return changed
    }

    /// Принять профиль собаки с другого телефона.
    ///
    /// **Собака заводится, если её ещё нет.** Это и есть починка
    /// «мама не видит мою собаку»: раньше приехавшие записи цеплялись
    /// к ПЕРВОЙ местной собаке (`FamilySync.apply`), а если местной
    /// не было ни одной — повисали ничьими.
    ///
    /// Решение Виктории от 23.09.2026: у гостя со своей собакой видны
    /// **обе, переключателем**. Слияния по кличке быть не должно ни при
    /// каких условиях — две «Стич» в одном доме это две собаки, и 23.09
    /// живой дневник уже разошёлся пополам именно так.
    @discardableResult
    static func accept(_ payload: DogPayload, context: ModelContext) -> Bool {
        // Пустая кличка не принимается ни на заведение, ни на слияние,
        // и ворота стоят здесь, а не только в разборе записи.
        //
        // **Вторая половина дороже первой.** Фильтр в
        // `SharedDiaryRecords.dogPayload` закрывает дорогу из CloudKit
        // и ничего не говорит про уже заведённую собаку: ниже идёт
        // `SharedDiaryMerge.resolve`, где побеждает поздняя правка
        // ЦЕЛИКОМ. Пустой снимок с поздним `changedAt` затирал кличку
        // живой собаки через `local.apply(merged)` — то есть пустые
        // собаки не только заводились, но и делались из настоящих.
        //
        // «Позже побеждает» верно для веса и порции: это факты, которые
        // уточняют. Для клички то же правило означает, что собака
        // у человека на экране пропадает без его участия — а все
        // одиннадцать связей `Dog` каскадные (`Dog.swift:128–158`),
        // и безымянной она становится вместе со всем дневником за собой.
        //
        // Ворота после последнего действия, способного их нарушить
        // (сборка снимка), и перед первым, который на них опирается
        // (`Dog(name:)` и `apply`).
        guard DogPayload.hasUsableName(payload.name) else {
            log.notice("общий дневник: снимок собаки без клички отклонён")
            return false
        }

        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<Dog>(predicate: #Predicate { $0.id == id })
        ).first

        guard let local = existing else {
            let dog = Dog(name: payload.name, weightKg: payload.weightKg)
            dog.id = payload.id
            dog.apply(payload)
            context.insert(dog)
            guard context.persist(otherwise: { context.delete(dog) }) else {
                log.error("общий дневник: собака не записалась")
                return false
            }
            // Крошка запуска уже умеет отличать приехавшую от заведённой
            // здесь — здесь мы это знаем точно, а не по разнице составов.
            StartupLog.note("собака \(payload.id.uuidString.prefix(8)) — приехала обменом")
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !context.persist(otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние профиля не записалось")
            }
        }
        return changed
    }

    /// Принять запись справочника клиник.
    ///
    /// **Безымянную не принимаем вовсе.** Имя клиники — ключ
    /// группировки «где делали»: запись без имени собрала бы в одну
    /// группу всё, что имени не заполнило, и человек увидел бы
    /// прививки неизвестно откуда, сложенные вместе. Это тот же
    /// запрет, что у приёма собаки, и завёлся он той же ценой.
    ///
    /// **Слияния по имени здесь НЕТ, и это осознанно.** У архива оно
    /// есть: там обе стороны вышли из одного файла, и имя совпадает
    /// побайтно. В обмене совпадение имён значит другое — двое завели
    /// одну организацию своими руками, с разными UUID. Склеить их
    /// значило бы решить за человека, что «Vet Riviera» у мамы
    /// и у Виктории — одна запись; разъехавшиеся телефоны схлопнутся
    /// при первой правке. Два справочника с похожими именами —
    /// видимая человеку неприятность; склейка — невидимая.
    @discardableResult
    static func accept(_ payload: ClinicPayload, context: ModelContext) -> Bool {
        guard Fmt.notBlank(payload.name) != nil else {
            log.error("общий дневник: приехала клиника без имени — не принимаем")
            return false
        }
        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<Clinic>(predicate: #Predicate { $0.id == id })
        ).first

        guard let local = existing else {
            let clinic = Clinic(name: payload.name, detail: payload.detail,
                                isLab: payload.isLab, phone: payload.phone)
            clinic.id = payload.id
            clinic.createdAt = payload.createdAt
            clinic.changedAt = payload.changedAt
            context.insert(clinic)
            guard context.persist(otherwise: { context.delete(clinic) }) else {
                log.error("общий дневник: клиника не записалась")
                return false
            }
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !context.persist(otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние клиники не записалось")
            }
        }
        return changed
    }

    /// Клиника для приехавшего дела ухода: по id, при промахе — по имени.
    ///
    /// **Промах по id здесь норма, а не сбой** — тот же урок, что
    /// у висящих доз. Справочник второй человек мог завести своей
    /// рукой до включения обмена, и тогда та же «Vet Riviera» лежит
    /// у него с другим UUID.
    ///
    /// **Клинику по имени мы НЕ заводим.** Промах по обоим оставляет
    /// связь пустой: запись, рождённая промахом, была бы дублем
    /// справочника, а справочник без дублей — правило дизайна.
    /// Приедет своя запись клиники — связь сошьётся следующей правкой
    /// дела ухода.
    static func clinic(for payload: CarePayload, context: ModelContext) -> Clinic? {
        if let id = payload.clinicID,
           let найдена = try? context.fetch(
               FetchDescriptor<Clinic>(predicate: #Predicate { $0.id == id })
           ).first {
            return найдена
        }
        guard let имя = Fmt.notBlank(payload.clinicName ?? "") else { return nil }
        return try? context.fetch(FetchDescriptor<Clinic>())
            .first { $0.name == имя }
    }

    /// Принять дело ухода.
    @discardableResult
    static func accept(_ payload: CarePayload, dog: Dog?, context: ModelContext) -> Bool {
        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        ).first

        guard let local = existing else {
            let task = CareTask(title: payload.title, detail: payload.detail)
            task.id = payload.id
            task.apply(payload)
            task.clinic = clinic(for: payload, context: context)
            task.dog = dog
            context.insert(task)
            guard context.persist(otherwise: { context.delete(task) }) else {
                log.error("общий дневник: дело ухода не записалось")
                return false
            }
            return false
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            // Связь сшивается по ПОБЕДИВШЕЙ версии, а не по приехавшей:
            // иначе проигравшая правка всё равно переставила бы клинику,
            // и спор двух телефонов решался бы по-разному для поля
            // и для связи.
            if let сшита = clinic(for: merged, context: context) {
                local.clinic = сшита
            }
            if !context.persist(otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние дела ухода не записалось")
            }
        }
        return changed
    }

    /// Принять схему лечения.
    ///
    /// **Связывание висящих доз.** Доза могла приехать раньше схемы —
    /// так бывает всегда, когда обмен включают посреди курса. Висящая
    /// ни на чём доза на экране не показывается вовсе, то есть второй
    /// человек видит приём открытым и даёт вторую таблетку. Поэтому
    /// приехавшая схема сразу забирает свои дозы.
    @discardableResult
    static func accept(_ payload: MedicationPayload, dog: Dog?, context: ModelContext) -> Bool {
        let id = payload.id
        let existing = try? context.fetch(
            FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        ).first

        let схема: Medication
        var changed = false
        if let local = existing {
            let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
            changed = merged != payload
            if merged != local.payload {
                let былПрежний = local.payload
                local.apply(merged)
                if !context.persist(otherwise: { local.apply(былПрежний) }) {
                    log.error("общий дневник: слияние схемы не записалось")
                }
            }
            схема = local
        } else {
            let свежая = Medication(name: payload.name, doseText: payload.doseText,
                                    times: payload.times)
            свежая.id = payload.id
            свежая.apply(payload)
            свежая.dog = dog
            context.insert(свежая)
            guard context.persist(otherwise: { context.delete(свежая) }) else {
                log.error("общий дневник: схема не записалась")
                return false
            }
            схема = свежая
        }

        подобратьДозы(схемы: схема, context: context)
        return changed
    }

    /// Дозы, приехавшие до схемы, привязываются к ней.
    ///
    /// Берём только те, что ждали **именно её** — по запомненному id
    /// или по имени. Первая редакция этой функции цепляла к приехавшей
    /// схеме все ничьи дозы подряд: условие в ней сравнивало схему
    /// с самой собой и было истинным всегда. При двух курсах это
    /// сложило бы приёмы разных препаратов в один — ровно та ошибка,
    /// ради которой у дозы вообще заведены свои правила.
    private static func подобратьДозы(схемы схема: Medication, context: ModelContext) {
        let ничьи = ((try? context.fetch(FetchDescriptor<DoseRecord>())) ?? [])
            .filter { $0.medication == nil }
        guard !ничьи.isEmpty else { return }

        let имя = folded(схема.name)
        var связали: [DoseRecord] = []
        for доза in ничьи {
            let поID = доза.awaitedMedicationID == схема.id
            let поИмени = доза.awaitedMedicationName.map { folded($0) == имя } ?? false
            guard поID || поИмени else { continue }
            доза.medication = схема
            связали.append(доза)
        }
        guard !связали.isEmpty else { return }
        if !context.persist(otherwise: { связали.forEach { $0.medication = nil } }) {
            log.error("общий дневник: связь доз со схемой не записалась")
        }
    }

    /// К какой собаке относится приехавшая запись.
    ///
    /// **По id, а не «первая местная».** До 23.09.2026 здесь стояло
    /// `fetch(Dog.self).first`, и это давало две беды разом: у гостя
    /// с собственной собакой чужие отметки ложились на неё, а у гостя
    /// без собак — повисали ничьими и не показывались нигде.
    ///
    /// Запасной вариант — единственная местная собака — оставлен
    /// намеренно: записи, уехавшие до того, как профиль научился
    /// ездить, помнят `dogID`, которого на этом телефоне нет. Когда
    /// собака одна, ошибиться невозможно; когда их две — лучше оставить
    /// запись ничьей, чем приписать её не тому животному. Ничью видно
    /// и можно починить, приписанную не туда — нет.
    static func dog(for payload: EventPayload, context: ModelContext) -> Dog? {
        dog(forDogID: payload.dogID, context: context)
    }

    /// То же для ухода и схем: правило владельца одно на все типы.
    /// Разойтись оно может только молча — и тогда лента будет у одной
    /// собаки, а расписание у другой.
    static func dog(forDogID id: UUID?, context: ModelContext) -> Dog? {
        let dogs = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        if let id, let свой = dogs.first(where: { $0.id == id }) { return свой }
        return dogs.count == 1 ? dogs.first : nil
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
            if medication == nil {
                // Схема ещё не приехала — запоминаем, чего доза ждёт.
                dose.awaitedMedicationID = payload.medicationID
                dose.awaitedMedicationName = payload.medicationName
            }
            context.insert(dose)
            guard context.persist(otherwise: { context.delete(dose) }) else {
                log.error("общий дневник: доза не записалась")
                return false
            }
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
            let былПрежний = local.payload
            local.apply(merged)
            if !context.persist(otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние дозы не записалось")
            }
        } else if linked {
            if !context.persist(otherwise: { local.medication = nil }) {
                log.error("общий дневник: связь дозы с препаратом не записалась")
            }
        }
        return changed
    }
}
