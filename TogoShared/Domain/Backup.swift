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
                                              title: $0.title, detail: $0.detail)
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
            events: dog.events.map { event in
                BackupArchive.EventSnapshot(
                    id: event.id, date: event.date, kindRaw: event.kindRaw,
                    authorName: event.authorName, isSynced: event.isSynced, note: event.note,
                    outcomeRaw: event.outcomeRaw, askSignalRaw: event.askSignalRaw,
                    durationSeconds: event.durationSeconds, stoolFormRaw: event.stoolFormRaw,
                    stoolFlagsRaw: event.stoolFlagsRaw, grams: event.grams,
                    milliliters: event.milliliters, fromPortion: event.fromPortion,
                    incidentKindRaw: event.incidentKindRaw, incidentDetailRaw: event.incidentDetailRaw,
                    toldFamily: event.toldFamily, deletedAt: event.deletedAt, deletedBy: event.deletedBy
                )
            },
            weights: dog.weights.map { BackupArchive.WeightSnapshot(date: $0.date, kg: $0.kg) },
            careTasks: dog.careTasks.map {
                BackupArchive.CareTaskSnapshot(
                    title: $0.title, detail: $0.detail, intervalDays: $0.intervalDays,
                    lastDone: $0.lastDone, categoryRaw: $0.categoryRaw,
                    seasonStartMonth: $0.seasonStartMonth, seasonEndMonth: $0.seasonEndMonth,
                    snoozeCount: $0.snoozeCount
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
                                                   cancelReason: $0.cancelReason)
                    }
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
                                            gramsPerDay: $0.gramsPerDay, openedAt: $0.openedAt)
            },
            heats: heats.map {
                BackupArchive.HeatSnapshot(startedAt: $0.startedAt, endedAt: $0.endedAt, note: $0.note)
            },
            documents: documents.map {
                BackupArchive.DocumentSnapshot(title: $0.title, image: $0.image,
                                               addedAt: $0.addedAt, note: $0.note)
            },
            daysOut: daysOut.map {
                BackupArchive.DayOutSnapshot(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                             plannedHours: $0.plannedHours, note: $0.note)
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
            for model in [LogEvent.self, WeightEntry.self, DoseRecord.self, Medication.self,
                          CareTask.self, TrainingSession.self, TrainingStep.self,
                          Trip.self, Episode.self, FamilyMember.self, Dog.self] as [any PersistentModel.Type] {
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
            attachRest(snapshot, to: dog, context: context)
        }

        for snapshot in archive.members where !(strategy == .merge && existingMemberNames.contains(snapshot.name)) {
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
            for snapshot in archive.episodes {
                let episode = Episode(title: snapshot.title, detail: snapshot.detail, startedAt: snapshot.startedAt)
                episode.endedAt = snapshot.endedAt
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
            medication.dog = dog
            context.insert(medication)
            for doseSnapshot in medicationSnapshot.doses {
                let dose = DoseRecord(scheduledAt: doseSnapshot.scheduledAt)
                dose.givenAt = doseSnapshot.givenAt
                dose.givenBy = doseSnapshot.givenBy
                dose.cancelledAt = doseSnapshot.cancelledAt
                dose.cancelReason = doseSnapshot.cancelReason
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
            document.dog = dog
            context.insert(document)
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
