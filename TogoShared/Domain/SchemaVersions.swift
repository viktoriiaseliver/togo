import Foundation
import SwiftData

// Версии схемы хранилища и план перехода между ними.
//
// **Зачем это появилось.** До 21.09.2026 плана миграции в проекте
// не было вовсе — ни одной `VersionedSchema`. Значит любая правка
// модели встречалась с уже существующим хранилищем без единого
// правила о том, как их мирить. Это нашли измерением, а не
// рассуждением: одни и те же `BackupTests` на одном и том же
// симуляторе шли зелено без правки модели и падали с ней,
// а на стёртом начисто симуляторе с правкой — снова зелено.
// То есть падало не от фичи, а от встречи нового поля со старой базой.
//
// Опаснее самого падения то, чем оно оборачивается на телефоне:
// `Persistence.appContainer()` не роняет приложение, а откатывается
// iCloud → локально → в памяти. Человек видит работающий экран,
// отмечает дозу, получает подтверждение — и запись не сохраняется
// никуда. Тихая потеря дневника с лечением.
//
// **Почему версий три, а не две.** Схема менялась дважды, и обе
// правки уже уехали из репозитория:
//
// | Версия | Сборка | Коммит    | Что нового                       |
// |--------|--------|-----------|----------------------------------|
// | V1     | 36     | `1815b59` | — (то, что стоит у тестировщиков)|
// | V2     | 46     | `4081a47` | `LogEvent`: `enteredAt`, `originRaw`, `isDayOnly` |
// | V3     | сейчас | `de07bda` | `Medication.fastingBeforeMinutes` |
//
// Номер сборки в проекте — это число коммитов (`Makefile`, цель
// `archive`), поэтому сборка и коммит сопоставляются точно, а не
// по памяти. Сборка 36 раздаётся тестировщикам, сборка 46 лежит
// в App Store Connect и ждёт отправки на ревью. Хранилища обеих
// форм существуют, и обе обязаны быть в плане: версию, которой
// в плане нет, SwiftData не умеет опознать и открыть.
//
// **Почему копии моделей, а не ссылки на нынешние классы.** Схема
// версии — это набор её моделей. Если бы V1 перечисляла те же
// классы, что и V3, все три версии оказались бы одинаковыми, план
// стал бы пустым обещанием и по-прежнему не открывал бы ни одну
// старую базу. Поэтому здесь лежат настоящие снимки: классы в том
// виде, в каком они были в этих коммитах. Тела вычисляемых свойств
// и методов опущены намеренно — на форму хранилища они не влияют,
// а лишний код разошёлся бы с оригиналом.
//
// Снимки сняты не руками, а из git: `git show 1815b59:TogoShared/Models/*.swift`
// и `git show 4081a47:...`. Различие проверено сверкой множеств
// хранимых свойств по всем шестнадцати моделям — см. `SchemaMigrationTests`.

// MARK: - V1 · сборка 36, коммит 1815b59
//
// То, что прямо сейчас стоит у тестировщиков.

nonisolated enum TogoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, DayOut.self, Dog.self, DogDocument.self, FamilyMember.self, Episode.self, Trip.self, FoodStock.self, HeatRecord.self, LogEvent.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self]
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var fastingMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var dog: Dog?
        @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
        var dosesStorage: [DoseRecord]?

        init() {}
    }

    @Model
    final class DoseRecord {
        var id: UUID = UUID()
        var scheduledAt: Date = Date()
        var givenAt: Date?
        var givenBy: String?
        var claimedBy: String?
        var claimedAt: Date?
        var cancelledAt: Date?
        var cancelReason: String?
        var changedAt: Date = Date()
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class DayOut {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var plannedHours: Int = 4
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Dog {
        var id: UUID = UUID()
        var name: String = ""
        var photo: Data?
        var breed: String?
        var birthDate: Date?
        var sexRaw: String = DogSex.unknown.rawValue
        var isNeutered: Bool = false
        var weightKg: Double = 0
        var targetWeightLow: Double?
        var targetWeightHigh: Double?
        var foodBrand: String = ""
        var portionGrams: Int = 0
        var mealsPerDay: Int = 2
        var mealTimes: [Int] = [7 * 60 + 30, 18 * 60 + 30]
        var wakeMinuteOfDay: Int = 7 * 60
        var sleepMinuteOfDay: Int = 23 * 60
        var forbiddenFoods: [String] = []
        var dailyNormGrams: Int?
        var rewards: [String] = []
        var sitterFood: String = ""
        var sitterDose: String = ""
        var sitterWalks: String = ""
        var sitterForbidden: String = ""
        var sitterEscalation: String = ""
        var trainingFoodFromPortion: Bool = true
        var markerKindRaw: String = MarkerKind.clicker.rawValue
        var sessionLengthMinutes: Int = 3
        var isOnTreatment: Bool = false
        var chipNumber: String?
        var passportNumber: String?
        var insuranceNumber: String?
        var vetName: String?
        var vetPhone: String?
        var clinicName: String?
        var clinicPhone: String?
        var distinctiveMarks: String?
        var createdAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \LogEvent.dog)
        var eventsStorage: [LogEvent]?
        @Relationship(deleteRule: .cascade, inverse: \WeightEntry.dog)
        var weightsStorage: [WeightEntry]?
        @Relationship(deleteRule: .cascade, inverse: \CareTask.dog)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .cascade, inverse: \Medication.dog)
        var medicationsStorage: [Medication]?
        @Relationship(deleteRule: .cascade, inverse: \TrainingStep.dog)
        var trainingStepsStorage: [TrainingStep]?
        @Relationship(deleteRule: .cascade, inverse: \TrainingSession.dog)
        var trainingSessionsStorage: [TrainingSession]?
        @Relationship(deleteRule: .cascade, inverse: \Trip.dog)
        var tripsStorage: [Trip]?
        @Relationship(deleteRule: .cascade, inverse: \DogDocument.dog)
        var documentsStorage: [DogDocument]?
        @Relationship(deleteRule: .cascade, inverse: \DayOut.dog)
        var daysOutStorage: [DayOut]?
        @Relationship(deleteRule: .cascade, inverse: \HeatRecord.dog)
        var heatsStorage: [HeatRecord]?
        @Relationship(deleteRule: .cascade, inverse: \FoodStock.dog)
        var stocksStorage: [FoodStock]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage)
        var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class FamilyMember {
        var id: UUID = UUID()
        var name: String = ""
        var roleRaw: String = FamilyRole.helper.rawValue
        var note: String?
        var isMe: Bool = false
        var customPermissionsRaw: [String]?
        var isOnDuty: Bool = false
        var dutyUntil: Date?
        var inviteToken: String?
        var inviteExpiresAt: Date?
        var accessExpiresAt: Date?
        var acceptedAt: Date?

        init() {}
    }

    @Model
    final class Episode {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var lastIncidentAt: Date = Date()
        var title: String = ""
        var detail: String = ""

        init() {}
    }

    @Model
    final class Trip {
        var id: UUID = UUID()
        var destination: String = ""
        var startDate: Date = Date()
        var endDate: Date = Date()
        var transportRaw: String = TransportKind.car.rawValue
        var travelHours: Double = 0
        var lodging: String = ""
        var participants: [String] = []
        var departureMinuteOfDay: Int = 9 * 60
        var packedItems: [String] = []
        var dog: Dog?

        init() {}
    }

    @Model
    final class FoodStock {
        var id: UUID = UUID()
        var kindRaw: String = FoodKind.dry.rawValue
        var brand: String = ""
        var packGrams: Int = 3000
        var packsLeft: Double = 1
        var countedAt: Date?
        var openedAt: Date?
        var gramsPerDay: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class LogEvent {
        var id: UUID = UUID()
        var date: Date = Date()
        var kindRaw: String = LogKind.note.rawValue
        var authorName: String = ""
        var isSynced: Bool = true
        var note: String?
        var outcomeRaw: String?
        var askSignalRaw: String?
        var durationSeconds: Int?
        var stoolFormRaw: String?
        var stoolFlagsRaw: [String] = []
        var grams: Int?
        var milliliters: Int?
        var fromPortion: Bool = false
        var reactionTriggerRaw: String?
        var reactionDistanceRaw: String?
        var incidentKindRaw: String?
        var incidentDetailRaw: String?
        var toldFamily: Bool = false
        var trainingSessionID: UUID?
        var medicationID: UUID?
        var careTaskID: UUID?
        var walkEventID: UUID?
        var deletedAt: Date?
        var deletedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingStep {
        var id: UUID = UUID()
        var cue: String = ""
        var place: String = ""
        var person: String = ""
        var distanceMeters: Int = 2
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var consecutiveGoodSessions: Int = 0
        var order: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingSession {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var durationSeconds: Int = 0
        var cue: String = ""
        var place: String = ""
        var person: String = ""
        var distanceMeters: Int = 2
        var markDelaysMs: [Int] = []
        var successes: Int = 0
        var attempts: Int = 0
        var gramsUsed: Int = 0
        var observationsRaw: [String] = []
        var countsTowardProgress: Bool = true
        var dog: Dog?

        init() {}
    }

    @Model
    final class ProcedureSkill {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var targetDate: Date?
        var successes: Int = 0
        var attempts: Int = 0

        init() {}
    }

}

// MARK: - V2 · сборка 46, коммит 4081a47
//
// Отличие от V1 — три поля в `LogEvent`: запись задним числом.
// Сборка лежит в ASC; хранилище такой формы есть на машинах,
// где её ставили.

nonisolated enum TogoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, DayOut.self, Dog.self, DogDocument.self, FamilyMember.self, Episode.self, Trip.self, FoodStock.self, HeatRecord.self, LogEvent.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self]
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var fastingMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var dog: Dog?
        @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
        var dosesStorage: [DoseRecord]?

        init() {}
    }

    @Model
    final class DoseRecord {
        var id: UUID = UUID()
        var scheduledAt: Date = Date()
        var givenAt: Date?
        var givenBy: String?
        var claimedBy: String?
        var claimedAt: Date?
        var cancelledAt: Date?
        var cancelReason: String?
        var changedAt: Date = Date()
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class DayOut {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var plannedHours: Int = 4
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Dog {
        var id: UUID = UUID()
        var name: String = ""
        var photo: Data?
        var breed: String?
        var birthDate: Date?
        var sexRaw: String = DogSex.unknown.rawValue
        var isNeutered: Bool = false
        var weightKg: Double = 0
        var targetWeightLow: Double?
        var targetWeightHigh: Double?
        var foodBrand: String = ""
        var portionGrams: Int = 0
        var mealsPerDay: Int = 2
        var mealTimes: [Int] = [7 * 60 + 30, 18 * 60 + 30]
        var wakeMinuteOfDay: Int = 7 * 60
        var sleepMinuteOfDay: Int = 23 * 60
        var forbiddenFoods: [String] = []
        var dailyNormGrams: Int?
        var rewards: [String] = []
        var sitterFood: String = ""
        var sitterDose: String = ""
        var sitterWalks: String = ""
        var sitterForbidden: String = ""
        var sitterEscalation: String = ""
        var trainingFoodFromPortion: Bool = true
        var markerKindRaw: String = MarkerKind.clicker.rawValue
        var sessionLengthMinutes: Int = 3
        var isOnTreatment: Bool = false
        var chipNumber: String?
        var passportNumber: String?
        var insuranceNumber: String?
        var vetName: String?
        var vetPhone: String?
        var clinicName: String?
        var clinicPhone: String?
        var distinctiveMarks: String?
        var createdAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \LogEvent.dog)
        var eventsStorage: [LogEvent]?
        @Relationship(deleteRule: .cascade, inverse: \WeightEntry.dog)
        var weightsStorage: [WeightEntry]?
        @Relationship(deleteRule: .cascade, inverse: \CareTask.dog)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .cascade, inverse: \Medication.dog)
        var medicationsStorage: [Medication]?
        @Relationship(deleteRule: .cascade, inverse: \TrainingStep.dog)
        var trainingStepsStorage: [TrainingStep]?
        @Relationship(deleteRule: .cascade, inverse: \TrainingSession.dog)
        var trainingSessionsStorage: [TrainingSession]?
        @Relationship(deleteRule: .cascade, inverse: \Trip.dog)
        var tripsStorage: [Trip]?
        @Relationship(deleteRule: .cascade, inverse: \DogDocument.dog)
        var documentsStorage: [DogDocument]?
        @Relationship(deleteRule: .cascade, inverse: \DayOut.dog)
        var daysOutStorage: [DayOut]?
        @Relationship(deleteRule: .cascade, inverse: \HeatRecord.dog)
        var heatsStorage: [HeatRecord]?
        @Relationship(deleteRule: .cascade, inverse: \FoodStock.dog)
        var stocksStorage: [FoodStock]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage)
        var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class FamilyMember {
        var id: UUID = UUID()
        var name: String = ""
        var roleRaw: String = FamilyRole.helper.rawValue
        var note: String?
        var isMe: Bool = false
        var customPermissionsRaw: [String]?
        var isOnDuty: Bool = false
        var dutyUntil: Date?
        var inviteToken: String?
        var inviteExpiresAt: Date?
        var accessExpiresAt: Date?
        var acceptedAt: Date?

        init() {}
    }

    @Model
    final class Episode {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var lastIncidentAt: Date = Date()
        var title: String = ""
        var detail: String = ""

        init() {}
    }

    @Model
    final class Trip {
        var id: UUID = UUID()
        var destination: String = ""
        var startDate: Date = Date()
        var endDate: Date = Date()
        var transportRaw: String = TransportKind.car.rawValue
        var travelHours: Double = 0
        var lodging: String = ""
        var participants: [String] = []
        var departureMinuteOfDay: Int = 9 * 60
        var packedItems: [String] = []
        var dog: Dog?

        init() {}
    }

    @Model
    final class FoodStock {
        var id: UUID = UUID()
        var kindRaw: String = FoodKind.dry.rawValue
        var brand: String = ""
        var packGrams: Int = 3000
        var packsLeft: Double = 1
        var countedAt: Date?
        var openedAt: Date?
        var gramsPerDay: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class LogEvent {
        var id: UUID = UUID()
        var date: Date = Date()
        var kindRaw: String = LogKind.note.rawValue
        var authorName: String = ""
        var isSynced: Bool = true
        var note: String?
        var enteredAt: Date?
        var originRaw: String?
        var isDayOnly: Bool = false
        var outcomeRaw: String?
        var askSignalRaw: String?
        var durationSeconds: Int?
        var stoolFormRaw: String?
        var stoolFlagsRaw: [String] = []
        var grams: Int?
        var milliliters: Int?
        var fromPortion: Bool = false
        var reactionTriggerRaw: String?
        var reactionDistanceRaw: String?
        var incidentKindRaw: String?
        var incidentDetailRaw: String?
        var toldFamily: Bool = false
        var trainingSessionID: UUID?
        var medicationID: UUID?
        var careTaskID: UUID?
        var walkEventID: UUID?
        var deletedAt: Date?
        var deletedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingStep {
        var id: UUID = UUID()
        var cue: String = ""
        var place: String = ""
        var person: String = ""
        var distanceMeters: Int = 2
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var consecutiveGoodSessions: Int = 0
        var order: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingSession {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var durationSeconds: Int = 0
        var cue: String = ""
        var place: String = ""
        var person: String = ""
        var distanceMeters: Int = 2
        var markDelaysMs: [Int] = []
        var successes: Int = 0
        var attempts: Int = 0
        var gramsUsed: Int = 0
        var observationsRaw: [String] = []
        var countsTowardProgress: Bool = true
        var dog: Dog?

        init() {}
    }

    @Model
    final class ProcedureSkill {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var targetDate: Date?
        var successes: Int = 0
        var attempts: Int = 0

        init() {}
    }

}


// MARK: - V3 · сборка 141, коммит 18843c1
//
// Отличие от V2 — `Medication.fastingBeforeMinutes`: половина правила
// «натощак», которой в модели не было.
//
// **Почему теперь это снимок, а не ссылки на нынешние классы.** До
// 23.09.2026 V3 перечисляла настоящие классы приложения. Пока модель
// не менялась, это работало и выглядело экономно. Первая же правка —
// `Dog.changedAt` для обмена профилем — сломала не сборку, а **открытие
// хранилища**: форма классов стала другой, а версия осталась 3.0.0,
// и SwiftData ответила «Cannot use staged migration with an unknown
// model version». На телефоне это не падение, а откат iCloud → локально
// → в память: человек видит рабочий экран, отмечает дозу, получает
// подтверждение — и запись не сохраняется никуда.
//
// Сборка 141 у четверых тестировщиков. Её хранилище — вот это.
//
// Снимок снят из git (`git show HEAD:TogoShared/Models/*.swift`), а не
// руками, и сверен по множествам хранимых свойств всех шестнадцати
// моделей. Сверщик первой редакции пропустил
// `@Attribute(.externalStorage) var image` у `DogDocument` — ровно та же
// ловушка, что стоила дня деривером зеркала CloudKit: разбор,
// не видящий поля с атрибутом, молча сообщает о полноте.

nonisolated enum TogoSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, DayOut.self, Dog.self, DogDocument.self, FamilyMember.self, Episode.self, Trip.self, FoodStock.self, HeatRecord.self, LogEvent.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self]
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var dog: Dog?
    @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
        var dosesStorage: [DoseRecord]?

        init() {}
    }

    @Model
    final class DoseRecord {
        var id: UUID = UUID()
        var scheduledAt: Date = Date()
        var givenAt: Date?
        var givenBy: String?
        var claimedBy: String?
        var claimedAt: Date?
        var cancelledAt: Date?
        var cancelReason: String?
        var changedAt: Date = Date()
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class DayOut {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var plannedHours: Int = 4
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Dog {
        var id: UUID = UUID()
        var name: String = ""
        var photo: Data?
        var breed: String?
        var birthDate: Date?
        var sexRaw: String = DogSex.unknown.rawValue
        var isNeutered: Bool = false
        var weightKg: Double = 0
        var targetWeightLow: Double?
        var targetWeightHigh: Double?
        var foodBrand: String = ""
        var portionGrams: Int = 0
        var mealsPerDay: Int = 2
        var mealTimes: [Int] = [7 * 60 + 30, 18 * 60 + 30]   // минуты от полуночи
        var wakeMinuteOfDay: Int = 7 * 60
        var sleepMinuteOfDay: Int = 23 * 60
        var forbiddenFoods: [String] = []
        var dailyNormGrams: Int?
        var rewards: [String] = []
        var sitterFood: String = ""
        var sitterDose: String = ""
        var sitterWalks: String = ""
        var sitterForbidden: String = ""
        var sitterEscalation: String = ""
        var trainingFoodFromPortion: Bool = true
        var markerKindRaw: String = MarkerKind.clicker.rawValue
        var sessionLengthMinutes: Int = 3
        var isOnTreatment: Bool = false
        var chipNumber: String?
        var passportNumber: String?
        var insuranceNumber: String?
        var vetName: String?
        var vetPhone: String?
        var clinicName: String?
        var clinicPhone: String?
        var distinctiveMarks: String?
        var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \LogEvent.dog)
        var eventsStorage: [LogEvent]?
    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.dog)
        var weightsStorage: [WeightEntry]?
    @Relationship(deleteRule: .cascade, inverse: \CareTask.dog)
        var careTasksStorage: [CareTask]?
    @Relationship(deleteRule: .cascade, inverse: \Medication.dog)
        var medicationsStorage: [Medication]?
    @Relationship(deleteRule: .cascade, inverse: \TrainingStep.dog)
        var trainingStepsStorage: [TrainingStep]?
    @Relationship(deleteRule: .cascade, inverse: \TrainingSession.dog)
        var trainingSessionsStorage: [TrainingSession]?
    @Relationship(deleteRule: .cascade, inverse: \Trip.dog)
        var tripsStorage: [Trip]?
    @Relationship(deleteRule: .cascade, inverse: \DogDocument.dog)
        var documentsStorage: [DogDocument]?
    @Relationship(deleteRule: .cascade, inverse: \DayOut.dog)
        var daysOutStorage: [DayOut]?
    @Relationship(deleteRule: .cascade, inverse: \HeatRecord.dog)
        var heatsStorage: [HeatRecord]?
    @Relationship(deleteRule: .cascade, inverse: \FoodStock.dog)
        var stocksStorage: [FoodStock]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
    @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class FamilyMember {
        var id: UUID = UUID()
        var name: String = ""
        var roleRaw: String = FamilyRole.helper.rawValue
        var note: String?
        var isMe: Bool = false
        var customPermissionsRaw: [String]?
        var isOnDuty: Bool = false
        var dutyUntil: Date?
        var inviteToken: String?
        var inviteExpiresAt: Date?
        var accessExpiresAt: Date?
        var acceptedAt: Date?

        init() {}
    }

    @Model
    final class Episode {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var lastIncidentAt: Date = Date()
        var title: String = ""
        var detail: String = ""

        init() {}
    }

    @Model
    final class Trip {
        var id: UUID = UUID()
        var destination: String = ""
        var startDate: Date = Date()
        var endDate: Date = Date()
        var transportRaw: String = TransportKind.car.rawValue
        var travelHours: Double = 0
        var lodging: String = ""
        var participants: [String] = []
        var departureMinuteOfDay: Int = 9 * 60
        var packedItems: [String] = []
        var dog: Dog?

        init() {}
    }

    @Model
    final class FoodStock {
        var id: UUID = UUID()
        var kindRaw: String = FoodKind.dry.rawValue
        var brand: String = ""
        var packGrams: Int = 3000
        var packsLeft: Double = 1
        var countedAt: Date?
        var openedAt: Date?
        var gramsPerDay: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
        var dog: Dog?

        init() {}
    }

    @Model
    final class LogEvent {
        var id: UUID = UUID()
        var date: Date = Date()
        var kindRaw: String = LogKind.note.rawValue
        var authorName: String = ""
        var isSynced: Bool = true
        var note: String?
        var enteredAt: Date?
        var originRaw: String?
        var isDayOnly: Bool = false
        var outcomeRaw: String?
        var askSignalRaw: String?
        var durationSeconds: Int?
        var stoolFormRaw: String?
        var stoolFlagsRaw: [String] = []
        var grams: Int?
        var milliliters: Int?
        var fromPortion: Bool = false
        var reactionTriggerRaw: String?
        var reactionDistanceRaw: String?
        var incidentKindRaw: String?
        var incidentDetailRaw: String?
        var toldFamily: Bool = false
        var trainingSessionID: UUID?
        var medicationID: UUID?
        var careTaskID: UUID?
        var walkEventID: UUID?
        var deletedAt: Date?
        var deletedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingStep {
        var id: UUID = UUID()
        var cue: String = ""             // «Ко мне»
        var place: String = ""           // «Коридор»
        var person: String = ""          // «Виктория»
        var distanceMeters: Int = 2
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var consecutiveGoodSessions: Int = 0
        var order: Int = 0
        var dog: Dog?

        init() {}
    }

    @Model
    final class TrainingSession {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var durationSeconds: Int = 0
        var cue: String = ""
        var place: String = ""
        var person: String = ""
        var distanceMeters: Int = 2
        var markDelaysMs: [Int] = []
        var successes: Int = 0
        var attempts: Int = 0
        var gramsUsed: Int = 0
        var observationsRaw: [String] = []
        var countsTowardProgress: Bool = true
        var dog: Dog?

        init() {}
    }

    @Model
    final class ProcedureSkill {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var statusRaw: String = SkillStatus.notStarted.rawValue
        var targetDate: Date?
        var successes: Int = 0
        var attempts: Int = 0

        init() {}
    }
}

// MARK: - V4 · сейчас
//
// Отличие от V3 — `Dog.changedAt`: время последней правки профиля.
// Нужно потому, что с 23.09.2026 профиль собаки ездит в общем дневнике,
// а у спора двух телефонов должно быть чем разрешаться. Решение
// Виктории: побеждает правка, что позже.
//
// Здесь перечислены настоящие классы приложения: V4 и есть то, что
// лежит в `TogoShared/Models`. Следующая правка модели обязана
// повторить сегодняшний ход — заморозить V4 снимком и завести V5.
// Иначе она снова сменит форму под неизменной версией, и хранилища
// тех, у кого стоит сегодняшняя сборка, перестанут открываться молча.

nonisolated enum TogoSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Dog.self,
            DogDocument.self,
            DayOut.self,
            HeatRecord.self,
            FoodStock.self,
            LogEvent.self,
            CareTask.self,
            Medication.self,
            DoseRecord.self,
            WeightEntry.self,
            TrainingStep.self,
            TrainingSession.self,
            ProcedureSkill.self,
            FamilyMember.self,
            Episode.self,
            Trip.self,
        ]
    }
}

// MARK: - План перехода

/// Как хранилище прежней формы становится нынешним.
///
/// **Обе стадии — `.lightweight`, и это доказано диффом, а не выбрано
/// на глаз.** Сверка хранимых свойств по всем шестнадцати моделям
/// между `1815b59`, `4081a47` и `HEAD` даёт ровно четыре изменения,
/// и все четыре — добавление поля:
///
/// - `LogEvent.enteredAt: Date?` — опциональное;
/// - `LogEvent.originRaw: String?` — опциональное;
/// - `LogEvent.isDayOnly: Bool = false` — со значением по умолчанию;
/// - `Medication.fastingBeforeMinutes: Int = 0` — со значением по умолчанию.
///
/// Ни одно поле не удалено и не переименовано, ни у одного не менялись
/// тип, опциональность и атрибуты, набор сущностей тот же. Это ровно
/// тот случай, который CoreData выводит сам, и `.custom` здесь добавил
/// бы код без единой задачи для него.
///
/// **Чего `.lightweight` не делает и почему это верно.** Заполнить
/// `fastingBeforeMinutes` у прежних схем он не станет — там останется
/// ноль. Так и задумано: правило «у схемы без окна „до“ оно равно окну
/// „после“» живёт в `Medication.fastingBefore`, то есть в чтении,
/// а не в данных. Переписать это миграцией значило бы потерять разницу
/// между «не заполнено» и «поставлен явный ноль» безвозвратно —
/// у вычисляемого свойства она хотя бы восстановима.
nonisolated enum TogoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TogoSchemaV1.self, TogoSchemaV2.self, TogoSchemaV3.self, TogoSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TogoSchemaV1.self, toVersion: TogoSchemaV2.self),
            .lightweight(fromVersion: TogoSchemaV2.self, toVersion: TogoSchemaV3.self),
            // `Dog.changedAt: Date = Date()` — добавление поля
            // со значением по умолчанию. Ровно тот случай, который
            // CoreData выводит сам; у прежних собак там встанет момент
            // перехода, и это верно: профиль с тех пор никто не трогал.
            .lightweight(fromVersion: TogoSchemaV3.self, toVersion: TogoSchemaV4.self),
        ]
    }
}
