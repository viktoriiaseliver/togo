import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Ошибки чтения бэкапа. Каждая говорит, что случилось и что делать —
/// «не удалось импортировать» без объяснения бесполезно.
nonisolated enum BackupError: LocalizedError, Sendable {
    case unreadable
    case futureFormat(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "Файл не похож на копию из Togo. Нужен файл .json, который приложение сохранило само.")
        case .futureFormat(let version):
            String(localized: "Файл сделан более новой версией приложения (формат \(version)). Обнови Togo — и он его прочитает.")
        }
    }
}

nonisolated enum BackupService {
    static let currentFormatVersion = 1
    static let fileExtension = "json"

    // MARK: Выгрузка

    @MainActor
    static func archive(context: ModelContext, appVersion: String) throws -> BackupArchive {
        // Сохраняем перед выгрузкой. Без этого связи, добавленные только что,
        // в файл не попадут — человек увезёт бэкап без последних записей
        // и ничего не заметит. Тихая потеря данных в файле переноса — худшее,
        // что может сделать эта функция.
        //
        // Комментарий выше называл это худшим исходом, а строка под ним
        // была `try?` — то есть ровно им. Метод и так `throws`: отказ
        // обязан дойти до экрана, а не превратиться в файл без последних
        // записей.
        try context.save()

        let dogs = try context.fetch(FetchDescriptor<Dog>())
        // Детей берём явными выборками и раскладываем по собакам сами:
        // полагаться на то, что обратная связь уже materialised, нельзя.
        //
        // Все выборки — `try`, а не `try?`, и это замер 04.11.2026:
        // шесть разделов стояли под `try?`, три — под `try`. Отказ
        // выборки давал архив БЕЗ раздела, а человек видел «сохранено».
        // Тот же класс, что `try context.save()` строкой выше.
        let allStocks = try context.fetch(FetchDescriptor<FoodStock>())
        let allHeats = try context.fetch(FetchDescriptor<HeatRecord>())
        let allDocuments = try context.fetch(FetchDescriptor<DogDocument>())
        let allDaysOut = try context.fetch(FetchDescriptor<DayOut>())
        let members = try context.fetch(FetchDescriptor<FamilyMember>())
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        // Навыки процедур — корневой список: связи с собакой у них нет.
        let skills = try context.fetch(FetchDescriptor<ProcedureSkill>())
        // Справочник клиник — тоже корневой и по той же причине.
        let clinics = try context.fetch(FetchDescriptor<Clinic>())

        return BackupArchive(
            createdAt: Date(),
            appVersion: appVersion,
            dogs: dogs.map { dog in
                snapshot(dog,
                         stocks: allStocks.filter { $0.dog?.persistentModelID == dog.persistentModelID },
                         heats: allHeats.filter { $0.dog?.persistentModelID == dog.persistentModelID },
                         documents: allDocuments.filter { $0.dog?.persistentModelID == dog.persistentModelID },
                         daysOut: allDaysOut.filter { $0.dog?.persistentModelID == dog.persistentModelID })
            },
            members: members.map { member in
                BackupArchive.MemberSnapshot(
                    name: member.name, roleRaw: member.roleRaw, note: member.note,
                    isMe: member.isMe, customPermissionsRaw: member.customPermissionsRaw,
                    isOnDuty: member.isOnDuty, dutyUntil: member.dutyUntil,
                    accessExpiresAt: member.accessExpiresAt, acceptedAt: member.acceptedAt
                )
            },
            episodes: episodes.map {
                BackupArchive.EpisodeSnapshot(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                              title: $0.title, detail: $0.detail,
                                              lastIncidentAt: $0.lastIncidentAt)
            },
            procedureSkills: skills.map {
                BackupArchive.ProcedureSkillSnapshot(
                    title: $0.title, detail: $0.detail, statusRaw: $0.statusRaw,
                    targetDate: $0.targetDate, successes: $0.successes,
                    attempts: $0.attempts)
            },
            clinics: clinics.map {
                BackupArchive.ClinicSnapshot(
                    name: $0.name, detail: $0.detail, isLab: $0.isLab,
                    phone: $0.phone, createdAt: $0.createdAt)
            }
        )
    }

    @MainActor
    private static func snapshot(
        _ dog: Dog,
        stocks: [FoodStock] = [],
        heats: [HeatRecord] = [],
        documents: [DogDocument] = [],
        daysOut: [DayOut] = []
    ) -> BackupArchive.DogSnapshot {
        BackupArchive.DogSnapshot(
            name: dog.name, photo: dog.photo, breed: dog.breed, birthDate: dog.birthDate,
            weightKg: dog.weightKg, targetWeightLow: dog.targetWeightLow,
            targetWeightHigh: dog.targetWeightHigh, foodBrand: dog.foodBrand,
            portionGrams: dog.portionGrams, mealsPerDay: dog.mealsPerDay,
            mealTimes: dog.mealTimes, forbiddenFoods: dog.forbiddenFoods,
            dailyNormGrams: dog.dailyNormGrams,
            rewards: dog.rewards, trainingFoodFromPortion: dog.trainingFoodFromPortion,
            markerKindRaw: dog.markerKindRaw, sessionLengthMinutes: dog.sessionLengthMinutes,
            isOnTreatment: dog.isOnTreatment, createdAt: dog.createdAt,
            sexRaw: dog.sexRaw, isNeutered: dog.isNeutered,
            wakeMinuteOfDay: dog.wakeMinuteOfDay, sleepMinuteOfDay: dog.sleepMinuteOfDay,
            chipNumber: dog.chipNumber, passportNumber: dog.passportNumber,
            insuranceNumber: dog.insuranceNumber,
            vetName: dog.vetName, vetPhone: dog.vetPhone,
            clinicName: dog.clinicName, clinicPhone: dog.clinicPhone,
            distinctiveMarks: dog.distinctiveMarks,
            sitterFood: dog.sitterFood, sitterDose: dog.sitterDose,
            sitterWalks: dog.sitterWalks, sitterForbidden: dog.sitterForbidden,
            sitterEscalation: dog.sitterEscalation,
            events: dog.events.map { event in
                BackupArchive.EventSnapshot(
                    id: event.id, date: event.date, kindRaw: event.kindRaw,
                    authorName: event.authorName, isSynced: event.isSynced, note: event.note,
                    outcomeRaw: event.outcomeRaw, askSignalRaw: event.askSignalRaw,
                    durationSeconds: event.durationSeconds, stoolFormRaw: event.stoolFormRaw,
                    stoolFlagsRaw: event.stoolFlagsRaw, grams: event.grams,
                    milliliters: event.milliliters, fromPortion: event.fromPortion,
                    incidentKindRaw: event.incidentKindRaw, incidentDetailRaw: event.incidentDetailRaw,
                    toldFamily: event.toldFamily, deletedAt: event.deletedAt, deletedBy: event.deletedBy,
                    isDayOnly: event.isDayOnly, enteredAt: event.enteredAt,
                    editedBy: event.editedBy,
                    originRaw: event.originRaw,
                    reactionTriggerRaw: event.reactionTriggerRaw,
                    reactionDistanceRaw: event.reactionDistanceRaw,
                    walkEventID: event.walkEventID, careTaskID: event.careTaskID,
                    medicationID: event.medicationID,
                    trainingSessionID: event.trainingSessionID
                )
            },
            weights: dog.weights.map { BackupArchive.WeightSnapshot(date: $0.date, kg: $0.kg) },
            careTasks: dog.careTasks.map {
                BackupArchive.CareTaskSnapshot(
                    title: $0.title, detail: $0.detail, intervalDays: $0.intervalDays,
                    lastDone: $0.lastDone, categoryRaw: $0.categoryRaw,
                    seasonStartMonth: $0.seasonStartMonth, seasonEndMonth: $0.seasonEndMonth,
                    snoozeCount: $0.snoozeCount,
                    kindRaw: $0.kindRaw, scheduledDate: $0.scheduledDate,
                    remindDaysBefore: $0.remindDaysBefore, streak: $0.streak,
                    // Клиника — ИМЕНЕМ, и имя берётся у связи, а не
                    // у поля `Dog.clinicName`: это разные клиники.
                    // Второе — врач собаки для листа ситтера, первое —
                    // где делали эту прививку.
                    clinicName: $0.clinic?.name,
                    vaccineBatch: $0.vaccineBatch,
                    vaccineValidUntil: $0.vaccineValidUntil
                )
            },
            medications: dog.medications.map { medication in
                BackupArchive.MedicationSnapshot(
                    name: medication.name, doseText: medication.doseText, times: medication.times,
                    fastingMinutes: medication.fastingMinutes,
                    fastingBeforeMinutes: medication.fastingBeforeMinutes,
                    isPaused: medication.isPaused,
                    prescriber: medication.prescriber, cancelledAt: medication.cancelledAt,
                    cancelledNote: medication.cancelledNote,
                    doses: medication.doses.map {
                        BackupArchive.DoseSnapshot(scheduledAt: $0.scheduledAt, givenAt: $0.givenAt,
                                                   givenBy: $0.givenBy, cancelledAt: $0.cancelledAt,
                                                   cancelReason: $0.cancelReason,
                                                   skippedAt: $0.skippedAt, skippedBy: $0.skippedBy,
                                                   claimedBy: $0.claimedBy, claimedAt: $0.claimedAt,
                                                   awaitedMedicationName: $0.awaitedMedicationName)
                    },
                    unitRaw: medication.unitRaw,
                    massPerUnitMcg: medication.massPerUnitMcg,
                    minutesAfterMeal: medication.minutesAfterMeal,
                    dependsOnMeal: medication.dependsOnMeal,
                    doseSlots: medication.doseSlotsData,
                    courseEnd: medication.courseEnd,
                    expiry: medication.expiry,
                    openedAt: medication.openedAt,
                    shelfAfterOpenDays: medication.shelfAfterOpenDays,
                    remindBeforeExpiry: medication.remindBeforeExpiry,
                    stockLeft: medication.stockLeft,
                    stockTotal: medication.stockTotal,
                    stockLeftAmount: medication.stockLeftAmount,
                    packAmount: medication.packAmount,
                    canGiveOutside: medication.canGiveOutside,
                    prescriptionNumber: medication.prescriptionNumber,
                    startedAt: medication.startedAt
                )
            },
            trainingSteps: dog.trainingSteps.map {
                BackupArchive.TrainingStepSnapshot(
                    cue: $0.cue, place: $0.place, person: $0.person,
                    distanceMeters: $0.distanceMeters, statusRaw: $0.statusRaw,
                    consecutiveGoodSessions: $0.consecutiveGoodSessions, order: $0.order
                )
            },
            trainingSessions: dog.trainingSessions.map {
                BackupArchive.TrainingSessionSnapshot(
                    startedAt: $0.startedAt, durationSeconds: $0.durationSeconds, cue: $0.cue,
                    place: $0.place, person: $0.person, distanceMeters: $0.distanceMeters,
                    markDelaysMs: $0.markDelaysMs, successes: $0.successes, attempts: $0.attempts,
                    gramsUsed: $0.gramsUsed, observationsRaw: $0.observationsRaw,
                    countsTowardProgress: $0.countsTowardProgress
                )
            },
            trips: dog.trips.map {
                BackupArchive.TripSnapshot(
                    destination: $0.destination, startDate: $0.startDate, endDate: $0.endDate,
                    transportRaw: $0.transportRaw, travelHours: $0.travelHours, lodging: $0.lodging,
                    participants: $0.participants, departureMinuteOfDay: $0.departureMinuteOfDay,
                    packedItems: $0.packedItems
                )
            },
            stocks: stocks.map {
                BackupArchive.StockSnapshot(kindRaw: $0.kindRaw, brand: $0.brand,
                                            packGrams: $0.packGrams, packsLeft: $0.packsLeft,
                                            gramsPerDay: $0.gramsPerDay, openedAt: $0.openedAt,
                                            expiry: $0.expiry,
                                            shelfAfterOpenDays: $0.shelfAfterOpenDays,
                                            countedAt: $0.countedAt)
            },
            heats: heats.map {
                BackupArchive.HeatSnapshot(startedAt: $0.startedAt, endedAt: $0.endedAt, note: $0.note)
            },
            documents: documents.map {
                BackupArchive.DocumentSnapshot(title: $0.title, image: $0.image,
                                               addedAt: $0.addedAt, note: $0.note,
                                               kindRaw: $0.kindRaw, number: $0.number,
                                               issuedBy: $0.issuedBy,
                                               validUntil: $0.validUntil,
                                               occurredOn: $0.occurredOn,
                                               directionRaw: $0.directionRaw,
                                               clinicName: $0.clinic?.name,
                                               deletedAt: $0.deletedAt)
            },
            daysOut: daysOut.map {
                BackupArchive.DayOutSnapshot(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                             plannedHours: $0.plannedHours, note: $0.note)
            },
            // Медкнижка — 07.10.2026. Собирается здесь, а не отдельным
            // проходом: `togo-1e` нашёл сегодня три поля, объявленные
            // в снимке и не заполненные сборщиком, и сторож паритета
            // такое не ловит — он сверяет ИМЕНА.
            labResults: dog.labResults.map {
                BackupArchive.LabResultSnapshot(
                    sampledOn: $0.sampledOn, sampledAt: $0.sampledAt,
                    laboratory: $0.laboratory, reportNumber: $0.reportNumber,
                    section: $0.section, indicator: $0.indicator,
                    value: $0.value, belowLimit: $0.belowLimit,
                    aboveLimit: $0.aboveLimit, textValue: $0.textValue,
                    unit: $0.unit,
                    referenceLow: $0.referenceLow, referenceHigh: $0.referenceHigh,
                    method: $0.method, labMark: $0.labMark, note: $0.note)
            },
            vetVisits: dog.vetVisits.map {
                BackupArchive.VetVisitSnapshot(
                    date: $0.date, clinicName: $0.clinic?.name, doctor: $0.doctor,
                    reasonRaw: $0.reasonRaw, conclusion: $0.conclusion)
            },
            diagnoses: dog.diagnoses.map {
                BackupArchive.DiagnosisSnapshot(
                    wording: $0.wording, statusRaw: $0.statusRaw,
                    madeOn: $0.madeOn, madeBy: $0.madeBy, evidence: $0.evidence)
            },
            prescriptions: dog.prescriptions.map {
                BackupArchive.PrescriptionSnapshot(
                    number: $0.number, date: $0.date, clinicName: $0.clinic?.name,
                    doctor: $0.doctor, dogWeightKg: $0.dogWeightKg,
                    medicationName: $0.medicationName, dosage: $0.dosage,
                    schedule: $0.schedule, duration: $0.duration,
                    pharmacyForm: $0.pharmacyForm,
                    controlFromWeeks: $0.controlFromWeeks,
                    controlToWeeks: $0.controlToWeeks,
                    dispensed: $0.dispensed, instruction: $0.instruction,
                    source: $0.source)
            },
            // Надгробие собаки — 26.10.2026. Разбор в объявлении поля:
            // список собак идёт в архив нефильтрованным, и без этой
            // строки восстановление поднимало удалённую собаку живой.
            deletedAt: dog.deletedAt
        )
    }

    // MARK: Файл

    static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(BackupArchive.self, from: data) else {
            throw BackupError.unreadable
        }
        guard archive.formatVersion <= currentFormatVersion else {
            throw BackupError.futureFormat(archive.formatVersion)
        }
        return archive
    }

    /// Дата в имени — местная, а не UTC: человек ищет файл по тому дню,
    /// в который он его сделал, а не по гринвичу.
    static func fileName(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "togo-\(stamp).\(fileExtension)"
    }

    // MARK: Загрузка

    /// Что делать с тем, что уже есть на устройстве.
    enum Strategy: String, CaseIterable, Sendable {
        /// Стереть всё и положить содержимое файла. Переезд на новый телефон.
        case replace
        /// Добавить, чего нет.
        ///
        /// **Лента сверяется по идентификатору, остальные четырнадцать
        /// коллекций — по естественным ключам.** `id` несёт один снимок
        /// из пятнадцати (`EventSnapshot`); у прочих его нет нарочно —
        /// «после восстановления это ДРУГАЯ запись в другом хранилище»
        /// (`ArchiveParityTests`). Чем опознаётся «та же запись»
        /// у каждого вида, перечислено у `attachRest`.
        ///
        /// Здесь стояло «записи сверяются по идентификатору»: про ленту
        /// правда, про остальное — нет, и обещание `detail` («повторы
        /// не задвоятся») держал один этот комментарий.
        case merge

        var title: String {
            switch self {
            case .replace: String(localized: "Заменить всё")
            case .merge: String(localized: "Добавить недостающее")
            }
        }

        var detail: String {
            switch self {
            case .replace: String(localized: "то, что сейчас на телефоне, будет стёрто")
            case .merge: String(localized: "существующие записи останутся, повторы не задвоятся")
            }
        }
    }

    /// Положить содержимое файла в хранилище и вернуть, сколько записей
    /// в нём прибавилось.
    ///
    /// # Две стратегии и одно правило на двоих
    ///
    /// ```
    /// replace  всё стереть и положить файл; опознавать нечего
    /// merge    долить недостающее: собаки и участники сливаются
    ///          по имени, лента — по `id`, остальное — по естественным
    ///          ключам (перечень у `attachRest`)
    /// ```
    ///
    /// При `merge` существующая собака получает: ленту, все четырнадцать
    /// прочих коллекций и **пустые** поля профиля. Заполненное руками
    /// не трогается — разбор у `дополнитьПрофиль`.
    ///
    /// # Чего `merge` НЕ приносит, и почему это решение
    ///
    /// **Эпизоды и навыки процедур** восстанавливаются только при
    /// `replace`. Опознать «тот же эпизод» нечем: `id` в снимке у них
    /// нет, связи с собакой нет тоже, а склейка по названию собрала бы
    /// в одну группу всё безымянное —
    ///
    /// > **группировка по полю со значением по умолчанию собирает
    /// > в одну группу всё, что это поле не заполнило.**
    ///
    /// Цена названа, а не обойдена: человек, доливающий файл, эпизодов
    /// и навыков не получит. Цена обратного выбора больше — разные
    /// эпизоды, склеенные в один, и разделить их потом нечем.
    /// Перестанет быть верным, если в `EpisodeSnapshot`
    /// и `ProcedureSkillSnapshot` появится устойчивый идентификатор.
    ///
    /// # Граница возвращаемого числа
    ///
    /// **Справочник клиник в счёт не входит** — цикл по
    /// `archive.clinics` вставляет записи без `restored += 1`. Это
    /// названо, а не починено: клиника не запись дневника, а строка
    /// справочника, и человек, читающий «Добавлено новых записей»,
    /// ищет глазами свои анализы и визиты. Понадобится считать и их —
    /// менять придётся и подпись на экране, а она живёт в каталоге
    /// строк на пяти языках.
    @MainActor
    @discardableResult
    static func restore(_ archive: BackupArchive, into целевой: ModelContext, strategy: Strategy) throws -> Int {
        // # Всё или ничего — отдельный контекст и ОДИН `save`
        //
        // До 04.11.2026 работа шла прямо в `mainContext`, и «заменить»
        // чистило хранилище `delete(model:)` — пакетным удалением, которое
        // уходит в хранилище без ожидания `save`. Бросок на полпути
        // (битый снимок, отказ выборки) оставлял дневник уже стёртым,
        // а вставленную половину — в контексте под автосохранением:
        // человек получал «Не получилось восстановить» и полупустой
        // дневник, который через секунду записывался сам.
        //
        // Теперь: свои изменения сначала записываются (иначе рабочий
        // контекст их не увидит), чистка поштучная, автосохранение
        // выключено, и в хранилище всё уходит одним `save` в конце.
        // Бросок — и рабочий контекст просто выбрасывается вместе со
        // всем, что успел натворить; хранилище остаётся прежним.
        try целевой.save()
        let context = ModelContext(целевой.container)
        context.autosaveEnabled = false

        func удалитьВсе<T: PersistentModel>(_ тип: T.Type) throws {
            for запись in try context.fetch(FetchDescriptor<T>()) { context.delete(запись) }
        }

        if strategy == .replace {
            // `ProcedureSkill` добавлен 07.10.2026 вместе с его снимком:
            // без чистки «заменить» удвоило бы навыки, потому что
            // опознать их при вставке нечем.
            for model in [LogEvent.self, WeightEntry.self, DoseRecord.self, Medication.self,
                          CareTask.self, TrainingSession.self, TrainingStep.self,
                          Trip.self, Episode.self, ProcedureSkill.self,
                          // `Clinic` — 07.10.2026, вместе со снимком.
                          // Без чистки «заменить» удвоило бы справочник:
                          // слияние по имени работает только в ветке
                          // «долить», а здесь имя уже занято старой
                          // записью, и человек получил бы одиннадцать
                          // организаций Стича дважды.
                          Clinic.self,
                          // Медкнижка — 07.10.2026. Поимённо, хотя у всех
                          // четырёх каскад от собаки: каскад срабатывает
                          // по связи, а запись с пустым `dog` каскадом
                          // не убирается и осталась бы сиротой. Ровно
                          // тот класс, из-за которого здесь уже стоят
                          // `LogEvent` и `WeightEntry`.
                          LabResult.self, VetVisit.self,
                          Diagnosis.self, Prescription.self,
                          FamilyMember.self, Dog.self] as [any PersistentModel.Type] {
                try удалитьВсе(model)
            }
        }

        let existingEventIDs: Set<UUID> = strategy == .merge
            ? Set(try context.fetch(FetchDescriptor<LogEvent>()).map(\.id))
            : []
        let existingDogNames: Set<String> = strategy == .merge
            ? Set(try context.fetch(FetchDescriptor<Dog>()).map(\.name))
            : []
        let existingMemberNames: Set<String> = strategy == .merge
            ? Set(try context.fetch(FetchDescriptor<FamilyMember>()).map(\.name))
            : []

        var restored = 0

        // Справочник клиник — ДО собак: дела ухода ссылаются на него,
        // и ссылка восстанавливается только из уже вставленной записи.
        //
        // **Слияние по имени здесь осмысленно, в отличие от собак.**
        // У собак две «Стич» в одном доме — две собаки, у клиник
        // наоборот: дизайн требует справочника без дублей, и две
        // записи «Vet Riviera» это одна организация, набранная дважды.
        // Но проверка на пустоту обязательна по той же причине, что
        // у собак: пустое имя клиникой не является, а группировка
        // по полю со значением по умолчанию собирает в одну группу
        // всё, что это поле не заполнило.
        var клиники: [String: Clinic] = [:]
        if strategy == .merge {
            for clinic in try context.fetch(FetchDescriptor<Clinic>()) {
                guard let имя = Fmt.notBlank(clinic.name) else { continue }
                клиники[имя] = clinic
            }
        }
        for snapshot in archive.clinics ?? [] {
            guard let имя = Fmt.notBlank(snapshot.name) else { continue }
            if клиники[имя] != nil { continue }
            let clinic = Clinic(name: имя, detail: snapshot.detail,
                                isLab: snapshot.isLab, phone: snapshot.phone)
            clinic.createdAt = snapshot.createdAt
            context.insert(clinic)
            клиники[имя] = clinic
        }

        for snapshot in archive.dogs {
            // Слияние идёт по кличке — и **только по настоящей кличке**.
            //
            // **Нашлось замером 07.10.2026, искали другое.** Условие
            // стояло `existingDogNames.contains(snapshot.name)` без
            // проверки на пустоту. Если в хранилище лежит хоть одна
            // безымянная запись, в наборе кличек есть `""` — и
            // безымянная собака ИЗ АРХИВА сливалась с ней: её отметки,
            // дозы и взвешивания приписывались чужой записи, про
            // которую мы даже не знаем, что это.
            //
            // Две безымянные из архива при этом схлопывались в одну.
            //
            // У приёма снимка это правило записано прямо: «слияния
            // по кличке быть не должно ни при каких условиях — две
            // „Стич“ в одном доме это две собаки». Здесь слияние
            // по кличке осмысленно (человек сам льёт свой же архив
            // поверх своего же дневника), но **пустая кличка кличкой
            // не является**, и склеивать по ней — то же, что склеивать
            // по отсутствию признака.
            //
            // > **Группировка по полю со значением по умолчанию
            // > собирает в одну группу всё, что это поле не заполнило.**
            if strategy == .merge, let имя = Fmt.dogName(snapshot.name),
               existingDogNames.contains(имя) {
                // Собака уже есть — доливаем к ней всё, чего у неё нет.
                //
                // **Здесь стоял один `attachEvents`, и это был самый
                // дорогой пропуск переноса.** Человек выбирал «Добавить
                // недостающее», получал «Добавлено новых записей: N» —
                // и получал ОДНУ ЛЕНТУ: профиль (чип, паспорт, врач,
                // режим дня, лист ситтера), веса, дела ухода, схемы
                // лечения, дозы, анализы, визиты, диагнозы, рецепты,
                // документы, запасы, течки, выезды, обучение и поездки
                // не приезжали вовсе. Отзыв владелицы дословно:
                // «добавило в логи истории, а не туда куда надо».
                //
                // > **Ветка, которая делает часть обещанного и считает
                // > сделанное, выглядит удачной.** Счётчик был прав про
                // > ленту и молчал про остальные четырнадцать коллекций,
                // > то есть отчитывался о том, что сделал, а не о том,
                // > что обещал экран.
                //
                // **Эпизоды и навыки процедур сюда НЕ доливаются, и это
                // решение, а не забывчивость.** Они восстанавливаются
                // только при «заменить» (ниже), потому что опознать
                // «тот же эпизод» нечем: `id` в снимке нет, связи
                // с собакой у обоих нет тоже, а склейка по названию
                // собрала бы в одну группу всё безымянное —
                //
                // > **группировка по полю со значением по умолчанию
                // > собирает в одну группу всё, что это поле
                // > не заполнило.**
                //
                // Цена записана прямо: человек, доливающий файл,
                // эпизодов и навыков не получит. Цена обратного выбора
                // больше — разные эпизоды, склеенные в один, и разделить
                // их потом нечем.
                if let dog = try context.fetch(FetchDescriptor<Dog>()).first(where: { $0.name == имя }) {
                    дополнитьПрофиль(snapshot, у: dog)
                    restored += attachEvents(snapshot.events, to: dog, skipping: existingEventIDs, context: context)
                    restored += attachRest(snapshot, to: dog, clinics: клиники, context: context)
                }
                continue
            }
            // Третья поверхность дефекта «пустые собаки» (отзыв 06.10.2026
            // по сборке 271). Первые две — разбор записи CloudKit
            // и приём снимка; здесь кличка бралась из архива без единой
            // проверки, и круг замыкался: безымянная попала в хранилище →
            // уехала в архив → приехала обратно после починки приёма.
            //
            // **Реакция здесь другая, чем на приёме, и это не поблажка.**
            // На приёме приезжает ЧУЖОЙ свежий профиль, за которым ничего
            // не стоит: отклонить — значит не завести лишнюю строку.
            // В архиве лежит СВОЙ дневник, и за безымянной собакой может
            // стоять вся история — отметки, дозы, взвешивания. Выбросить
            // её молча значило бы потерять данные человека, чиня
            // косметику.
            //
            // Поэтому правило ровно то же, что принято для уборки:
            // безымянная удаляется (здесь — не восстанавливается), только
            // если **ничего за собой не тянет**. Безымянная с историей
            // восстанавливается как есть: это не мусор, а улика о семени,
            // которого мы пока не нашли, и человеку она важнее нашей
            // чистоты.
            if !DogPayload.hasUsableName(snapshot.name), ничегоНеТянет(snapshot) {
                continue
            }
            let dog = makeDog(snapshot)
            context.insert(dog)
            // **Третий вход фото собаки, и он приезжает с другого
            // телефона.** Фото стало подложкой всего приложения
            // (решение дизайна 23.10.2026, круг 2 п. 1), а
            // `BackgroundStore` живёт в App Group и базу не читает —
            // байты ему отдают у точки записи.
            //
            // Человек, переехавший на новый телефон, ждёт того же вида,
            // что был: без этой строки он получил бы чёрные вкладки
            // при живом `Dog.photo`.
            //
            // > **Фото здесь НЕ ужато.** Остальные два входа зовут
            // > `ФонФото.ужать` (1000 px, JPEG 0,8); в копию же байты
            // > попали такими, какими лежали в базе — в том числе
            // > снятые до того, как ужиматель появился. Ужимать их
            // > здесь нельзя: это тихая правка чужих данных при
            // > восстановлении. Но и в App Group полноразмерный блоб
            // > опасен — его читает **расширение виджета**, где память
            // > жёстко ограничена (3000 px декодируется примерно
            // > в 36 МБ). Ужатие на стороне `BackgroundStore` —
            // > отдельная работа, и она названа, а не сделана
            // > попутно.
            if let фото = dog.photo {
                BackgroundStore.shared.запомнитьФотоСобаки(фото)
            }
            restored += attachEvents(snapshot.events, to: dog, skipping: existingEventIDs, context: context)
            // Счёт из медчасти идёт в `restored` и здесь: до 29.10.2026
            // `attachRest` не возвращал ничего, и «Добавлено новых
            // записей» считало одну ленту. У собаки, восстановленной
            // вместе со 140 анализами и 40 визитами, экран печатал
            // число отметок дневника — то есть умалчивал ровно о том,
            // ради чего файл и собран.
            restored += attachRest(snapshot, to: dog, clinics: клиники, context: context)
        }

        // Участники сливаются по имени — и тот же класс, что у собак:
        // `FamilyMember.name` по умолчанию `""`, и безымянный участник
        // из архива слился бы с безымянным из хранилища. Проверка
        // на пустоту делает «сливать по имени» осмысленным:
        // пустое имя именем не является.
        for snapshot in archive.members
        where !(strategy == .merge && Fmt.notBlank(snapshot.name) != nil
                && existingMemberNames.contains(snapshot.name)) {
            let member = FamilyMember(name: snapshot.name,
                                      role: FamilyRole(rawValue: snapshot.roleRaw) ?? .helper,
                                      isMe: snapshot.isMe)
            member.note = snapshot.note
            member.customPermissionsRaw = snapshot.customPermissionsRaw
            member.isOnDuty = snapshot.isOnDuty
            member.dutyUntil = snapshot.dutyUntil
            member.accessExpiresAt = snapshot.accessExpiresAt
            member.acceptedAt = snapshot.acceptedAt
            context.insert(member)
            restored += 1
        }

        if strategy == .replace {
            // Навыки процедур: корневой список, собаки у них нет.
            // В ветке «долить» не восстанавливаются по той же причине,
            // что эпизоды, — опознать «тот же навык» нечем: ни `id`
            // в снимке, ни связи, а склейка по названию собрала бы
            // в одну группу всё, что названия не заполнило.
            // Наш класс, оплаченный сегодня четырьмя случаями.
            for snapshot in archive.procedureSkills ?? [] {
                let skill = ProcedureSkill(title: snapshot.title, detail: snapshot.detail,
                                           targetDate: snapshot.targetDate)
                skill.statusRaw = snapshot.statusRaw
                skill.successes = snapshot.successes
                skill.attempts = snapshot.attempts
                context.insert(skill)
            }
            for snapshot in archive.episodes {
                let episode = Episode(title: snapshot.title, detail: snapshot.detail, startedAt: snapshot.startedAt)
                episode.endedAt = snapshot.endedAt
                // Последний инцидент держит КОНЕЦ эпизода: `isOngoing`
                // сравнивает `now − lastIncidentAt` с сорока восьмью
                // часами. В `init` это поле равно `startedAt`, поэтому
                // без восстановления тишина считалась бы от начала —
                // и эпизод, у которого инциденты шли пять дней,
                // объявился бы законченным задним числом.
                episode.lastIncidentAt = snapshot.lastIncidentAt ?? snapshot.startedAt
                context.insert(episode)
            }
        }

        // Сохраняем сразу: восстановление должно пережить закрытие
        // приложения, даже если человек тут же его убьёт. Заодно связи
        // применяются, и экраны показывают восстановленное, а не пустоту.
        //
        // Здесь стоял `try?`, и обещание строкой выше держал один лишь
        // комментарий: при отказе функция возвращала число восстановленных
        // записей, экран показывал «Восстановлено», а в хранилище не было
        // ничего. Метод и так объявлен `throws`, а вызывающий
        // (`BackupScreen.restore`) уже ловит и показывает «Не получилось
        // восстановить» — возможность промолчать была заведена здесь
        // без всякой нужды.
        try context.save()

        return restored
    }

    /// Тянет ли снимок собаки за собой хоть одну запись.
    ///
    /// Перечислены **все одиннадцать** коллекций снимка — не выборка.
    ///
    /// **Предупреждение, стоявшее здесь утром, сбылось к вечеру того же
    /// дня, и сбылось моей же правкой.** Было написано: «если в архиве
    /// появится одиннадцатая, здесь её не будет, и безымянная собака
    /// с записями нового вида пропадёт при восстановлении молча».
    /// Одиннадцатой оказались `daysOut` — те самые выезды, про которые
    /// здесь же стояло «в архиве их нет вовсе, и это не этой работы».
    /// Оказалось — этой.
    ///
    /// > **Срок жизни предупреждения «если появится X» измеряется
    /// > часами, а не месяцами, когда X уже назван поимённо рядом.**
    ///
    /// Сторож на полноту перечня теперь есть — `ArchiveParityTests`:
    /// каждая каскадная связь `Dog` обязана быть в `DogSnapshot` либо
    /// названа исключением с причиной.
    private static func ничегоНеТянет(_ snapshot: BackupArchive.DogSnapshot) -> Bool {
        snapshot.events.isEmpty
            && snapshot.weights.isEmpty
            && snapshot.careTasks.isEmpty
            && snapshot.medications.isEmpty
            && snapshot.trainingSteps.isEmpty
            && snapshot.trainingSessions.isEmpty
            && snapshot.trips.isEmpty
            && (snapshot.stocks ?? []).isEmpty
            && (snapshot.heats ?? []).isEmpty
            && (snapshot.documents ?? []).isEmpty
            && (snapshot.daysOut ?? []).isEmpty
    }

    @MainActor
    private static func makeDog(_ snapshot: BackupArchive.DogSnapshot) -> Dog {
        let dog = Dog(name: snapshot.name, weightKg: snapshot.weightKg)
        dog.photo = snapshot.photo
        dog.breed = snapshot.breed
        dog.birthDate = snapshot.birthDate
        dog.targetWeightLow = snapshot.targetWeightLow
        dog.targetWeightHigh = snapshot.targetWeightHigh
        dog.foodBrand = snapshot.foodBrand
        dog.portionGrams = snapshot.portionGrams   // ниже пересчитается из нормы
        dog.mealsPerDay = snapshot.mealsPerDay
        dog.mealTimes = snapshot.mealTimes
        dog.forbiddenFoods = snapshot.forbiddenFoods
        // Архив мог быть записан старой версией, где количество еды жило
        // в двух полях сразу и они не сходились. Приводим к одному числу
        // тут же, а не оставляем расхождение на потом.
        dog.setDailyGrams(snapshot.dailyNormGrams
                          ?? max(0, snapshot.portionGrams * max(1, snapshot.mealsPerDay)))
        dog.rewards = snapshot.rewards
        dog.trainingFoodFromPortion = snapshot.trainingFoodFromPortion
        dog.markerKindRaw = snapshot.markerKindRaw
        dog.sessionLengthMinutes = snapshot.sessionLengthMinutes
        dog.isOnTreatment = snapshot.isOnTreatment
        dog.createdAt = snapshot.createdAt
        // Семнадцать полей, добавленных 07.10.2026. Там, где поле
        // непустое по типу, стоит `?? dog.<поле>` — то есть значение
        // по умолчанию МОДЕЛИ, а не ноль: старый архив ключа не знает,
        // и подставить ему нуль значило бы сказать «человек выбрал 00:00
        // подъёмом», чего он не выбирал.
        dog.sexRaw = snapshot.sexRaw ?? dog.sexRaw
        dog.isNeutered = snapshot.isNeutered ?? dog.isNeutered
        dog.wakeMinuteOfDay = snapshot.wakeMinuteOfDay ?? dog.wakeMinuteOfDay
        dog.sleepMinuteOfDay = snapshot.sleepMinuteOfDay ?? dog.sleepMinuteOfDay
        dog.passportNumber = snapshot.passportNumber
        dog.chipNumber = snapshot.chipNumber
        dog.insuranceNumber = snapshot.insuranceNumber
        dog.vetName = snapshot.vetName
        dog.vetPhone = snapshot.vetPhone
        dog.clinicName = snapshot.clinicName
        dog.clinicPhone = snapshot.clinicPhone
        dog.distinctiveMarks = snapshot.distinctiveMarks
        dog.sitterFood = snapshot.sitterFood ?? dog.sitterFood
        dog.sitterDose = snapshot.sitterDose ?? dog.sitterDose
        dog.sitterWalks = snapshot.sitterWalks ?? dog.sitterWalks
        dog.sitterForbidden = snapshot.sitterForbidden ?? dog.sitterForbidden
        dog.sitterEscalation = snapshot.sitterEscalation ?? dog.sitterEscalation
        // Надгробие переносится как есть, и `?? dog.deletedAt` здесь
        // не нужен: у новой записи оно и так `nil`, а у старого архива
        // ключа нет — то есть собака из него не удалена. Оба случая
        // дают одно и то же, и лишний `??` соврал бы о наличии решения.
        dog.deletedAt = snapshot.deletedAt
        return dog
    }

    /// Долить профиль собаки, которая на телефоне уже есть:
    /// **заполнить пустое, не тронуть заполненное**.
    ///
    /// «Добавить недостающее» буквально это и значит. Затирать
    /// заполненное руками — не значит: номер чипа, врача и приметы
    /// человек мог поправить ПОСЛЕ того, как снял файл, и тогда архив
    /// здесь источник более старый, чем телефон. То же правило уже
    /// записано у справочника клиник — «слияние перезаписало телефон
    /// из архива поверх местного; правило доливки — не трогать то, что
    /// уже есть».
    ///
    /// # Чего эта функция не трогает вовсе
    ///
    /// ```
    /// weightKg · portionGrams · mealsPerDay · mealTimes   правят каждый день
    /// isOnTreatment · forbiddenFoods · rewards            правят каждый день
    /// markerKindRaw                                       правят каждый день
    /// foodBrand                                           пишется из запаса корма
    /// createdAt                                           факт о ЗАПИСИ, не о собаке
    /// deletedAt                                           надгробие чужого телефона
    /// ```
    ///
    /// Первые восемь — то, что человек меняет на экранах: вес меряют
    /// на весах, порцию двигают в режиме питания, лакомства переписывают
    /// после занятия. У них «пусто» и «ноль» неразличимы по типу, а
    /// значит подстановка из вчерашнего файла молча откатила бы
    /// сегодняшнюю правку. Пустыми они бывают у НОВОЙ собаки — а новая
    /// идёт другой веткой, через `makeDog`, где снимок переносится
    /// целиком.
    ///
    /// `deletedAt` отдельной строкой: привези его сюда — и файл
    /// с телефона, где собаку удалили, похоронил бы живую карточку
    /// вместе со всей историей. Надгробие ставит человек у себя,
    /// а не файл за него.
    @MainActor
    private static func дополнитьПрофиль(_ snapshot: BackupArchive.DogSnapshot, у dog: Dog) {
        // Девять необязательных строк: порода, три номера, врач
        // и клиника с телефонами, приметы. Списком, а не девятью `if`
        // подряд: одинаковое правило, записанное девять раз, расходится
        // на десятом.
        let строки: [(ReferenceWritableKeyPath<Dog, String?>, String?)] = [
            (\.breed, snapshot.breed),
            (\.chipNumber, snapshot.chipNumber),
            (\.passportNumber, snapshot.passportNumber),
            (\.insuranceNumber, snapshot.insuranceNumber),
            (\.vetName, snapshot.vetName),
            (\.vetPhone, snapshot.vetPhone),
            (\.clinicName, snapshot.clinicName),
            (\.clinicPhone, snapshot.clinicPhone),
            (\.distinctiveMarks, snapshot.distinctiveMarks),
        ]
        for (поле, изФайла) in строки {
            // Пустая строка — такая же пустота, как `nil`: человек,
            // стерший поле, оставляет в нём `""`, и для него это то же
            // самое «не заполнено».
            guard Fmt.notBlank(dog[keyPath: поле] ?? "") == nil,
                  let новое = Fmt.notBlank(изФайла ?? "") else { continue }
            dog[keyPath: поле] = новое
        }

        // Пять строк листа ситтера — то же правило, другой тип:
        // опциональности у них в модели нет, пусто значит `""`.
        let листСиттера: [(ReferenceWritableKeyPath<Dog, String>, String?)] = [
            (\.sitterFood, snapshot.sitterFood),
            (\.sitterDose, snapshot.sitterDose),
            (\.sitterWalks, snapshot.sitterWalks),
            (\.sitterForbidden, snapshot.sitterForbidden),
            (\.sitterEscalation, snapshot.sitterEscalation),
        ]
        for (поле, изФайла) in листСиттера {
            guard Fmt.notBlank(dog[keyPath: поле]) == nil,
                  let новое = Fmt.notBlank(изФайла ?? "") else { continue }
            dog[keyPath: поле] = новое
        }

        if dog.birthDate == nil { dog.birthDate = snapshot.birthDate }
        if dog.targetWeightLow == nil { dog.targetWeightLow = snapshot.targetWeightLow }
        if dog.targetWeightHigh == nil { dog.targetWeightHigh = snapshot.targetWeightHigh }

        // Норма еды — единственное настоящее число про количество
        // (`Dog.dailyNormGrams`), и у собак, заведённых до той правки,
        // оно пустое.
        //
        // `setDailyGrams` заодно пересчитывает `portionGrams`, и это
        // не правка «поля, которое трогают каждый день»: модель говорит
        // прямо, что правильное значение порции всегда `servingGrams`
        // и пишет его именно `setDailyGrams`. Порция здесь зеркало,
        // а оставленное старым зеркало — это та самая пара
        // несходящихся чисел на карточке, из-за которой норма и стала
        // единственной.
        if dog.dailyNormGrams == nil, let норма = snapshot.dailyNormGrams, норма > 0 {
            dog.setDailyGrams(норма)
        }

        // Пол: пусто — это `unknown`, а не отсутствие значения.
        // От пола зависит календарь течки, то есть видит ли человек
        // цикл вообще.
        if (DogSex(rawValue: dog.sexRaw) ?? .unknown) == .unknown,
           let изФайла = snapshot.sexRaw,
           (DogSex(rawValue: изФайла) ?? .unknown) != .unknown {
            dog.sexRaw = изФайла
        }

        // **У `Bool` пустоты нет, и это названная граница, а не выбор.**
        // `isNeutered` в модели не опционален, значит «не кастрирован»
        // и «не сказано» — одно состояние, и различить их нечем.
        // Без вранья здесь можно ровно одно: поднять флаг, когда файл
        // говорит «да», а на телефоне стоит умолчание. Снимать флаг
        // по файлу нельзя — это было бы утверждение за человека,
        // а `nil` в снимке (старый файл ключа не знает) значит «файл
        // не в курсе», и тогда не трогаем ничего.
        if dog.isNeutered == false, snapshot.isNeutered == true {
            dog.isNeutered = true
        }

        // Режим дня. Умолчания берутся у самой модели, а не копией
        // числа: поменяй кто-нибудь подъём в `Dog`, и копия здесь стала
        // бы молча считать непустое пустым.
        //
        // Граница названа: отличить «человек выбрал семь утра»
        // от «никто не трогал» нечем — у часа подъёма нет пустого
        // состояния, как и у `isNeutered`. Поэтому час из файла
        // подставляется только там, где на телефоне стоит ровно
        // умолчание.
        let умолчание = Dog(name: "", weightKg: 0)
        if dog.wakeMinuteOfDay == умолчание.wakeMinuteOfDay,
           let изФайла = snapshot.wakeMinuteOfDay {
            dog.wakeMinuteOfDay = изФайла
        }
        if dog.sleepMinuteOfDay == умолчание.sleepMinuteOfDay,
           let изФайла = snapshot.sleepMinuteOfDay {
            dog.sleepMinuteOfDay = изФайла
        }

        // Фото. Пусто — подложки нет вовсе, и тогда она едет из файла;
        // непустое не трогаем, человек мог переснять.
        //
        // `BackgroundStore` здесь по той же причине, что в ветке новой
        // собаки: он живёт в App Group, базу не читает, и байты ему
        // отдают у точки записи. Без этой строки человек получил бы
        // живое `Dog.photo` и чёрные вкладки.
        if dog.photo == nil, let фото = snapshot.photo {
            dog.photo = фото
            BackgroundStore.shared.запомнитьФотоСобаки(фото)
        }
    }

    @MainActor
    private static func attachEvents(
        _ snapshots: [BackupArchive.EventSnapshot],
        to dog: Dog,
        skipping existing: Set<UUID>,
        context: ModelContext
    ) -> Int {
        var count = 0
        for snapshot in snapshots where !existing.contains(snapshot.id) {
            let event = LogEvent(kind: LogKind(rawValue: snapshot.kindRaw) ?? .note,
                                 date: snapshot.date, authorName: snapshot.authorName)
            event.id = snapshot.id
            event.isSynced = snapshot.isSynced
            event.note = snapshot.note
            event.outcomeRaw = snapshot.outcomeRaw
            event.askSignalRaw = snapshot.askSignalRaw
            event.durationSeconds = snapshot.durationSeconds
            event.stoolFormRaw = snapshot.stoolFormRaw
            event.stoolFlagsRaw = snapshot.stoolFlagsRaw
            event.grams = snapshot.grams
            event.milliliters = snapshot.milliliters
            event.fromPortion = snapshot.fromPortion
            event.incidentKindRaw = snapshot.incidentKindRaw
            event.incidentDetailRaw = snapshot.incidentDetailRaw
            event.toldFamily = snapshot.toldFamily
            event.deletedAt = snapshot.deletedAt
            event.deletedBy = snapshot.deletedBy
            // «Часа не помню» — оговорка, без которой число лжёт:
            // `WalkRhythm` отбрасывает такие записи, считая обычное
            // время выхода, и восстановленная без флага запись
            // попадёт в счёт как точная.
            event.isDayOnly = snapshot.isDayOnly ?? event.isDayOnly
            event.enteredAt = snapshot.enteredAt ?? event.enteredAt
            event.editedBy = snapshot.editedBy
            event.originRaw = snapshot.originRaw
            event.reactionTriggerRaw = snapshot.reactionTriggerRaw
            event.reactionDistanceRaw = snapshot.reactionDistanceRaw
            event.walkEventID = snapshot.walkEventID
            event.careTaskID = snapshot.careTaskID
            event.medicationID = snapshot.medicationID
            event.trainingSessionID = snapshot.trainingSessionID
            event.dog = dog
            context.insert(event)
            count += 1
        }
        return count
    }

    /// Естественный ключ: части, склеенные знаком, которого в тексте
    /// не бывает.
    ///
    /// Разделитель — `U+001F` (unit separator), а не дефис и не точка:
    /// печатный знак склеивает и РАЗНЫЕ пары («Когти-21» + «» и «Когти»
    /// + «21» дают одну строку), а ключ, который иногда совпадает
    /// у разных записей, — это молчаливый пропуск при доливке, то есть
    /// потеря данных там, где человек просил их добавить.
    private static func ключ(_ части: String...) -> String {
        части.joined(separator: "\u{1F}")
    }

    /// Дата в ключе — **целыми секундами вниз**, а не сырым `Double`.
    ///
    /// Замер, а не осторожность: `JSONEncoder` с
    /// `dateEncodingStrategy = .iso8601` печатает дату без долей секунды
    /// и доли ОТБРАСЫВАЕТ — `1790000000.7` уезжает в файл как
    /// `2026-09-21T14:13:20Z` и возвращается `1790000000.0`. Значит
    /// сравнение сырых `Double` у записи из хранилища (её дату поставил
    /// `Date()`, с долями) и у неё же из файла не совпадёт НИКОГДА,
    /// и первое же «Добавить недостающее» поверх своего же дневника
    /// завело бы второй экземпляр каждой записи.
    ///
    /// Вниз (`.rounded(.down)`), а не к ближайшему: округление
    /// к ближайшему подняло бы `…000,7` до `…001`, а файл несёт
    /// `…000` — ровно то расхождение, которое здесь и чинится.
    ///
    /// Пустая дата даёт пустую часть ключа: «не сказано» — тоже
    /// значение, и две записи без даты мы не различаем ничем.
    private static func секунды(_ дата: Date?) -> String {
        guard let дата else { return "" }
        return String(Int(дата.timeIntervalSince1970.rounded(.down)))
    }

    /// Вес в ключе — целыми граммами.
    ///
    /// По той же причине, что дата секундами: `4.1` после круга через
    /// JSON сравнимо, а `4.1 * 3` — уже нет, и сравнивать килограммы
    /// оператором `==` значит однажды не узнать своё же взвешивание.
    private static func граммы(_ кг: Double) -> String {
        String(Int((кг * 1000).rounded()))
    }

    /// Новая схема лечения из снимка.
    ///
    /// Вынесена из `attachRest` 29.10.2026, когда у той появилась
    /// развилка «схема уже есть — доливаем в неё только дозы». Тело
    /// не тронуто ни строкой: тридцать полей с разбором, почему каждое
    /// едет, стоят того, чтобы их переносили целиком, а не набирали
    /// заново.
    @MainActor
    private static func makeMedication(
        _ medicationSnapshot: BackupArchive.MedicationSnapshot
    ) -> Medication {
        let medication = Medication(name: medicationSnapshot.name,
                                    doseText: medicationSnapshot.doseText,
                                    times: medicationSnapshot.times,
                                    fastingMinutes: medicationSnapshot.fastingMinutes)
        medication.fastingBeforeMinutes = medicationSnapshot.fastingBeforeMinutes ?? 0
        medication.isPaused = medicationSnapshot.isPaused
        medication.prescriber = medicationSnapshot.prescriber
        medication.cancelledAt = medicationSnapshot.cancelledAt
        medication.cancelledNote = medicationSnapshot.cancelledNote
        // Дата начала схемы. **Дыра, открывшаяся при сведении двух
        // линий 29.10.2026, а не чья-то забывчивость:** поле завела
        // облачная сессия (V9), а работа по доливке архива шла
        // параллельно и вынесла создание схемы в эту функцию. Каждая
        // правка была полной у себя, а вместе они дали восстановление,
        // которое теряло дату начала курса.
        //
        // > **Две полные половины дают неполное целое, если их не свести
        // > замером.** Поймано сверкой `makeMedication` с полями
        // > снимка, а не прогоном: тест на это нашёлся бы, только если
        // > кто-то сравнивал список полей, — и такой сторож есть
        // > (`ArchiveParityTests`), поэтому дыра прожила минуты.
        //
        // Старый архив без даты её не стирает: `?? medication.startedAt`
        // — та же идиома, что у единицы дозы ниже.
        medication.startedAt = medicationSnapshot.startedAt ?? medication.startedAt
        // Единица дозы — первая из тринадцати: без неё «0,5»
        // не значит ничего, а ошибка здесь не путаница в дневнике,
        // а передозировка.
        medication.unitRaw = medicationSnapshot.unitRaw ?? medication.unitRaw
        // Сила единицы — то, от чего считается доза. Про единицу
        // строкой выше подумали отдельно, про массу нет, и она
        // не ехала вовсе: `Backup` 0 · `BackupArchive` 0. Сама
        // запись при этом выглядела полной — `doseText` и единица
        // ездили, — поэтому потерю не замечал никто.
        //
        // **ПРАВЛЮ СВОЙ ЖЕ ДОВОД, он был неверен.** Здесь стояло:
        // «`??` не косметика: `nil` из старого снимка не должен
        // затирать массу, введённую человеком после восстановления».
        // Такого сценария на этом пути НЕ БЫВАЕТ: `Medication(…)`
        // строкой выше рождает запись заново (конструктор в файле
        // один), `init` массы не ставит — значит слева всегда `nil`,
        // и `?? medication.massPerUnitMcg` это `?? nil`.
        //
        // > Механизм безвреден, а объяснение рядом с ним неверно —
        // > и это хуже, чем отсутствие объяснения: по нему чуть
        // > не написали тест на поведение, которого не бывает.
        // > Он прошёл бы ПУСТО, и защиту считали бы проверенной.
        //
        // **И ВТОРАЯ ПОПРАВКА, она сужает первую.** Я написал «верно
        // для всех девяти» — слишком широко; замер `a5` и `23`:
        // `??` подставляет **умолчание инициализатора**, и у соседей
        // (`unitRaw`, `fastingBeforeMinutes`, `minutesAfterMeal`)
        // умолчание НЕ `nil`, там приём осмыслен. Пуст он ровно там,
        // где умолчание `nil`, — здесь.
        //
        // > **Приём перенесён с необязательного поля на
        // > необязательное, у которого нет значения по умолчанию.**
        // > Четыре соседние строки по виду одинаковы, и одна
        // > не делает ничего.
        //
        // Третий замер `a5` говорил сильнее остальных: «`attachRest`
        // зовётся из одного места и всегда на НОВОЙ собаке; при
        // `.merge` на существующей собаке он не зовётся вовсе. То есть
        // лекарства в существующую собаку не сливаются ни одним путём».
        //
        // > **Это было описание ДЕФЕКТА, прочитанное как описание
        // > устройства.** Одна и та же строка служила доводом в пользу
        // > `??` и называла потерю всей медчасти при «Добавить
        // > недостающее» — и три недели читалась как первое.
        //
        // С 29.10.2026 ветка `.merge` зовёт `attachRest`, и лекарства
        // в существующую собаку доливаются. Довод про `??` от этого
        // не изменился: запись рождается заново здесь же, слева
        // по-прежнему всегда `nil`.
        //
        // `??` оставлен: он идиома этой функции, и выламывать одну
        // строку из четырёх одинаковых значит завести четвёртую
        // форму там, где три работают. Чинится строка, не код.
        //
        // Настоящий непроверенный случай другой, и он за кругом:
        // снимок БЕЗ массы (нынешние архивы Виктории и мамы) обязан
        // дать `massPerUnitMcg == nil` и `dailyMassMcg == nil` —
        // чтобы график честно не рисовал столбик, а не рисовал ноль.
        medication.massPerUnitMcg = medicationSnapshot.massPerUnitMcg
            ?? medication.massPerUnitMcg
        medication.minutesAfterMeal = medicationSnapshot.minutesAfterMeal
            ?? medication.minutesAfterMeal
        // `dependsOnMeal` — вычисляемое (get-only): оно выводится
        // из `minutesAfterMeal`, и восстанавливать его отдельно
        // нечего. В снимок положено нарочно: для ветеринара это
        // ответ на вопрос «до еды или после», и прочитать его
        // из файла глазами важнее, чем вывести.
        medication.doseSlotsData = medicationSnapshot.doseSlots
            ?? medication.doseSlotsData
        medication.courseEnd = medicationSnapshot.courseEnd
        medication.expiry = medicationSnapshot.expiry
        medication.openedAt = medicationSnapshot.openedAt
        medication.shelfAfterOpenDays = medicationSnapshot.shelfAfterOpenDays
            ?? medication.shelfAfterOpenDays
        medication.remindBeforeExpiry = medicationSnapshot.remindBeforeExpiry
            ?? medication.remindBeforeExpiry
        medication.stockLeft = medicationSnapshot.stockLeft ?? medication.stockLeft
        medication.stockTotal = medicationSnapshot.stockTotal ?? medication.stockTotal
        medication.stockLeftAmount = medicationSnapshot.stockLeftAmount
        medication.packAmount = medicationSnapshot.packAmount
        medication.canGiveOutside = medicationSnapshot.canGiveOutside
            ?? medication.canGiveOutside
        medication.prescriptionNumber = medicationSnapshot.prescriptionNumber
        return medication
    }

    /// Долить к собаке всё, кроме ленты, и вернуть, сколько записей
    /// легло в хранилище.
    ///
    /// # Возврат — не удобство, а счётчик на экране
    ///
    /// До 29.10.2026 функция не возвращала ничего, и «Добавлено новых
    /// записей: N» считало одну ленту. Собака, приехавшая со 140
    /// анализами, давала число отметок дневника — строка не лгала
    /// и **умалчивала ровно о том, ради чего файл собран**. Тот же
    /// класс, что был у подписи диалога перед «Заменить всё».
    ///
    /// # Пропуск — по ЕСТЕСТВЕННЫМ ключам, потому что `id` в снимке нет
    ///
    /// `id` несёт один снимок из пятнадцати — `EventSnapshot`, и по нему
    /// работает дедупликация ленты (`attachEvents`). У остальных его нет
    /// нарочно: «после восстановления это ДРУГАЯ запись в другом
    /// хранилище» (`ArchiveParityTests`). Значит опознать «та же запись»
    /// можно только тем, чем её опознаёт человек, — содержанием:
    ///
    /// ```
    /// вес             дата + килограммы
    /// дело ухода      название
    /// схема лечения   название + номер назначения
    /// доза            время приёма ВНУТРИ своей схемы
    /// анализ          дата забора + показатель + номер отчёта
    /// визит           дата + клиника
    /// диагноз         формулировка + дата постановки
    /// рецепт          номер + название лекарства
    /// документ        название + дата на бумаге
    /// запас корма     вид + марка + вес упаковки
    /// течка           дата начала
    /// выезд           дата начала
    /// шаг обучения    команда + номер в лестнице
    /// занятие         время начала
    /// поездка         куда + день отъезда
    /// ```
    ///
    /// Каждый ключ собирается строкой над своим циклом, а не общим
    /// блоком в начале: правят их по одному, и ключ, уехавший от своего
    /// цикла, расходится с ним молча.
    ///
    /// # Ключи берутся у САМОЙ СОБАКИ, а не параметром
    ///
    /// Так их невозможно передать чужими. У новой собаки коллекции
    /// пусты, пропускать нечего — то есть «заменить» и «новая собака»
    /// ведут себя ровно как прежде, и условия на стратегию здесь нет
    /// ни одного.
    ///
    /// # Надгробие считается «запись уже есть»
    ///
    /// Ключи читаются с `*Storage`, а не с обёрток `dog.careTasks`
    /// и соседей, отсеивающих надгробия. Иначе запись, удалённая
    /// на этом телефоне и лежащая в файле живой, ОЖИЛА бы при доливке —
    /// тот же класс, что чинили у документов 28.10.2026, только другой
    /// дорогой. Человек убрал бумагу; долив файла её не возвращает.
    ///
    /// # Чего этот пропуск не делает
    ///
    /// Повторов ВНУТРИ одного файла он не схлопывает: ключи сняты
    /// до вставки и по ходу не пополняются. Два одинаковых взвешивания
    /// в файле — это два взвешивания в хранилище источника, и первый
    /// долив воспроизводит оба. Второй долив того же файла не добавит
    /// уже ничего: ключ в наборе есть.
    @MainActor
    @discardableResult
    private static func attachRest(
        _ snapshot: BackupArchive.DogSnapshot,
        to dog: Dog,
        clinics: [String: Clinic],
        context: ModelContext
    ) -> Int {
        var добавлено = 0

        // Вес — `дата + килограммы`. Два взвешивания в один день бывают
        // (дома утром и у врача днём), поэтому одной даты мало; вес без
        // даты — тем более не ключ.
        let естьВеса = Set((dog.weightsStorage ?? [])
            .map { ключ(секунды($0.date), граммы($0.kg)) })
        for weight in snapshot.weights
        where !естьВеса.contains(ключ(секунды(weight.date), граммы(weight.kg))) {
            let entry = WeightEntry(date: weight.date, kg: weight.kg)
            entry.dog = dog
            context.insert(entry)
            добавлено += 1
        }
        // Дело ухода — по НАЗВАНИЮ. Интервал, последняя дата и серия
        // в ключ не входят нарочно: «Когти» каждые 21 день и «Когти»
        // каждые 30 — это одно дело, которому поменяли срок. Войди срок
        // в ключ, доливка завела бы второе «Когти», и человек получил бы
        // два напоминания об одном.
        let естьДела = Set((dog.careTasksStorage ?? []).map(\.title))
        for care in snapshot.careTasks where !естьДела.contains(care.title) {
            let task = CareTask(title: care.title, detail: care.detail,
                                intervalDays: care.intervalDays,
                                category: CareCategory(rawValue: care.categoryRaw) ?? .grooming,
                                lastDone: care.lastDone)
            task.seasonStartMonth = care.seasonStartMonth
            task.seasonEndMonth = care.seasonEndMonth
            task.snoozeCount = care.snoozeCount
            // `scheduledDate` — дата прививки; без неё медкнижка
            // превращается в «каждые 365 дней от неизвестного дня».
            task.kindRaw = care.kindRaw ?? task.kindRaw
            task.scheduledDate = care.scheduledDate
            task.remindDaysBefore = care.remindDaysBefore ?? task.remindDaysBefore
            task.streak = care.streak ?? task.streak
            // Номер партии и «годна до» — шаг 0, 07.10.2026. Их
            // спрашивает врач, и спрашивает у того, кто привёл собаку.
            task.vaccineBatch = care.vaccineBatch
            task.vaccineValidUntil = care.vaccineValidUntil
            // Клиника связывается ПО ИМЕНИ из уже вставленного
            // справочника. Промах по имени оставляет связь пустой
            // и клинику не заводит: справочник без дублей — правило
            // дизайна, а запись, рождённая промахом, была бы дублем,
            // отличающимся опечаткой.
            if let имя = Fmt.notBlank(care.clinicName ?? "") {
                task.clinic = clinics[имя]
            }
            task.dog = dog
            context.insert(task)
            добавлено += 1
        }
        // Схема лечения — `название + номер назначения`. Номер в ключе
        // потому, что одно лекарство выписывают дважды разными курсами
        // («Lévothyrox» по рецепту 2026/0417 и по 2026/0881 — две схемы
        // с разными дозами), и без номера вторая молча не приехала бы.
        // Пустой номер участвует в ключе пустым: две схемы без номера
        // и с одним названием мы не различаем ничем, и доливка честно
        // считает их одной.
        var схемыПоКлючу: [String: Medication] = [:]
        for схема in dog.medicationsStorage ?? [] {
            схемыПоКлючу[ключ(схема.name, схема.prescriptionNumber ?? "")] = схема
        }
        for medicationSnapshot in snapshot.medications {
            let ключСхемы = ключ(medicationSnapshot.name,
                                 medicationSnapshot.prescriptionNumber ?? "")
            // Схемы ещё нет — заводим; есть — доливаем в неё одни дозы.
            // Второе и есть то, ради чего развилка: пропустить схему
            // целиком значило бы не привезти приёмы, которых на этом
            // телефоне не было.
            //
            // Заведённая здесь схема в набор НЕ дописывается, и это
            // та же оговорка, что у остальных четырнадцати коллекций:
            // набор отвечает про то, что лежало на телефоне ДО долива.
            // Две одинаковые схемы в одном файле — это две схемы
            // в хранилище источника, и схлопывать их за человека мы
            // не беремся; повторный долив того же файла их всё равно
            // не задвоит — ключ к тому времени в наборе есть.
            let medication: Medication
            if let существующая = схемыПоКлючу[ключСхемы] {
                medication = существующая
            } else {
                medication = makeMedication(medicationSnapshot)
                medication.dog = dog
                context.insert(medication)
                добавлено += 1
            }
            // Доза — время приёма ВНУТРИ своей схемы, а не глобально:
            // в семь утра дают и левотироксин, и преднизолон, и это две
            // разные дозы. Ключи снимаются у той схемы, в которую
            // доливаем, — в том числе у только что заведённой, где их
            // нет ни одного.
            let естьДозы = Set((medication.dosesStorage ?? [])
                .map { секунды($0.scheduledAt) })
            for doseSnapshot in medicationSnapshot.doses
            where !естьДозы.contains(секунды(doseSnapshot.scheduledAt)) {
                // **`DoseRecord.устойчивыйID` здесь НЕ применяется, и это
                // не недосмотр.** Он выводит id из `medication.id`,
                // а `MedicationSnapshot` id схемы не несёт (см. ниже) —
                // при восстановлении схема получает свежий `UUID()`.
                // Значит выведенный id был бы функцией случайной
                // величины: у двух телефонов, восстановивших ОДИН
                // архив независимо, отметки всё равно разойдутся.
                //
                // Пока `MedicationSnapshot` не несёт устойчивый id схемы,
                // независимое восстановление одного архива на двух
                // телефонах даёт по две отметки на приём — тот же дефект,
                // что чинит `устойчивыйID`, второй дорогой.
                //
                // Цена ниже, чем кажется: обычный путь — восстановили
                // у одного, записи уехали обменом со своими id. Дефект
                // достаётся только тем, кто восстановил архив ОБА.
                let dose = DoseRecord(scheduledAt: doseSnapshot.scheduledAt)
                dose.givenAt = doseSnapshot.givenAt
                dose.givenBy = doseSnapshot.givenBy
                dose.cancelledAt = doseSnapshot.cancelledAt
                dose.cancelReason = doseSnapshot.cancelReason
                // Пропущенная доза — факт, а не его отсутствие: врач
                // спрашивает «сколько раз пропустили», и архив отвечал
                // «ни разу» вместо правды.
                dose.skippedAt = doseSnapshot.skippedAt
                dose.skippedBy = doseSnapshot.skippedBy
                // Чего доза ждёт, если схема до неё не доехала.
                // Едет только имя: `awaitedMedicationID` в архив
                // не идёт нарочно — `Medication.id` тоже не идёт,
                // и восстановленная ссылка указывала бы в никуда,
                // выглядя при этом валидным UUID.
                dose.awaitedMedicationName = doseSnapshot.awaitedMedicationName
                dose.claimedBy = doseSnapshot.claimedBy
                dose.claimedAt = doseSnapshot.claimedAt
                dose.medication = medication
                context.insert(dose)
                добавлено += 1
            }
        }
        // Шаг обучения — `команда + номер в лестнице`. Команда одна
        // («место»), а шагов у неё десяток, и отличает их порядок:
        // место на кухне → место при госте → место в двух метрах.
        // Расстояние и человек в ключ не идут: их правят, доводя тот же
        // шаг, и войди они в ключ — правка завела бы дубль.
        let естьШаги = Set((dog.trainingStepsStorage ?? [])
            .map { ключ($0.cue, String($0.order)) })
        for stepSnapshot in snapshot.trainingSteps
        where !естьШаги.contains(ключ(stepSnapshot.cue, String(stepSnapshot.order))) {
            let step = TrainingStep(cue: stepSnapshot.cue, place: stepSnapshot.place,
                                    person: stepSnapshot.person,
                                    distanceMeters: stepSnapshot.distanceMeters,
                                    order: stepSnapshot.order)
            step.statusRaw = stepSnapshot.statusRaw
            step.consecutiveGoodSessions = stepSnapshot.consecutiveGoodSessions
            step.dog = dog
            context.insert(step)
            добавлено += 1
        }
        // Занятие — по ВРЕМЕНИ НАЧАЛА. Двух занятий, начатых в одну
        // секунду, не бывает: таймер запускают руками. Команда и место
        // различают занятия слабее, чем секунда, и в ключе не нужны.
        let естьЗанятия = Set((dog.trainingSessionsStorage ?? [])
            .map { секунды($0.startedAt) })
        for sessionSnapshot in snapshot.trainingSessions
        where !естьЗанятия.contains(секунды(sessionSnapshot.startedAt)) {
            let session = TrainingSession(cue: sessionSnapshot.cue, place: sessionSnapshot.place,
                                          person: sessionSnapshot.person,
                                          distanceMeters: sessionSnapshot.distanceMeters)
            session.startedAt = sessionSnapshot.startedAt
            session.durationSeconds = sessionSnapshot.durationSeconds
            session.markDelaysMs = sessionSnapshot.markDelaysMs
            session.successes = sessionSnapshot.successes
            session.attempts = sessionSnapshot.attempts
            session.gramsUsed = sessionSnapshot.gramsUsed
            session.observationsRaw = sessionSnapshot.observationsRaw
            session.countsTowardProgress = sessionSnapshot.countsTowardProgress
            session.dog = dog
            context.insert(session)
            добавлено += 1
        }
        // Запас корма — `вид + марка + вес упаковки`. Упаковка в ключе
        // потому, что «Acana» мешком 3 кг и «Acana» паучем 100 г лежат
        // в доме одновременно и расходуются по-разному. Остаток
        // упаковок и дата пересчёта в ключ не идут: это и есть то, что
        // меняется каждый день, — войди они в ключ, доливка заводила бы
        // новый запас на каждое изменение остатка.
        let естьЗапасы = Set((dog.stocksStorage ?? [])
            .map { ключ($0.kindRaw, $0.brand, String($0.packGrams)) })
        for stockSnapshot in snapshot.stocks ?? []
        where !естьЗапасы.contains(ключ(stockSnapshot.kindRaw, stockSnapshot.brand,
                                        String(stockSnapshot.packGrams))) {
            let stock = FoodStock(kind: FoodKind(rawValue: stockSnapshot.kindRaw) ?? .dry,
                                  brand: stockSnapshot.brand,
                                  packGrams: stockSnapshot.packGrams,
                                  packsLeft: stockSnapshot.packsLeft,
                                  gramsPerDay: stockSnapshot.gramsPerDay)
            stock.openedAt = stockSnapshot.openedAt
            stock.expiry = stockSnapshot.expiry
            stock.shelfAfterOpenDays = stockSnapshot.shelfAfterOpenDays
                ?? stock.shelfAfterOpenDays
            // Дата пересчёта: от неё `usedGrams` отсчитывает съеденное.
            // Без неё `usedGrams` отдаёт ноль, и восстановленный запас
            // показывает полный мешок вместо «кончается завтра».
            // Откат — на `init`, то есть «пересчитан сейчас»: у файлов,
            // снятых до 07.10.2026, этого поля нет, и соврать «пересчитан
            // год назад» нельзя.
            stock.countedAt = stockSnapshot.countedAt ?? stock.countedAt
            stock.dog = dog
            context.insert(stock)
            добавлено += 1
        }
        // Течка — по ДАТЕ НАЧАЛА. Двух течек, начавшихся в один день,
        // не бывает, а конец и заметку человек дописывает потом — течка
        // идёт две недели. Войди `endedAt` в ключ, и доливка завела бы
        // вторую течку поверх той же самой, как только первую закрыли.
        let естьТечки = Set((dog.heatsStorage ?? []).map { секунды($0.startedAt) })
        for heatSnapshot in snapshot.heats ?? []
        where !естьТечки.contains(секунды(heatSnapshot.startedAt)) {
            let heat = HeatRecord(startedAt: heatSnapshot.startedAt,
                                  endedAt: heatSnapshot.endedAt,
                                  note: heatSnapshot.note)
            heat.dog = dog
            context.insert(heat)
            добавлено += 1
        }
        // Выезд — по ДАТЕ НАЧАЛА, и по той же причине, что течка:
        // конец дописывают, когда вернулись, а `plannedHours` правят
        // на ходу.
        let естьВыезды = Set((dog.daysOutStorage ?? []).map { секунды($0.startedAt) })
        for dayOutSnapshot in snapshot.daysOut ?? []
        where !естьВыезды.contains(секунды(dayOutSnapshot.startedAt)) {
            let выезд = DayOut(startedAt: dayOutSnapshot.startedAt,
                               plannedHours: dayOutSnapshot.plannedHours)
            выезд.endedAt = dayOutSnapshot.endedAt
            выезд.note = dayOutSnapshot.note
            выезд.dog = dog
            context.insert(выезд)
            добавлено += 1
        }
        // Документ — `название + дата НА БУМАГЕ`. Дата именно
        // `occurredOn`, а не `addedAt`: один бланк, снятый дважды, —
        // один документ, и ключ обязан это видеть. Пустая `occurredOn`
        // участвует пустой: «дата не сказана» — тоже значение, и два
        // паспорта без даты мы не различаем ничем.
        let естьДокументы = Set((dog.documentsStorage ?? [])
            .map { ключ($0.title, секунды($0.occurredOn)) })
        for documentSnapshot in snapshot.documents ?? []
        where !естьДокументы.contains(ключ(documentSnapshot.title,
                                           секунды(documentSnapshot.occurredOn))) {
            let document = DogDocument(title: documentSnapshot.title,
                                       image: documentSnapshot.image,
                                       note: documentSnapshot.note)
            document.addedAt = documentSnapshot.addedAt
            // Четыре поля шага 0: тип, номер, кем выдан, срок. Срок —
            // то, из-за чего шаг 0 и начался: истёкшую прививку нельзя
            // было назвать, потому что поля не существовало.
            document.kindRaw = documentSnapshot.kindRaw ?? document.kindRaw
            document.number = documentSnapshot.number
            document.issuedBy = documentSnapshot.issuedBy
            document.validUntil = documentSnapshot.validUntil
            // Три поля шага 1, 28.10.2026. `occurredOn` — дата
            // на бумаге; `addedAt` выше отвечает про телефон, и путать
            // их нельзя: искать человек будет по первой.
            //
            // Подставлять `addedAt` при пустом `occurredOn` НЕЛЬЗЯ:
            // вышло бы, что человек сказал «анализ сдан в день съёмки».
            // Пусто — значит не сказано, и так и остаётся.
            document.occurredOn = documentSnapshot.occurredOn
            document.directionRaw = documentSnapshot.directionRaw
            // Клиника ищется по имени в уже вставленном справочнике,
            // как у дела ухода, визита и рецепта; промах оставляет связь
            // пустой и клиники не заводит.
            if let имя = Fmt.notBlank(documentSnapshot.clinicName ?? "") {
                document.clinic = clinics[имя]
            }
            // Надгробие — как у события и у собаки. Без него удалённый
            // документ ОЖИВАЛ при восстановлении: список в архив идёт
            // без фильтра надгробий, а поля в снимке не было.
            // Разбор — у `DocumentSnapshot.deletedAt`.
            document.deletedAt = documentSnapshot.deletedAt
            document.dog = dog
            context.insert(document)
            добавлено += 1
        }
        // Медкнижка — 07.10.2026. Клиника ищется по имени в уже
        // вставленном справочнике, как у дел ухода; промах оставляет
        // связь пустой и клиники не заводит.
        // Анализ — `дата забора + показатель + номер отчёта`. Все три:
        // в одном отчёте до двадцати двух показателей (биохимия), один
        // показатель сдают по многу раз, а номер отчёта в старых
        // записях бывает пуст.
        let естьАнализы = Set((dog.labResultsStorage ?? [])
            .map { ключ(секунды($0.sampledOn), $0.indicator, $0.reportNumber) })
        for снимок in snapshot.labResults ?? []
        where !естьАнализы.contains(ключ(секунды(снимок.sampledOn), снимок.indicator,
                                         снимок.reportNumber)) {
            let анализ = LabResult(sampledOn: снимок.sampledOn,
                                   indicator: снимок.indicator,
                                   section: снимок.section,
                                   laboratory: снимок.laboratory,
                                   reportNumber: снимок.reportNumber)
            анализ.sampledAt = снимок.sampledAt
            // Три поля значения — порознь. Сложить их в одно значило бы
            // превратить «<0,1» в число 0,1, то есть тихо неверное
            // значение вместо видимо неизвестного.
            анализ.value = снимок.value
            анализ.belowLimit = снимок.belowLimit
            анализ.aboveLimit = снимок.aboveLimit
            анализ.textValue = снимок.textValue
            анализ.unit = снимок.unit
            анализ.referenceLow = снимок.referenceLow
            анализ.referenceHigh = снимок.referenceHigh
            анализ.method = снимок.method
            анализ.labMark = снимок.labMark
            анализ.note = снимок.note
            анализ.dog = dog
            context.insert(анализ)
            добавлено += 1
        }
        // Визит — `дата + клиника`. Двух приёмов в одной клинике
        // в один день не бывает; в разных клиниках в один день —
        // бывает, и это два визита.
        let естьВизиты = Set((dog.vetVisitsStorage ?? [])
            .map { ключ(секунды($0.date), $0.clinic?.name ?? "") })
        for снимок in snapshot.vetVisits ?? []
        where !естьВизиты.contains(ключ(секунды(снимок.date), снимок.clinicName ?? "")) {
            let визит = VetVisit(date: снимок.date, doctor: снимок.doctor,
                                 reasonRaw: снимок.reasonRaw)
            визит.conclusion = снимок.conclusion
            if let имя = Fmt.notBlank(снимок.clinicName ?? "") {
                визит.clinic = clinics[имя]
            }
            визит.dog = dog
            context.insert(визит)
            добавлено += 1
        }
        // Диагноз — `формулировка + дата постановки`. Статус в ключ
        // не входит: снятый диагноз — тот же диагноз, которому
        // поменяли статус, и войди статус в ключ, доливка завела бы
        // второй, с прежним «подтверждён».
        let естьДиагнозы = Set((dog.diagnosesStorage ?? [])
            .map { ключ($0.wording, секунды($0.madeOn)) })
        for снимок in snapshot.diagnoses ?? []
        where !естьДиагнозы.contains(ключ(снимок.wording, секунды(снимок.madeOn))) {
            let диагноз = Diagnosis(wording: снимок.wording, madeOn: снимок.madeOn,
                                    statusRaw: снимок.statusRaw)
            диагноз.madeBy = снимок.madeBy
            диагноз.evidence = снимок.evidence
            диагноз.dog = dog
            context.insert(диагноз)
            добавлено += 1
        }
        // Рецепт — `номер + название лекарства`. Номер один на бланк,
        // а в бланке бывает несколько препаратов — у Стича такие есть.
        let естьРецепты = Set((dog.prescriptionsStorage ?? [])
            .map { ключ($0.number, $0.medicationName) })
        for снимок in snapshot.prescriptions ?? []
        where !естьРецепты.contains(ключ(снимок.number, снимок.medicationName)) {
            let рецепт = Prescription(number: снимок.number, date: снимок.date,
                                      medicationName: снимок.medicationName)
            рецепт.doctor = снимок.doctor
            рецепт.dogWeightKg = снимок.dogWeightKg
            рецепт.dosage = снимок.dosage
            рецепт.schedule = снимок.schedule
            рецепт.duration = снимок.duration
            рецепт.pharmacyForm = снимок.pharmacyForm
            рецепт.controlFromWeeks = снимок.controlFromWeeks
            рецепт.controlToWeeks = снимок.controlToWeeks
            рецепт.dispensed = снимок.dispensed
            рецепт.instruction = снимок.instruction
            рецепт.source = снимок.source
            if let имя = Fmt.notBlank(снимок.clinicName ?? "") {
                рецепт.clinic = clinics[имя]
            }
            рецепт.dog = dog
            context.insert(рецепт)
            добавлено += 1
        }
        // Поездка — `куда + день отъезда`. Двух поездок в одно место
        // в один день не бывает; возвращение и сборы правят до самого
        // выезда, и в ключ они не идут.
        let естьПоездки = Set((dog.tripsStorage ?? [])
            .map { ключ($0.destination, секунды($0.startDate)) })
        for tripSnapshot in snapshot.trips
        where !естьПоездки.contains(ключ(tripSnapshot.destination,
                                         секунды(tripSnapshot.startDate))) {
            let trip = Trip(destination: tripSnapshot.destination,
                            startDate: tripSnapshot.startDate,
                            endDate: tripSnapshot.endDate,
                            transport: TransportKind(rawValue: tripSnapshot.transportRaw) ?? .car)
            trip.travelHours = tripSnapshot.travelHours
            trip.lodging = tripSnapshot.lodging
            trip.participants = tripSnapshot.participants
            trip.departureMinuteOfDay = tripSnapshot.departureMinuteOfDay
            trip.packedItems = tripSnapshot.packedItems
            trip.dog = dog
            context.insert(trip)
            добавлено += 1
        }
        return добавлено
    }
}

/// Обёртка для системного «Поделиться».
nonisolated struct BackupFile: Transferable {
    let name: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.name)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
