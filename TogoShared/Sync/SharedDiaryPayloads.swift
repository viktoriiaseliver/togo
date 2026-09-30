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
            vetName: vetName,
            vetPhone: vetPhone,
            clinicName: clinicName,
            clinicPhone: clinicPhone,
            distinctiveMarks: distinctiveMarks,
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
        vetName = payload.vetName
        vetPhone = payload.vetPhone
        clinicName = payload.clinicName
        clinicPhone = payload.clinicPhone
        distinctiveMarks = payload.distinctiveMarks
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
            cancelledNote: cancelledNote, changedAt: changedAt
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
            RemoteDoseChange.post(dose)
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
            if context.persist(otherwise: { local.apply(былПрежний) }) {
                RemoteDoseChange.post(local)
            } else {
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

// MARK: - Чужая отметка дозы → напоминания

extension Notification.Name {
    /// Отметка дозы пришла с другого телефона и записалась в базу.
    ///
    /// Напоминания t-10/t+30/t+60 ставит `ReminderScheduler`, а он живёт
    /// в цели приложения: `TogoShared` собирается и в виджеты, поэтому
    /// позвать его отсюда нельзя. Без этого сигнала мама отмечала приём,
    /// а у второго человека через полчаса всё равно звенело «Доза
    /// не отмечена». Слушает цель приложения (см. `RemoteDoseChange`).
    static let togoRemoteDoseChanged = Notification.Name("togoRemoteDoseChanged")
}

/// Что лежит в `userInfo` сигнала `.togoRemoteDoseChanged`.
///
/// Кроме id дозы — препарат и назначенное время: у каждого телефона
/// дозы на день заводит свой `DoseScheduler.ensureDoses`, и у своей
/// дозы на тот же час id другой. Напоминания висят на СВОЁМ id,
/// поэтому слушателю нужно найти свою дозу того же препарата на ту же
/// минуту, а не только чужую по id.
nonisolated enum RemoteDoseChange {
    static let doseIDKey = "doseID"
    /// `UUID?` — препарат может ещё не приехать.
    static let medicationIDKey = "medicationID"
    static let scheduledAtKey = "scheduledAt"
    /// Доза закрыта: дана, пропущена или отменена. Только тогда
    /// напоминания надо снимать; открытую чужую дозу трогать незачем.
    static let isClosedKey = "isClosed"

    @MainActor
    static func post(_ dose: DoseRecord) {
        var info: [String: Any] = [
            doseIDKey: dose.id,
            scheduledAtKey: dose.scheduledAt,
            isClosedKey: dose.givenAt != nil || dose.skippedAt != nil || dose.cancelledAt != nil,
        ]
        if let medicationID = dose.medication?.id { info[medicationIDKey] = medicationID }
        NotificationCenter.default.post(name: .togoRemoteDoseChanged, object: nil, userInfo: info)
    }
}
