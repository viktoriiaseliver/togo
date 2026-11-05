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
            photo: photo,
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
        photo = payload.photo
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

/// Единственные ворота НАРУЖУ: что мы вправе положить в общую зону.
///
/// **Заведено 08.10.2026, и заведено потому, что у наружу ДВЕ двери,
/// а запрет стоял в одной.** Первая редакция починки поставила `guard`
/// внутри `FamilySync.enqueueLocalChanges` — пути «сохранили →
/// отправили». Вторая дверь, засев уже лежащих записей, кладёт
/// изменения в `engine.state.add(...)` **напрямую**, минуя эту
/// функцию, и пустые собаки уехали бы по ней при зелёном стороже
/// первой.
///
/// Нашёл это не я, а автор засева — и написал мне **до** своей первой
/// правки, а не после.
///
/// > **Два пути наружу — два места для одного запрета. Пока он стоит
/// > в одном, второй его не знает.**
///
/// Отсюда форма: правило живёт здесь одной функцией, а обе двери её
/// **зовут**. Копия условия у второй двери была бы хуже: два разбора
/// одного правила расходятся молча, и у нас это записано ценой двух
/// случаев за сутки.
///
/// # Почему это НЕ `Dog.canBeShown`
///
/// Похоже на правило показа и является другим вопросом.
/// `canBeShown` отвечает «рисовать ли это человеку на экране»;
/// здесь — «вправе ли мы положить это в чужое хранилище». Совпадают
/// они сегодня и могут разойтись завтра: решение «пустые записи
/// не показываем, а не удаляем» принято для СВОЕГО экрана, и у чужого
/// хранилища своего правила показа нет вовсе.
///
/// Единственная реализация вопроса «годится ли это в кличку» —
/// `DogPayload.hasUsableName`, и у неё теперь три звонящих: разбор
/// записи CloudKit, приём снимка и эти ворота.
///
/// # Чего эти ворота НЕ делают
///
/// Они запрещают **отправлять новых** и ничего не делают с теми, кто
/// уже уехал. Замер автора засева: исходящий круг слушает только
/// `inserted` и `updated`, удаления в нём нет вовсе, а надгробие
/// (`deletedAt`) есть только у `LogEvent` — `.deleteRecord`
/// в `Sync/` ноль вхождений. То есть **пятнадцать пустых собак
/// из выгрузки Виктории, если они уже в общей зоне, остаются там**,
/// и работы «убрать уехавшее» у нас нет.
nonisolated enum SharedDiaryOutgoing {

    /// Можно ли отправлять эту собаку в общую зону.
    ///
    /// Безымянную нельзя: у неё нет ни клички, ни связей (замер
    /// по журналу переписи — нули по всем одиннадцати), и у человека
    /// на другом конце она станет строкой без подписи, которую он
    /// не сможет ни понять, ни убрать.
    @MainActor
    static func sendable(_ dog: Dog) -> Bool {
        DogPayload.hasUsableName(dog.name)
    }

    /// Раньше этой даты записи в дневнике собаки быть не может:
    /// приложению меньше года. Замер по живой выгрузке 08.10.2026 —
    /// самая ранняя настоящая запись `2026-09-01`, то есть запас
    /// в двадцать четыре года.
    ///
    /// **Это НЕ копия `CloudKitSchemaWarmup.доПрограммы`, и они
    /// отвечают на разные вопросы** — там «что удалять, убирая
    /// прогрев», здесь «вправе ли мы положить это в чужое
    /// хранилище». Тот константу держать не может по устройству:
    /// весь файл прогрева под `#if DEBUG`, а эти ворота обязаны
    /// работать в продуктовой сборке. Сдвинешь одну — посмотри
    /// на вторую: `grep -rn "доПрограммы\|раньшеПриложения"`.
    static let раньшеПриложения = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01

    /// Можно ли отправлять эту запись в общую зону.
    ///
    /// # Чего здесь нет и почему
    ///
    /// Признак — **дата, а не имя автора**. У отладочной записи
    /// прогрева в поле автора стоит метка, но опираться на неё нельзя:
    /// `LogEvent` ездит в общий дневник, и слияние переписывает
    /// `authorName` из приехавшего payload — это написано в голове
    /// самого прогрева (`CloudKitSchemaWarmup:35-40`) и измерено там
    /// же 23.09. Дату не переписывает никто.
    ///
    /// # Что это ловит на живых данных
    ///
    /// Замер 08.10.2026 по выгрузке с телефона Виктории: из 182
    /// записей одна — отладочная, автор `ПРОГРЕВ СХЕМЫ`, дата
    /// `2001-01-01`, у видимой собаки «Стич». Создаёт её
    /// `CloudKitSchemaWarmup`, и он целиком под `#if DEBUG`:
    /// в продуктовой сборке она **не создастся и не удалится** —
    /// `remove()` тоже под `DEBUG`. То есть артефакт отладочной
    /// сборки уже лежит в живых данных, а убрать его оттуда
    /// приложение не умеет.
    ///
    /// Без этих ворот засев отправил бы её маме первой записью
    /// истории: заметка от автора, которого она не знает, датой
    /// 1 января 2001 года — в комнату, которую засев и должен был
    /// наполнить.
    ///
    /// # Чего эти ворота НЕ делают
    ///
    /// То же, что у собак: запрещают **отправлять** и ничего
    /// не делают с уехавшим. Уехала ли эта запись в зону уже —
    /// **неизмеримо**: `isSynced` объявлен `= true` по умолчанию
    /// и доставку строки не отслеживает (`TGRows:274`), а приватную
    /// базу CloudKit открывают права владельца данных.
    @MainActor
    static func sendable(_ event: LogEvent) -> Bool {
        event.date >= раньшеПриложения
    }
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
            разовыеВременаДата: разовыеВременаДата,
            разовыеВремена: разовыеВремена,
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
            deletedAt: deletedAt, changedAt: changedAt
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
        разовыеВременаДата = payload.разовыеВременаДата
        разовыеВремена = payload.разовыеВремена
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
        deletedAt = payload.deletedAt
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
            deletedAt: deletedAt, changedAt: changedAt
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
        deletedAt = payload.deletedAt
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
            unitRaw: unitRaw, massPerUnitMcg: massPerUnitMcg,
            doseSlotsData: doseSlotsData,
            courseEnd: courseEnd, startedAt: startedAt,
            expiry: expiry, openedAt: openedAt,
            shelfAfterOpenDays: shelfAfterOpenDays,
            remindBeforeExpiry: remindBeforeExpiry,
            canGiveOutside: canGiveOutside,
            deletedAt: deletedAt, changedAt: changedAt
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
        // Масса — через `if let`, как единица дозы рядом, и по той же
        // причине: снимок от прежней сборки её не прислал, и присвоить
        // `nil` значило бы стереть массу у того, кто её уже ввёл.
        // Это ровно та правка, которую здесь сделали для `unitRaw`
        // 07.10 и не сделали для массы 08.10.
        if let масса = payload.massPerUnitMcg { massPerUnitMcg = масса }
        if let слоты = payload.doseSlotsData { doseSlotsData = слоты }
        courseEnd = payload.courseEnd ?? courseEnd
        // Та же идиома: снимок от сборки до V8 даты начала не несёт.
        startedAt = payload.startedAt ?? startedAt
        expiry = payload.expiry ?? expiry
        openedAt = payload.openedAt ?? openedAt
        if let дней = payload.shelfAfterOpenDays { shelfAfterOpenDays = дней }
        if let напоминать = payload.remindBeforeExpiry { remindBeforeExpiry = напоминать }
        if let наУлице = payload.canGiveOutside { canGiveOutside = наУлице }
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension WeightEntry {
    var payload: WeightPayload {
        WeightPayload(id: id, dogID: dog?.id, date: date, kg: kg, deletedAt: deletedAt, changedAt: changedAt)
    }

    func apply(_ payload: WeightPayload) {
        date = payload.date
        kg = payload.kg
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension DogDocument {
    var payload: DocumentPayload {
        DocumentPayload(
            id: id, dogID: dog?.id, title: title, kind: kindRaw,
            number: number, issuedBy: issuedBy, validUntil: validUntil,
            addedAt: addedAt, note: note, deletedAt: deletedAt, changedAt: changedAt,
            occurredOn: occurredOn, direction: directionRaw,
            clinicID: clinic?.id, clinicName: clinic?.name
        )
    }

    /// `image` не трогается ни в одну сторону: его в нагрузке нет,
    /// и приехавшая правка не должна стирать скан, который человек
    /// положил у себя.
    ///
    /// **`clinic` здесь НЕ ставится, и это то же решение, что
    /// у медкнижки** (`SharedDiaryPayloads:443`): для поиска клиники
    /// нужен контекст, а у модели до вставки его может не быть. Связь
    /// сшивает приём — `accept(_:dog:context:)`, — там, где контекст
    /// есть по устройству.
    func apply(_ payload: DocumentPayload) {
        title = payload.title
        kindRaw = payload.kind
        number = payload.number
        issuedBy = payload.issuedBy
        validUntil = payload.validUntil
        addedAt = payload.addedAt
        note = payload.note
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
        occurredOn = payload.occurredOn
        directionRaw = payload.direction
    }
}

// MARK: - Медкнижка
//
// У всех четырёх `clinic` НЕ ставится в `apply`: для поиска по id нужен
// контекст, а у модели до вставки его может не быть. Связь сшивает
// приём — там, где контекст есть по устройству. То же решение, что
// у дела ухода.

@MainActor
extension LabResult {
    var payload: LabResultPayload {
        LabResultPayload(
            id: id, dogID: dog?.id, sampledOn: sampledOn, sampledAt: sampledAt,
            laboratory: laboratory, reportNumber: reportNumber,
            section: section, indicator: indicator,
            value: value, belowLimit: belowLimit, aboveLimit: aboveLimit,
            textValue: textValue, unit: unit,
            referenceLow: referenceLow, referenceHigh: referenceHigh,
            method: method, labMark: labMark, note: note, deletedAt: deletedAt, changedAt: changedAt
        )
    }

    func apply(_ payload: LabResultPayload) {
        sampledOn = payload.sampledOn
        sampledAt = payload.sampledAt
        laboratory = payload.laboratory
        reportNumber = payload.reportNumber
        section = payload.section
        indicator = payload.indicator
        value = payload.value
        belowLimit = payload.belowLimit
        aboveLimit = payload.aboveLimit
        textValue = payload.textValue
        unit = payload.unit
        referenceLow = payload.referenceLow
        referenceHigh = payload.referenceHigh
        method = payload.method
        labMark = payload.labMark
        note = payload.note
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension VetVisit {
    var payload: VetVisitPayload {
        VetVisitPayload(
            id: id, dogID: dog?.id, date: date,
            clinicID: clinic?.id, clinicName: clinic?.name,
            doctor: doctor, reason: reasonRaw, conclusion: conclusion,
            deletedAt: deletedAt, changedAt: changedAt
        )
    }

    func apply(_ payload: VetVisitPayload) {
        date = payload.date
        doctor = payload.doctor
        reasonRaw = payload.reason
        conclusion = payload.conclusion
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension Diagnosis {
    var payload: DiagnosisPayload {
        DiagnosisPayload(
            id: id, dogID: dog?.id, wording: wording, status: statusRaw,
            madeOn: madeOn, madeBy: madeBy, evidence: evidence,
            deletedAt: deletedAt, changedAt: changedAt
        )
    }

    func apply(_ payload: DiagnosisPayload) {
        wording = payload.wording
        statusRaw = payload.status
        madeOn = payload.madeOn
        madeBy = payload.madeBy
        evidence = payload.evidence
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension Prescription {
    var payload: PrescriptionPayload {
        PrescriptionPayload(
            id: id, dogID: dog?.id, number: number, date: date,
            clinicID: clinic?.id, clinicName: clinic?.name,
            doctor: doctor, dogWeightKg: dogWeightKg,
            medicationName: medicationName, dosage: dosage,
            schedule: schedule, duration: duration,
            pharmacyForm: pharmacyForm,
            controlFromWeeks: controlFromWeeks, controlToWeeks: controlToWeeks,
            dispensed: dispensed, instruction: instruction, source: source,
            deletedAt: deletedAt, changedAt: changedAt
        )
    }

    func apply(_ payload: PrescriptionPayload) {
        number = payload.number
        date = payload.date
        doctor = payload.doctor
        dogWeightKg = payload.dogWeightKg
        medicationName = payload.medicationName
        dosage = payload.dosage
        schedule = payload.schedule
        duration = payload.duration
        pharmacyForm = payload.pharmacyForm
        controlFromWeeks = payload.controlFromWeeks
        controlToWeeks = payload.controlToWeeks
        dispensed = payload.dispensed
        instruction = payload.instruction
        source = payload.source
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

@MainActor
extension Clinic {
    var payload: ClinicPayload {
        ClinicPayload(
            id: id, name: name, detail: detail, isLab: isLab,
            phone: phone, createdAt: createdAt, deletedAt: deletedAt, changedAt: changedAt
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
        deletedAt = payload.deletedAt
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
            deletedAt: deletedAt, changedAt: changedAt
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
        deletedAt = payload.deletedAt
        changedAt = payload.changedAt
    }
}

/// Чем кончился приём одной записи.
///
/// Три исхода вместо прежнего `Bool` («надо ли вернуть»), и третий —
/// ради обмена, а не ради экрана. До 04.11.2026 отказ выборки читался
/// как «записи нет» и заводил дубликат, а отказ записи терялся: `apply`
/// двигал время сверки и сохранял положение движка, и запись больше
/// не приезжала. Теперь `.отказ` доходит до `FamilySync.apply`: тот
/// не двигает время сверки и держит запись в `отложенныйПриём`, повторяя
/// её следующим заходом.
nonisolated enum ИсходПриёма: Equatable, Sendable {
    /// Записано или сознательно не принято (пустая кличка, надгробие
    /// на то, чего у нас не было).
    case принято
    /// Записано, и наша версия после слияния отличается от приехавшей —
    /// её надо отправить обратно.
    case вернуть
    /// Выборка или запись отказали: у нас этой записи нет или она старая.
    case отказ
}

/// Приём чужих изменений в свой дневник.
///
/// Одно место, через которое всё приходящее попадает в базу — ровно так же,
/// как `EventLog` единственная дверь для своих записей. Иначе правила
/// слияния расползутся по экранам и разойдутся.
@MainActor
enum SharedDiaryInbox {

    // MARK: Страница — ОДИН контекст от начала до конца

    /// Контекст открытой страницы — или `nil`, если страницы нет.
    ///
    /// # Почему здесь больше нет отката
    ///
    /// **Решение Виктории 29.10.2026 — путь 1, и целиком.** До него
    /// страница принималась в ГЛАВНЫЙ контекст, а честность отказа
    /// держалась на откатах: каждый `accept` клал замыкание «вернуть
    /// как было», и при неудавшемся сохранении они прокручивались
    /// назад. Форма держится для правки поля и **не держится для
    /// вставки** — это замер, а не подозрение. Запертое хранилище
    /// (`allowsSave: false`), одна вставка, пять форм одного вызова:
    ///
    /// ```
    /// [А] delete сразу после упавшего save    остался 1
    /// [Б] fetch МЕЖДУ упавшим save и delete   стало 0 — работает
    /// [В] rollback внутри otherwise           остался 1, hasChanges=false
    /// [Г] rollback после возврата persist     остался 1, hasChanges=false
    /// [Д] fetch сразу после упавшего save     отдал ОДНУ вставку ДВАЖДЫ
    /// ```
    ///
    /// Два вывода дороже самого замера: после упавшего `save` состояние
    /// контекста в памяти **недостоверно само по себе — оно двоит**;
    /// `rollback()` ставит `hasChanges = false` и ОСТАВЛЯЕТ запись
    /// видимой, то есть она на экране, а сохранить её уже нельзя
    /// никогда. Работала ровно одна форма — [Б], — и механизма ей нет,
    /// есть совпадение.
    ///
    /// > **Поэтому отката тут нет вовсе.** Страница живёт в своём
    /// > контексте от начала до конца; не записалась — контекст
    /// > выбрасывается целиком, и возвращать нечего, потому что
    /// > в главном ничего и не менялось. «Целиком или никак»
    /// > обеспечено устройством кода, а не порядком замыканий.
    ///
    /// # Чего это НЕ чинит
    ///
    /// `persist(otherwise: { context.delete(x) })` вне страницы — та же
    /// неработающая форма отката вставки, и зовут её из двух десятков
    /// мест, включая медицинские (разбор — `Persist.swift`). Здесь
    /// закрыт один путь — приём чужой страницы. Остальные ждут хозяина.
    private static var открытаяСтраница: ModelContext?

    /// Схемы и дозы, приехавшие ЭТОЙ страницей.
    ///
    /// Копятся внутри `accept`, читаются один раз в конце страницы —
    /// в её контексте и ДО сохранения. Список собирает не вызывающий,
    /// а сам приём: пока его собирали снаружи, «решение в контексте
    /// страницы» оставалось договорённостью с вызывающим.
    private static var схемыСтраницы: [UUID] = []
    private static var дозыСтраницы: [UUID] = []

    /// Итог страницы: записалась ли она и что решила погасить.
    struct ИтогСтраницы {
        /// `false` значит «не записалось НИЧЕГО, и главный контекст
        /// этой страницы не видел вовсе».
        let записано: Bool

        /// Дозы, по которым напоминания больше не ждут отметки, —
        /// **идентификаторами, а не живыми моделями**: модель
        /// принадлежит контексту страницы и пережила бы его.
        ///
        /// Решение принято ВНУТРИ страницы, до сохранения. Гасить —
        /// после `записано == true`: до сохранения принятое ещё
        /// не факт хранилища, и погашенный по нему курс мог оказаться
        /// живым.
        let большеНеЖдут: [UUID]
    }

    /// Записать принятое: сразу — если страницы нет.
    ///
    /// **Внутри страницы не сохраняет и не копит ничего** — ни `save`,
    /// ни отката. Сохранение у страницы одно и оно последнее; откат
    /// у неё — выброшенный контекст.
    ///
    /// Различитель — ТОЖДЕСТВО контекста, а не флаг «страница открыта».
    /// Прежняя редакция смотрела на флаг, и всякий, кто звал `accept`
    /// со своим контекстом, пока шла чужая страница, получал молчаливое
    /// «записано» без сохранения. Тождество отвечает про тот контекст,
    /// который ему дали, и про него одного.
    static func записать(_ context: ModelContext, otherwise вернуть: () -> Void) -> Bool {
        guard открытаяСтраница !== context else { return true }
        return context.persist(otherwise: вернуть)
    }

    /// Принять страницу чужих изменений в ОТДЕЛЬНЫЙ контекст и сохранить
    /// её один раз.
    ///
    /// **Главный контекст сюда не передаётся вовсе, и это не экономия
    /// параметра.** Пока он был на входе, «на отказе его не трогаем»
    /// оставалось обещанием исполнителя; теперь страница физически
    /// не может его тронуть — у неё его нет.
    ///
    /// Вложенный вызов присоединяется к внешней странице, а не заводит
    /// свою: второй `save()` посреди страницы вернул бы ровно то,
    /// от чего мы ушли. Решение о напоминаниях принимает ВНЕШНЯЯ
    /// страница — она одна знает весь состав.
    static func партией(контейнер: ModelContainer,
                        _ принять: (ModelContext) -> Void) -> ИтогСтраницы {
        if let открытая = открытаяСтраница {
            принять(открытая)
            return ИтогСтраницы(записано: true, большеНеЖдут: [])
        }

        let страница = ModelContext(контейнер)
        // Явно, а не по умолчанию: автосохранение посреди страницы —
        // это и есть «частично».
        страница.autosaveEnabled = false
        открытаяСтраница = страница
        схемыСтраницы = []
        дозыСтраницы = []
        defer {
            открытаяСтраница = nil
            схемыСтраницы = []
            дозыСтраницы = []
        }

        принять(страница)

        // Решение «эти дозы больше не ждут» снимается ЗДЕСЬ: в контексте
        // страницы и ДО сохранения. Спрошенный в главном, он ответил бы
        // по прежней картине — отменённый приехавшей схемой курс
        // выглядел бы живым, и напоминание по его дозам осталось бы
        // стоять.
        let большеНеЖдут = дозыБезОжидания(context: страница)

        guard страница.hasChanges else {
            return ИтогСтраницы(записано: true, большеНеЖдут: большеНеЖдут)
        }
        do {
            try страница.save()
            return ИтогСтраницы(записано: true, большеНеЖдут: большеНеЖдут)
        } catch {
            // Возвращать нечего: контекст страницы здесь и кончается,
            // а главный её не видел. Гасить тоже нечего — решение
            // принято по тому, что не доехало.
            log.error("""
                общий дневник: страница не записалась — \
                \(String(describing: error))
                """)
            return ИтогСтраницы(записано: false, большеНеЖдут: [])
        }
    }

    /// Дозы страницы, которые больше не ждут отметки.
    ///
    /// **Два входа, и они не повторяют друг друга.** По дозам
    /// спрашивается `ждётОтметки` — предикат САМОЙ дозы, и про схему
    /// он не знает нарочно. По схемам спрашивается
    /// `ждётОтметкиСУчётомСхемы`: у доз отменённой схемы собственный
    /// `cancelledAt` пуст, то есть по первому предикату они по-прежнему
    /// ждут, и одним только входом по дозам они бы не погасли.
    ///
    /// Цена пропуска называется прямо, потому что она про лекарство:
    /// Виктория отменила курс, у мамы он жив, и мама получает «Через
    /// 10 минут доза» по лечению, которого больше нет.
    ///
    /// Выборка схемы под `do`, а не под `try?`: у `try?` склеены «такой
    /// схемы нет» (ответ — не гасить ничего) и «посмотреть не удалось»,
    /// и при отказе второе молча становится первым.
    private static func дозыБезОжидания(context: ModelContext) -> [UUID] {
        var итог: [UUID] = []
        var видели: Set<UUID> = []

        for схемаID in схемыСтраницы {
            do {
                guard let схема = try context.fetch(
                    FetchDescriptor<Medication>(predicate: #Predicate { $0.id == схемаID })
                ).first else { continue }
                for доза in схема.doses where !доза.ждётОтметкиСУчётомСхемы {
                    if видели.insert(доза.id).inserted { итог.append(доза.id) }
                }
            } catch {
                log.error("""
                    общий дневник: приехала схема \(схемаID), выборка \
                    по id отказала — напоминания по её дозам СЕЙЧАС \
                    не гаснут, погаснут при открытии приложения. \
                    \(String(describing: error))
                    """)
            }
        }

        // Доза — та, что лежит у нас ПОСЛЕ слияния, а не та, что
        // приехала: спор решает `SharedDiaryMerge`, и чужая отметка
        // могла проиграть своей.
        for дозаID in дозыСтраницы {
            guard let доза = доза(дозаID, context: context), !доза.ждётОтметки else { continue }
            if видели.insert(доза.id).inserted { итог.append(доза.id) }
        }
        return итог
    }

    /// Страница привезла схему — её дозы надо пересмотреть в конце.
    ///
    /// Тождество контекста, а не флаг: приём вне страницы (архив,
    /// тесты) не копит ничего и список не растит.
    private static func кСверке(схема id: UUID, context: ModelContext) {
        guard открытаяСтраница === context else { return }
        схемыСтраницы.append(id)
    }

    /// Страница привезла отметку дозы — её надо пересмотреть в конце.
    private static func кСверке(доза id: UUID, context: ModelContext) {
        guard открытаяСтраница === context else { return }
        дозыСтраницы.append(id)
    }

    /// Принять запись дневника с другого телефона.
    ///
    /// Исход — `ИсходПриёма`: `.вернуть`, если после слияния наша версия
    /// изменилась, `.отказ`, если выборка или запись не удались.
    @discardableResult
    static func accept(_ payload: EventPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            let event = LogEvent(kind: .note, date: payload.date, authorName: payload.authorName)
            event.id = payload.id
            event.apply(payload)
            event.dog = dog
            context.insert(event)
            // Приехавшая запись, которую не записали, вернётся следующим
            // кругом обмена — но круг станет вечным, если об этом молчать.
            guard записать(context, otherwise: { context.delete(event) }) else {
                log.error("общий дневник: запись не записалась")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние записи не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
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
    static func accept(_ payload: DogPayload, context: ModelContext) -> ИсходПриёма {
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
            return .принято
        }

        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<Dog>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let dog = Dog(name: payload.name, weightKg: payload.weightKg)
            dog.id = payload.id
            dog.apply(payload)
            context.insert(dog)
            guard записать(context, otherwise: { context.delete(dog) }) else {
                log.error("общий дневник: собака не записалась")
                return .отказ
            }
            // Крошка запуска уже умеет отличать приехавшую от заведённой
            // здесь — здесь мы это знаем точно, а не по разнице составов.
            //
            // **Текст разведён с `DogOrigin` 08.10.2026, и это починка
            // инструмента наблюдения, а не стиля.** До неё оба места
            // печатали дословно одно — «собака <id> — приехала
            // обменом», — хотя говорят о разном:
            //
            // ```
            // здесь                  МЫ завели из снимка, источник известен точно
            // DogOrigin:52           в составе прибавилось, положил кто-то мимо нас
            // ```
            //
            // Второе — единственная улика по зеркалу CloudKit, которого
            // мы не понимаем: девять разных `id` за шесть дней и пять
            // исчезновений, причина не установлена. Пока строки
            // совпадали, крошки читались обоими способами, то есть
            // не отвечали ни на один вопрос.
            //
            // > **Один текст на две причины хуже молчания: молчание
            // > заставляет спросить, а совпавшая строка даёт готовый
            // > неверный ответ.**
            //
            // Следствие, которое надо помнить при чтении старых
            // журналов: крошки, снятые ДО этого коммита, по данному
            // признаку не читаются вовсе.
            StartupLog.note("собака \(payload.id.uuidString.prefix(8)) — принята из общего дневника")
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние профиля не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
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
    static func accept(_ payload: ClinicPayload, context: ModelContext) -> ИсходПриёма {
        guard Fmt.notBlank(payload.name) != nil else {
            log.error("общий дневник: приехала клиника без имени — не принимаем")
            return .принято
        }
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<Clinic>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let clinic = Clinic(name: payload.name, detail: payload.detail,
                                isLab: payload.isLab, phone: payload.phone)
            clinic.id = payload.id
            clinic.createdAt = payload.createdAt
            clinic.changedAt = payload.changedAt
            context.insert(clinic)
            guard записать(context, otherwise: { context.delete(clinic) }) else {
                log.error("общий дневник: клиника не записалась")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние клиники не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
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
        // Одна реализация на четыре типа (04.11.2026): здесь стояла
        // дословная копия `клиника(id:имя:)` — два поиска одного правила
        // «по id, промах — по имени» расходятся молча.
        клиника(id: payload.clinicID, имя: payload.clinicName, context: context)
    }

    /// Принять взвешивание.
    ///
    /// **Нулевой вес не принимается**, и проверка стоит ЗДЕСЬ тоже,
    /// а не только в разборе записи: `accept` зовут и из тестов,
    /// минуя `CKRecord`. Проверка в одном из двух входов — это
    /// проверка, которую обойдут, не заметив.
    @discardableResult
    static func accept(_ payload: WeightPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        guard payload.kg > 0 else {
            log.error("общий дневник: приехало взвешивание с нулём — не принимаем")
            return .принято
        }
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let запись = WeightEntry(date: payload.date, kg: payload.kg)
            запись.id = payload.id
            запись.changedAt = payload.changedAt
            запись.dog = dog
            context.insert(запись)
            guard записать(context, otherwise: { context.delete(запись) }) else {
                log.error("общий дневник: взвешивание не записалось")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние взвешивания не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять документ.
    ///
    /// **Скан местного телефона не трогается.** В нагрузке его нет,
    /// и `apply` его не очищает: человек положил страницу паспорта
    /// у себя, и чужая правка номера не имеет права её стереть.
    @discardableResult
    static func accept(_ payload: DocumentPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<DogDocument>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let документ = DogDocument(title: payload.title)
            документ.id = payload.id
            документ.apply(payload)
            // Клиника сшивается здесь, а не в `apply`: там нет
            // контекста. Промах по id и по имени оставляет связь
            // пустой и клиники НЕ заводит — запись, рождённая промахом,
            // была бы дублем справочника. То же решение, что
            // у медкнижки.
            документ.clinic = клиника(id: payload.clinicID,
                                      имя: payload.clinicName, context: context)
            документ.dog = dog
            context.insert(документ)
            guard записать(context, otherwise: { context.delete(документ) }) else {
                log.error("общий дневник: документ не записался")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            // Связь сшивается по ПОБЕДИВШЕЙ версии, как у визита:
            // иначе спор решался бы по-разному для поля и для связи.
            if let сшита = клиника(id: merged.clinicID,
                                   имя: merged.clinicName, context: context) {
                local.clinic = сшита
            }
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние документа не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    // MARK: Медкнижка
    //
    // Четыре приёма, и все четыре по одной форме: нашли по id — слили,
    // не нашли — завели. Своих «сильных» полей здесь нет: медкнижка это
    // перепечатка документа, а не действие, и спор решает `changedAt`.

    /// Клиника для приехавшей записи медкнижки: по id, при промахе —
    /// по имени. Клинику по имени НЕ заводим: запись, рождённая
    /// промахом, была бы дублем справочника.
    private static func клиника(id: UUID?, имя: String?, context: ModelContext) -> Clinic? {
        if let id, let найдена = try? context.fetch(
            FetchDescriptor<Clinic>(predicate: #Predicate { $0.id == id })
        ).first {
            return найдена
        }
        guard let имя = Fmt.notBlank(имя ?? "") else { return nil }
        return try? context.fetch(FetchDescriptor<Clinic>()).first { $0.name == имя }
    }

    /// Принять строку анализа.
    @discardableResult
    static func accept(_ payload: LabResultPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<LabResult>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let анализ = LabResult(sampledOn: payload.sampledOn)
            анализ.id = payload.id
            анализ.apply(payload)
            анализ.dog = dog
            context.insert(анализ)
            guard записать(context, otherwise: { context.delete(анализ) }) else {
                log.error("общий дневник: анализ не записался")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние анализа не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять визит к врачу.
    @discardableResult
    static func accept(_ payload: VetVisitPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<VetVisit>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let визит = VetVisit(date: payload.date)
            визит.id = payload.id
            визит.apply(payload)
            визит.clinic = клиника(id: payload.clinicID, имя: payload.clinicName, context: context)
            визит.dog = dog
            context.insert(визит)
            guard записать(context, otherwise: { context.delete(визит) }) else {
                log.error("общий дневник: визит не записался")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            // Связь сшивается по ПОБЕДИВШЕЙ версии: иначе спор
            // решался бы по-разному для поля и для связи.
            if let сшита = клиника(id: merged.clinicID, имя: merged.clinicName, context: context) {
                local.clinic = сшита
            }
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние визита не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять диагноз.
    @discardableResult
    static func accept(_ payload: DiagnosisPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<Diagnosis>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let диагноз = Diagnosis(madeOn: payload.madeOn)
            диагноз.id = payload.id
            диагноз.apply(payload)
            диагноз.dog = dog
            context.insert(диагноз)
            guard записать(context, otherwise: { context.delete(диагноз) }) else {
                log.error("общий дневник: диагноз не записался")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние диагноза не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять назначение.
    @discardableResult
    static func accept(_ payload: PrescriptionPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<Prescription>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let рецепт = Prescription(date: payload.date)
            рецепт.id = payload.id
            рецепт.apply(payload)
            рецепт.clinic = клиника(id: payload.clinicID, имя: payload.clinicName, context: context)
            рецепт.dog = dog
            context.insert(рецепт)
            guard записать(context, otherwise: { context.delete(рецепт) }) else {
                log.error("общий дневник: назначение не записалось")
                return .отказ
            }
            return .принято
        }

        let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
        let changed = merged != payload
        if merged != local.payload {
            let былПрежний = local.payload
            local.apply(merged)
            if let сшита = клиника(id: merged.clinicID, имя: merged.clinicName, context: context) {
                local.clinic = сшита
            }
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние назначения не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять дело ухода.
    @discardableResult
    static func accept(_ payload: CarePayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        guard let existing = context.опознать(
            FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
            let task = CareTask(title: payload.title, detail: payload.detail)
            task.id = payload.id
            task.apply(payload)
            task.clinic = clinic(for: payload, context: context)
            task.dog = dog
            context.insert(task)
            guard записать(context, otherwise: { context.delete(task) }) else {
                log.error("общий дневник: дело ухода не записалось")
                return .отказ
            }
            return .принято
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
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние дела ухода не записалось")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }

    /// Принять схему лечения.
    ///
    /// **Связывание висящих доз.** Доза могла приехать раньше схемы —
    /// так бывает всегда, когда обмен включают посреди курса. Висящая
    /// ни на чём доза на экране не показывается вовсе, то есть второй
    /// человек видит приём открытым и даёт вторую таблетку. Поэтому
    /// приехавшая схема сразу забирает свои дозы.
    @discardableResult
    static func accept(_ payload: MedicationPayload, dog: Dog?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        // Приехала схема — значит её отмена или пауза могли приехать
        // вместе с ней, и напоминания по её дозам надо пересмотреть
        // в конце страницы. Отмечается ДО разбора и безусловно: так же,
        // как это делал вызывающий, пока список жил у него.
        кСверке(схема: id, context: context)
        guard let existing = context.опознать(
            FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        let схема: Medication
        var changed = false
        if let local = existing {
            let merged = SharedDiaryMerge.resolve(local: local.payload, remote: payload)
            changed = merged != payload
            if merged != local.payload {
                let былПрежний = local.payload
                local.apply(merged)
                if !записать(context, otherwise: { local.apply(былПрежний) }) {
                    log.error("общий дневник: слияние схемы не записалось")
                    return .отказ
                }
            }
            схема = local
        } else {
            // Надгробие на схему, которой у нас никогда не было,
            // заводить нечего — тот же страж, что у остальных десяти,
            // форма здесь другая (`if let`, а не `guard`).
            if payload.deletedAt != nil { return .принято }
            let свежая = Medication(name: payload.name, doseText: payload.doseText,
                                    times: payload.times)
            свежая.id = payload.id
            свежая.apply(payload)
            свежая.dog = dog
            context.insert(свежая)
            guard записать(context, otherwise: { context.delete(свежая) }) else {
                log.error("общий дневник: схема не записалась")
                return .отказ
            }
            схема = свежая
        }

        подобратьДозы(схемы: схема, context: context)
        return changed ? .вернуть : .принято
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
        // Копия в `let`: откат теперь может уехать в конец партии,
        // и держать он обязан тот состав, что связали здесь.
        let связанные = связали
        if !записать(context, otherwise: { связанные.forEach { $0.medication = nil } }) {
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

    /// Доза, какой она лежит у нас ПОСЛЕ приёма чужой отметки.
    ///
    /// Нужна тому, кто решает, снимать ли местные напоминания: спрашивать
    /// об этом приехавшую нагрузку нельзя. Спор двух телефонов решает
    /// `SharedDiaryMerge.resolve`, и чужая отметка могла его **проиграть**
    /// — тогда по нагрузке доза «отмечена», а у нас по-прежнему ждёт.
    /// Снять запрос по проигравшей отметке значило бы погасить
    /// напоминание о дозе, которую никто не дал.
    /// ## Почему здесь `do/catch`, а не `try?` — замер 14.10.2026
    ///
    /// Сторож `ОтказВыборкиПоIdTests` поймал это место **в день своего
    /// рождения**: он завёлся с долгом 15 по этому файлу, а вхождений
    /// стало 16. Шестнадцатое — вот это, и оно пришло вместе со второй
    /// половиной снятия напоминаний (`02b5ae9`).
    ///
    /// `try?` отдаёт `nil` и на «такой дозы нет», и на «не смог
    /// посмотреть». Решение вызывающего на `nil` — **не снимать
    /// напоминание** (`FamilySync:771-774`, `if let … !ждётОтметки`),
    /// и оно верное: не зная местного состояния, гасить запрос нельзя.
    ///
    /// Но из этого следует, что **отказ выборки молча возвращает ровно
    /// тот дефект, который чинил `b9ecc5f`**: мама отметила дозу,
    /// выборка отказала, напоминание продолжает звонить — и причины
    /// этого нет ни в одном журнале.
    ///
    /// > Поведение на отказе остаётся прежним нарочно. Меняется то,
    /// > что отказ перестаёт быть невидимым: прежде «нет такой дозы»
    /// > и «замер не состоялся» были неотличимы **по типу**.
    ///
    /// Долг числом не правился: сторож красен был по делу, и починка
    /// места дешевле записи в эталон. Остальные пятнадцать — отдельная
    /// работа, форма та же.
    static func доза(_ id: UUID, context: ModelContext) -> DoseRecord? {
        do {
            return try context.fetch(
                FetchDescriptor<DoseRecord>(predicate: #Predicate { $0.id == id })
            ).first
        } catch {
            log.error("""
                общий дневник: не смог посмотреть местную дозу — \
                напоминание останется, и это не «дозы нет»: \
                \(error.localizedDescription)
                """)
            return nil
        }
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
    static func accept(_ payload: DosePayload, medication: Medication?, context: ModelContext) -> ИсходПриёма {
        let id = payload.id
        // То же, что у схемы: отметка приехала — в конце страницы
        // спросим ту дозу, которая легла у нас после слияния.
        кСверке(доза: id, context: context)
        guard let existing = context.опознать(
            FetchDescriptor<DoseRecord>(predicate: #Predicate { $0.id == id })
        ).ответ else {
            log.error("общий дневник: выборка по id отказала — запись пропущена до следующего захода")
            return .отказ
        }

        guard let local = existing else {
            // Надгробие на запись, которой у нас НИКОГДА НЕ БЫЛО,
            // заводить нечего. Создать её, чтобы в ту же секунду скрыть,
            // значило бы положить человеку в базу запись, которой он
            // не видел, — тот же класс, что «мусор, который уходит
            // от нас к человеку, хуже мусора, который лежит у нас».
            if payload.deletedAt != nil { return .принято }
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
            guard записать(context, otherwise: { context.delete(dose) }) else {
                log.error("общий дневник: доза не записалась")
                return .отказ
            }
            return .принято
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
            if !записать(context, otherwise: { local.apply(былПрежний) }) {
                log.error("общий дневник: слияние дозы не записалось")
                return .отказ
            }
        } else if linked {
            if !записать(context, otherwise: { local.medication = nil }) {
                log.error("общий дневник: связь дозы с препаратом не записалась")
                return .отказ
            }
        }
        return changed ? .вернуть : .принято
    }
}
