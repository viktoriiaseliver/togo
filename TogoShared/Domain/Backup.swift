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
        let allStocks = (try? context.fetch(FetchDescriptor<FoodStock>())) ?? []
        let allHeats = (try? context.fetch(FetchDescriptor<HeatRecord>())) ?? []
        let allDocuments = (try? context.fetch(FetchDescriptor<DogDocument>())) ?? []
        let allDaysOut = (try? context.fetch(FetchDescriptor<DayOut>())) ?? []
        let members = try context.fetch(FetchDescriptor<FamilyMember>())
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        // Навыки процедур — корневой список: связи с собакой у них нет.
        let skills = (try? context.fetch(FetchDescriptor<ProcedureSkill>())) ?? []
        // Справочник клиник — тоже корневой и по той же причине.
        let clinics = (try? context.fetch(FetchDescriptor<Clinic>())) ?? []

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
                    prescriptionNumber: medication.prescriptionNumber
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
                                               validUntil: $0.validUntil)
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
            }
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
        /// Добавить, чего нет. Записи сверяются по идентификатору,
        /// поэтому повторный импорт того же файла ничего не задваивает.
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

    @MainActor
    @discardableResult
    static func restore(_ archive: BackupArchive, into context: ModelContext, strategy: Strategy) throws -> Int {
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
                try context.delete(model: model)
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
                // Собака уже есть — доливаем только новые записи к ней.
                if let dog = try context.fetch(FetchDescriptor<Dog>()).first(where: { $0.name == имя }) {
                    restored += attachEvents(snapshot.events, to: dog, skipping: existingEventIDs, context: context)
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
            restored += attachEvents(snapshot.events, to: dog, skipping: existingEventIDs, context: context)
            attachRest(snapshot, to: dog, clinics: клиники, context: context)
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
        return dog
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

    @MainActor
    private static func attachRest(
        _ snapshot: BackupArchive.DogSnapshot,
        to dog: Dog,
        clinics: [String: Clinic],
        context: ModelContext
    ) {
        for weight in snapshot.weights {
            let entry = WeightEntry(date: weight.date, kg: weight.kg)
            entry.dog = dog
            context.insert(entry)
        }
        for care in snapshot.careTasks {
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
        }
        for medicationSnapshot in snapshot.medications {
            let medication = Medication(name: medicationSnapshot.name,
                                        doseText: medicationSnapshot.doseText,
                                        times: medicationSnapshot.times,
                                        fastingMinutes: medicationSnapshot.fastingMinutes)
            medication.fastingBeforeMinutes = medicationSnapshot.fastingBeforeMinutes ?? 0
            medication.isPaused = medicationSnapshot.isPaused
            medication.prescriber = medicationSnapshot.prescriber
            medication.cancelledAt = medicationSnapshot.cancelledAt
            medication.cancelledNote = medicationSnapshot.cancelledNote
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
            // `??` оставлен: он идиома этой функции (так написаны
            // ДЕВЯТЬ полей подряд), и выламывать одно из девяти — значит
            // сделать его исключением без причины. Что `??` здесь
            // подставляет умолчание инициализатора, а не значение
            // человека, верно для всех девяти.
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
            medication.dog = dog
            context.insert(medication)
            for doseSnapshot in medicationSnapshot.doses {
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
            }
        }
        for stepSnapshot in snapshot.trainingSteps {
            let step = TrainingStep(cue: stepSnapshot.cue, place: stepSnapshot.place,
                                    person: stepSnapshot.person,
                                    distanceMeters: stepSnapshot.distanceMeters,
                                    order: stepSnapshot.order)
            step.statusRaw = stepSnapshot.statusRaw
            step.consecutiveGoodSessions = stepSnapshot.consecutiveGoodSessions
            step.dog = dog
            context.insert(step)
        }
        for sessionSnapshot in snapshot.trainingSessions {
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
        }
        for stockSnapshot in snapshot.stocks ?? [] {
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
        }
        for heatSnapshot in snapshot.heats ?? [] {
            let heat = HeatRecord(startedAt: heatSnapshot.startedAt,
                                  endedAt: heatSnapshot.endedAt,
                                  note: heatSnapshot.note)
            heat.dog = dog
            context.insert(heat)
        }
        for dayOutSnapshot in snapshot.daysOut ?? [] {
            let выезд = DayOut(startedAt: dayOutSnapshot.startedAt,
                               plannedHours: dayOutSnapshot.plannedHours)
            выезд.endedAt = dayOutSnapshot.endedAt
            выезд.note = dayOutSnapshot.note
            выезд.dog = dog
            context.insert(выезд)
        }
        for documentSnapshot in snapshot.documents ?? [] {
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
            document.dog = dog
            context.insert(document)
        }
        // Медкнижка — 07.10.2026. Клиника ищется по имени в уже
        // вставленном справочнике, как у дел ухода; промах оставляет
        // связь пустой и клиники не заводит.
        for снимок in snapshot.labResults ?? [] {
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
        }
        for снимок in snapshot.vetVisits ?? [] {
            let визит = VetVisit(date: снимок.date, doctor: снимок.doctor,
                                 reasonRaw: снимок.reasonRaw)
            визит.conclusion = снимок.conclusion
            if let имя = Fmt.notBlank(снимок.clinicName ?? "") {
                визит.clinic = clinics[имя]
            }
            визит.dog = dog
            context.insert(визит)
        }
        for снимок in snapshot.diagnoses ?? [] {
            let диагноз = Diagnosis(wording: снимок.wording, madeOn: снимок.madeOn,
                                    statusRaw: снимок.statusRaw)
            диагноз.madeBy = снимок.madeBy
            диагноз.evidence = снимок.evidence
            диагноз.dog = dog
            context.insert(диагноз)
        }
        for снимок in snapshot.prescriptions ?? [] {
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
        }
        for tripSnapshot in snapshot.trips {
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
        }
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
