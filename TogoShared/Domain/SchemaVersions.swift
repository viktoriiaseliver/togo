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
// | V3     | 141    | `18843c1` | `Medication.fastingBeforeMinutes` |
// | V4     | 191–271| `923ac93` | `changedAt` ×3, `awaited…` ×2       |
// | V5     | сейчас | —         | тринадцать полей под экраны хендоффа|
//
// Номер сборки в этой таблице — число коммитов на тот день, когда
// строки писались. **С 07.10.2026 это больше не так**, и сопоставить
// версию схемы с номером сборки по `git rev-list` уже нельзя: номер
// стал решением и живёт в `Tools/номер-сборки.txt` (коммит `a5e7dd1`,
// решение Виктории). Замер 14.10.2026: в файле `276`, а
// `git rev-list --count HEAD` даёт **826** — счёт коммитов рос быстрее
// загрузок, и собранный по нему номер прыгнул бы вперёд необратимо.
// Прежние строки таблицы верны: они описывают прошлое, когда номер
// и правда был счётом. Новые строки сюда вписывать **по файлу номера**.
//
// Сборка 36 раздаётся тестировщикам, сборка 46 лежит
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


// MARK: - V3 · сборки 141–174, коммит 18843c1 (это сборка 165)
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

// MARK: - V4 · сборки 191–271, коммит 923ac93
//
// Отличие от V3 — пять полей, и все ради общего дневника:
//
// - `Dog.changedAt`, `CareTask.changedAt`, `Medication.changedAt` —
//   время последней правки. У спора двух телефонов должно быть чем
//   разрешаться; решение Виктории от 23.09.2026 — побеждает правка,
//   что позже.
// - `DoseRecord.awaitedMedicationID` и `awaitedMedicationName` — чего
//   ждёт доза, приехавшая раньше своей схемы. Связь `medication` это
//   ссылка на объект, и памяти у неё нет: ничья доза не помнит, чьей
//   хотела быть, а на экране не показывается вовсе — то есть второй
//   человек видит приём открытым и даёт вторую таблетку.
//
// **Почему это снимок, а не ссылки на нынешние классы — 05.10.2026.**
// До сегодняшнего дня V4 перечисляла живые классы приложения, и рядом
// стояла оговорка: «V4 не уезжала никуда, между ней и V3 нет ни одной
// сборки у тестировщиков». Оговорка была верна в момент написания
// и устарела через одиннадцать часов. Замер в App Store Connect:
//
//     V4 введена     коммит 39e3d91 · 23.09.2026 13:18
//     форма устоялась коммит 923ac93 · 23.09.2026, тем же днём
//     залито после    191 (24.09 00:25), 216, 248, 256, 258, 271
//     роздано         все шесть, IN_BETA_TESTING
//
// Шесть розданных сборок несут форму 4.0.0. Значит обязанность
// заморозить её наступила, и любое новое поле в живом классе сменило
// бы форму под неизменной версией — то есть повторило бы дефект
// 23.09 в точности: на телефоне это не падение, а откат
// iCloud → локально → в память, и человек отмечает дозу, видит
// подтверждение, а запись не сохраняется никуда.
//
// **Промежуточной формы 4.0.0 не видел никто, и основание этому
// не то, которым его сперва объяснили.** Первая редакция этой записи
// говорила «между сборками 175 и 177 не роздано ничего» — а сборок
// с такими номерами в ASC нет вовсе: 175 и 177 это номера КОММИТОВ
// (номер сборки тогда и был `git rev-list --count`, но залит
// не каждый коммит). Поймал togo-5a запросом всех девятнадцати
// сборок. Верное основание сильнее: ближайшая залитая после `39e3d91`
// — 191, а 185 залита 23.09 в 05:52, то есть ДО введения V4. Первая
// же сборка с V4 несла устоявшуюся форму.
//
// > Номер коммита и номер залитой сборки отвечают на разные вопросы.
// > В комментарии схемы слово «сборка» читается как замер ASC —
// > значит там оно означает только залитое.
//
// **С 07.10.2026 они и считаются по-разному** (`Tools/номер-сборки.txt`,
// коммит `a5e7dd1`): номер залитой сборки — решение в файле, счёт
// коммитов — производная от истории. Замер 14.10.2026: 276 против 826.
// Эта разница сама по себе и есть причина смены: счёт мерил количество
// нашей работы вместо количества отданных сборок.
//
// **Снимок не перенабран, а собран из V3 плюс измеренная разница.**
// Перенабор воспроизводит ошибку в невидимых местах: у V3 он однажды
// пропустил `@Attribute(.externalStorage)` у `DogDocument.image`.
// Дифф множеств хранимых свойств «снимок V3 → модели сборки 271» дал
// ровно эти пять полей, ни одного удаления и тот же набор сущностей;
// результат сверен с формой сборки 271 побайтно — 16 классов,
// 213 полей.
//
// Проверяется за минуту: `TogoTests/SchemaFrozenTests.swift`,
// тест «снимок V4 описывает форму розданных сборок».

nonisolated enum TogoSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, DayOut.self, Dog.self, DogDocument.self, FamilyMember.self, Episode.self, Trip.self, FoodStock.self, HeatRecord.self, LogEvent.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self]
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var changedAt: Date = Date()
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
        var changedAt: Date = Date()
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
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?
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
        var changedAt: Date = Date()
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

// MARK: - V5 · сейчас
//
// Отличие от V4 — **тринадцать** полей под экраны хендоффа
// (`Дизайн/КОНТРАКТ-ПАКЕТА.md:97` — контракт данных дизайна,
// `DECISIONS.md:6,10` — решения по запасу):
//
// | Модель | Поле | Зачем на экране |
// |---|---|---|
// | `Medication` | `unitRaw` | таблетка · мл · доза: «½ таблетки» и «1,5 мл» считаются по-разному |
// | | `doseSlotsData` | расписание с количеством на каждое время: ½ списывает 0,5 |
// | | `stockLeftAmount` | остаток дробно: половинки и миллилитры |
// | | `packAmount` | упаковка дробно; **им же включается счёт** — `PillSupplyAdvisor.supply` выходит через `guard packSize > 0` |
// | | `courseEnd` | «курс до»; курс короче запаса — о покупке не напоминаем |
// | | `expiry` | «годен до», с упаковки |
// | | `openedAt` | «вскрыт» — у капель отсчёт идёт от вскрытия |
// | | `shelfAfterOpenDays` | «после вскрытия»; переключатель «Сразу вскрыл» запускает отсчёт |
// | | `remindBeforeExpiry` | «напомню за месяц до конца срока» |
// | | `canGiveOutside` | «можно дать на улице» — кнопка «Дал» в режиме прогулки |
// | `FoodStock` | `expiry` | тот же «годен до» у корма |
// | | `shelfAfterOpenDays` | открытый мешок портится быстрее, чем кончается |
// | `LogEvent` | `editedBy` | экран правки записи: кто поправил, а не только кто удалил |
//
// **Правка этой таблицы 05.10, и механизм важнее трёх строк.** В первой
// редакции здесь стояло «десять полей» и семь строк у `Medication` —
// а в модели их было десять. Числа разошлись **не от устаревания**:
// оба написаны одним коммитом `2ba2989` в одну минуту. Таблицу
// я написал под замысел на десять полей, потом замер togo-9e добавил
// три (`stockLeftAmount`, `packAmount`, `remindBeforeExpiry`) — модель
// и тест я поправил, а таблицу нет.
//
// Поймал togo-f5, сверив таблицу с сообщением коммита. Верное число —
// тринадцать, и доказывает его не эта таблица, а прошедший тест
// `пятаяВерсияДобавляетПоля`: он перечисляет поля **поимённо**
// и падает от любого расхождения. Проверять надо им, а не чтением:
// у таблицы нет никого, кто бы её проверил.
//
// **Срок годности и срок после вскрытия — два разных поля, не одно.**
// В шторке «Купил» они стоят рядом, и «Сразу вскрыл» переключает одно
// в другое. Одним полем разница потерялась бы молча — и проявилась
// бы у человека с открытым флаконом, то есть там, где цена ошибки
// в дозе.
//
// **Почему ни одной новой сущности.** Набор из шестнадцати моделей —
// инвариант плана: на него опирается `.lightweight` и его сторожит
// `наборМоделейОдин`. Расписание доз с количеством легло полем внутри
// `Medication` структурой-слотом, а не отдельной моделью. Параллельные
// массивы «времена» и «количества» были бы миной: длины разъезжаются
// молча, и доза ½ приземлилась бы на чужой час.
//
// **Все тринадцать полей** опциональные или со значением по умолчанию
// — иначе зеркало CloudKit не заводится, а `.lightweight` не выводится.
// Это не счёт, а гарантия, и ровно ею V4→V5 объявлена облегчённой:
// сказанная про десять полей из тринадцати, она оставляла бы три
// без утверждения и читалась как утверждение про все. Проверяет её
// не это предложение, а сторож `беззащитныхНет` у togo-5a: ноль
// атрибутов без опциональности и без значения по умолчанию из 213.
//
// Поимённо: `unitRaw` = `.tab`, `doseSlotsData` = `[]`,
// `shelfAfterOpenDays` = 0 (оба места), `remindBeforeExpiry` = false,
// `canGiveOutside` = false; `stockLeftAmount`, `packAmount`,
// `courseEnd`, `expiry` (оба места), `openedAt`, `editedBy` —
// опциональные.
//
// Здесь перечислены настоящие классы приложения.
//
// **ФОРМА V5 МЕНЯЛАСЬ НА МЕСТЕ ДВАЖДЫ 07.10.2026, и это решение,
// а не недосмотр.** Шаг 0 добавил `Clinic`, медицинский слой —
// `LabResult`, `VetVisit`, `Diagnosis`, `Prescription`: шестнадцать
// сущностей стали двадцатью одной под неизменным номером `5.0.0`.
// Разрешила Виктория вслух: «данные сохранять не нужно, приложение
// можно снести целиком». Безопасно это потому, что отказ **громкий** —
// `Persistence.swift:265` показывает «Дневник не открылся» вместо
// молчаливого откатa в память.
//
// # Чем проверять, что так ещё можно. ЧЕТВЁРТАЯ редакция условия
//
// Прежние три редакции мерили не то, и порядок здесь важнее итога —
// он показывает, как вопрос подменялся:
//
//     1  «уедет в розданной сборке»   запрос в ASC: 271 < 318,
//        (МОЯ, и она неверна)         значит «не уехала», значит
//                                     «менять можно»
//     2  «существует база версии»     ближе, но мерила технику
//     3  решение Виктории             сняло вопрос для ЭТОЙ сборки,
//                                     не для класса
//     4  sqlite по `Z_METADATA`       отвечает на заданный вопрос
//
// **Первая редакция — моя, и она отвечала на другой вопрос.** Замер
// `togo-02` 07.10.2026: база `5.0.0` с шестнадцатью сущностями
// **уже лежала на устройстве**, пока ASC отвечал «не уехала». Причина
// проста и ни в чьей невнимательности: `make device` ставит сборку
// **мимо ASC**, и App Store Connect про неё не знает по устройству.
//
// > **Запрос отвечает «уехало ли ЭТИМ путём», а вопрос был «есть ли
// > вообще».** И ответил он в сторону разрешения — «безопасно
// > менять», — то есть ошибка была не нейтральной.
//
// Верный чек — не запрос в чужую систему, а одна команда по тому
// месту, где последствие и наступает:
//
//     sqlite3 "<App Group>/Togo.store" 'SELECT Z_PLIST FROM Z_METADATA'
//     # счёт NSStoreModelVersionHashes против числа сущностей в схеме
//
// Расходятся — на устройстве база другой формы, и правка V5 на месте
// даст этому человеку «Дневник не открылся».
//
// **Вопрос перед следующей правкой моделей — продуктовый, а не
// технический:** «эту базу тоже можно потерять?» Ответа на него нет
// ни в ASC, ни в `Z_METADATA` — он у хозяина данных. От кода требуется
// одно: чтобы вопрос **возник вовремя**, а для этого хватает честного
// чека.
//
// V6 **не заводилась нарочно**: `TogoSchemaV5` ссылается на живые
// модели, то есть V5 и V6 вышли бы побайтно одинаковыми, а стадия
// между двумя одинаковыми формами не миграция. Поднять номер
// по-настоящему можно только вместе со снимком — а снимок это те
// самые четыреста строк, которые Виктория отменила вслух.
//
// Цена, которую это несёт человеку, названа заранее, а не после:
// у Виктории на телефоне база `5.0.0` с шестнадцатью сущностями,
// и следующая сборка даст ей «Дневник не открылся». Экран честный,
// но **неожиданный**, и разница между «снесу, как разрешила»
// и «увидела поломку» — только в том, сказали ли ей до заливки.

// MARK: - V5 · сборки 273–277, ЗАМОРОЖЕНА 26.10.2026
//
// **Снимок, а не ссылки на живые классы, и заморожена она по аварии,
// а не по плану.** До 26.10.2026 `TogoSchemaV5` перечисляла живые
// классы приложения. Это было названо решением (прежняя редакция
// стояла здесь же) на посылке «V5 наружу не уехала» — и посылка
// устарела: сборки 273, 275, 276 и 277 розданы обеим группам
// TestFlight, пять телефонов.
//
// Цена посылки наступила в тот же день. Коммит `f546719` (16:04)
// добавил `deletedAt` одиннадцати живым моделям — и форма V5
// изменилась под неизменным номером `5.0.0` у всех, у кого стояла
// сборка. Телефон Виктории в 17:21:
//
//     право на iCloud есть, пробую
//     iCloud не открылся, откатываюсь на локальное
//     локальное не открылось: SwiftDataError(unknownDataStoreSchema)
//     файл дневника есть, но не открылся — «Дневник не открылся»
//
// Обе двери в одну стену: форма её базы не совпадала НИ С ОДНОЙ
// зарегистрированной версией, потому что снимка формы 304 не было
// нигде — V5 показывала на живые классы, то есть уже на 315 полей.
//
// > **Версия, которая ссылается на живые классы, не описывает ничего:
// > она описывает то, что получится, а старое хранилище описано
// > ровно тем, что получалось ТОГДА.**
//
// # Чем проверен этот снимок
//
// Не чтением. Снят из git — `git show 66f3512:TogoShared/Models/*.swift`,
// где `66f3512` — последний коммит перед `f546719`, — и извлечены
// ровно хранимые свойства с их аннотациями. Тела вычисляемых свойств
// и методов опущены: на форму хранилища они не влияют.
//
// Приёмка снимка машинная, и она сильнее любого глаза:
// `SchemaShapeTests.снимокПятойРавенРозданнойФорме` требует от него
// отпечаток `67ada9b4d174b89cd9fd8aed1bdb456c` и 304 свойства —
// записанные 08.10.2026, за восемнадцать дней до этой правки.
// Случайно в такой хеш не попасть.
//
// **Генератор снимка воспроизвёл исторический дефект V3, и поймал его
// счёт, а не внимательность.** Перенабор V3 однажды потерял
// `@Attribute(.externalStorage)` у `DogDocument.image`; здесь
// извлечение потеряло ТО ЖЕ САМОЕ поле и по той же причине —
// строка начинается не с `var`, а с аннотации, и проверка
// «начинается с `var`» прошла мимо неё молча. Разошлись числа:
// 303 против записанных 304. Поле вернулось в снимок.
//
// > **Одно и то же поле потеряно дважды, двумя разными способами,
// > с разницей в три недели. Защитил не опыт, а записанный счёт.**
//
// Между `43f05a5` (08.10, когда снят отпечаток 304) и `f546719`
// хранимые поля не менялись ни разу — десять коммитов по моделям,
// ноль правок формы (контроль: на самом `f546719` тот же разбор даёт
// 11). Значит форма 304 — ровно то, что лежит на пяти телефонах.
//
// Что было в V5 сверх V4 — тринадцать полей хендоффа, `Clinic`
// и медицинский слой (`LabResult`, `VetVisit`, `Diagnosis`,
// `Prescription`): шестнадцать сущностей стали двадцатью одной.
// Разбор каждого поля — в `SchemaMigrationTests.пятаяВерсияТолькоДобавляет`,
// поимённо, потому что число сходится и при перепутанных местах.

nonisolated enum TogoSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
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
        var changedAt: Date = Date()
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
        @Relationship(deleteRule: .cascade, inverse: \LabResult.dog)
        var labResultsStorage: [LabResult]?
        @Relationship(deleteRule: .cascade, inverse: \VetVisit.dog)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .cascade, inverse: \Diagnosis.dog)
        var diagnosesStorage: [Diagnosis]?
        @Relationship(deleteRule: .cascade, inverse: \Prescription.dog)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var kindRaw: String = DocumentKind.other.rawValue
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
        var changedAt: Date = Date()
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
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
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
        var expiry: Date?
        var shelfAfterOpenDays: Int = 0
        var gramsPerDay: Int = 0
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
        var editedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
        var clinic: Clinic?
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var doseSlotsData: [DoseSlot] = []
        var unitRaw: String = MedUnit.tab.rawValue
        var massPerUnitMcg: Double?
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var stockLeftAmount: Double?
        var packAmount: Double?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int = 0
        var remindBeforeExpiry: Bool = false
        var canGiveOutside: Bool = false
        var prescriptionNumber: String?
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var changedAt: Date = Date()
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
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?
        var changedAt: Date = Date()

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

    @Model
    final class Clinic {
        var id: UUID = UUID()
        var name: String = ""
        var detail: String?
        var isLab: Bool = false
        var phone: String?
        var createdAt: Date = Date()
        var changedAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \CareTask.clinic)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .nullify, inverse: \VetVisit.clinic)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .nullify, inverse: \Prescription.clinic)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class LabResult {
        var id: UUID = UUID()
        var sampledOn: Date = Date()
        var sampledAt: Date?
        var laboratory: String = ""
        var reportNumber: String = ""
        var section: String = ""
        var indicator: String = ""
        var value: Double?
        var belowLimit: Double?
        var aboveLimit: Double?
        var textValue: String?
        var unit: String = ""
        var referenceLow: Double?
        var referenceHigh: Double?
        var method: String?
        var labMark: String = ""
        var note: String = ""
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class VetVisit {
        var id: UUID = UUID()
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var reasonRaw: String = VisitReason.checkup.rawValue
        var conclusion: String = ""
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class Diagnosis {
        var id: UUID = UUID()
        var wording: String = ""
        var statusRaw: String = DiagnosisStatus.hypothesis.rawValue
        var madeOn: Date = Date()
        var madeBy: String = ""
        var evidence: String = ""
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class Prescription {
        var id: UUID = UUID()
        var number: String = ""
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var dogWeightKg: Double?
        var medicationName: String = ""
        var dosage: String = ""
        var schedule: String = ""
        var duration: String = ""
        var pharmacyForm: String?
        var controlFromWeeks: Int = 0
        var controlToWeeks: Int = 0
        var dispensed: String = ""
        var instruction: String = ""
        var source: String = ""
        var changedAt: Date = Date()
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
}

// MARK: - V6 · сейчас
//
// Отличие от V5 — **одиннадцать надгробий**, по одному полю
// `deletedAt: Date?` у каждого типа, который едет ко второму человеку:
// `CareTask`, `Clinic`, `Diagnosis`, `Dog`, `DogDocument`,
// `DoseRecord`, `LabResult`, `Medication`, `Prescription`, `VetVisit`,
// `WeightEntry`. Решение Виктории: «надгробия всем одиннадцати сразу».
//
// Двенадцатое надгробие — `LogEvent.deletedAt` — живёт с V4 и в этот
// счёт не входит. `Medication.massPerUnitMcg` тоже не входит: он вошёл
// 08.10 коммитом `43f05a5`, ТЕМ ЖЕ, что записал отпечаток 304, то есть
// он уже внутри формы V5. Наряд называл двенадцать новых полей —
// их одиннадцать, и арифметика `304 + 11 = 315` это подтвердила
// прогоном.
//
// **Зачем надгробия.** До них удаление у владельца не доезжало
// до второго человека ни по одному типу, кроме отметок: исходящая
// очередь собирается из `didSave`, а удалённая запись не приходит
// ни в `inserted`, ни в `updated`. Самый дорогой случай — отменённая
// схема лечения, которая у мамы оставалась жива и давала напоминания
// о дозах.
//
// **Здесь перечислены настоящие классы приложения, и это законно
// ровно потому, что V5 выше — снимок.** Пока последняя версия плана
// ссылается на живые классы, её форма ползёт при каждой правке модели,
// а номер стоит на месте: это и есть дефект 26.10. Правило, которое
// из него следует:
//
// > **Правка модели обязана идти вместе с новой версией — либо
// > не идти вовсе. Заморозить предыдущую ПОСЛЕ того, как она уехала
// > людям, уже нельзя без снимка, а снимок после факта снимается
// > только из git.**
//
// Все одиннадцать — `Date?`, опциональные: ни одного обязательного
// без значения по умолчанию, ни одного удаления, ни одного
// переименования, набор сущностей тот же (21 → 21). Это ровно тот
// случай, который CoreData выводит сам, и ровно поэтому стадия
// V5 → V6 объявлена облегчённой.

nonisolated enum TogoSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    /// **V6 ЗАМОРОЖЕНА СНИМКОМ 27.10.2026, и это починка того же
    /// класса, что вчера стоил людям открытого дневника.**
    ///
    /// До этой правки `models` перечисляла ЖИВЫЕ классы, и форма V6
    /// менялась под неизменным номером `6.0.0` при каждом добавлении
    /// поля. Ровно так 26.10 сломалась V5: у человека со сборкой
    /// 273–277 хранилище перестало совпадать с любой зарегистрированной
    /// версией, и приложение честно говорило «Дневник не открылся».
    ///
    /// > **Версия, ссылающаяся на живые классы, не описывает ничего:
    /// > она описывает то, что ПОЛУЧИТСЯ, а старое хранилище описано
    /// > ровно тем, что получалось ТОГДА.**
    ///
    /// Поэтому здесь снимок: 21 класс, 335 хранимых свойств, снятый
    /// с `TogoShared/Models/*.swift` **до** добавления `LogEvent.photo`.
    /// Сверен с живыми классами по числу свойств у каждой модели —
    /// расхождений ноль.
    ///
    /// Сборка 279 уехала людям именно с этой формой. Она и есть то,
    /// из чего V7 обязана уметь мигрировать.
    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
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
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        @Relationship(deleteRule: .cascade, inverse: \LabResult.dog)
        var labResultsStorage: [LabResult]?
        @Relationship(deleteRule: .cascade, inverse: \VetVisit.dog)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .cascade, inverse: \Diagnosis.dog)
        var diagnosesStorage: [Diagnosis]?
        @Relationship(deleteRule: .cascade, inverse: \Prescription.dog)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var kindRaw: String = DocumentKind.other.rawValue
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
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
        var expiry: Date?
        var shelfAfterOpenDays: Int = 0
        var gramsPerDay: Int = 0
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
        var editedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
        var clinic: Clinic?
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var doseSlotsData: [DoseSlot] = []
        var unitRaw: String = MedUnit.tab.rawValue
        var massPerUnitMcg: Double?
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var stockLeftAmount: Double?
        var packAmount: Double?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int = 0
        var remindBeforeExpiry: Bool = false
        var canGiveOutside: Bool = false
        var prescriptionNumber: String?
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        var deletedAt: Date?
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?
        var changedAt: Date = Date()
        var deletedAt: Date?

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

    @Model
    final class Clinic {
        var id: UUID = UUID()
        var name: String = ""
        var detail: String?
        var isLab: Bool = false
        var phone: String?
        var createdAt: Date = Date()
        var changedAt: Date = Date()
        var deletedAt: Date?
        @Relationship(deleteRule: .nullify, inverse: \CareTask.clinic)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .nullify, inverse: \VetVisit.clinic)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .nullify, inverse: \Prescription.clinic)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class LabResult {
        var id: UUID = UUID()
        var sampledOn: Date = Date()
        var sampledAt: Date?
        var laboratory: String = ""
        var reportNumber: String = ""
        var section: String = ""
        var indicator: String = ""
        var value: Double?
        var belowLimit: Double?
        var aboveLimit: Double?
        var textValue: String?
        var unit: String = ""
        var referenceLow: Double?
        var referenceHigh: Double?
        var method: String?
        var labMark: String = ""
        var note: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class VetVisit {
        var id: UUID = UUID()
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var reasonRaw: String = VisitReason.checkup.rawValue
        var conclusion: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Diagnosis {
        var id: UUID = UUID()
        var wording: String = ""
        var statusRaw: String = DiagnosisStatus.hypothesis.rawValue
        var madeOn: Date = Date()
        var madeBy: String = ""
        var evidence: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Prescription {
        var id: UUID = UUID()
        var number: String = ""
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var dogWeightKg: Double?
        var medicationName: String = ""
        var dosage: String = ""
        var schedule: String = ""
        var duration: String = ""
        var pharmacyForm: String?
        var controlFromWeeks: Int = 0
        var controlToWeeks: Int = 0
        var dispensed: String = ""
        var instruction: String = ""
        var source: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
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
}

// MARK: - V7 · сборки 280–282, ЗАМОРОЖЕНА 28.10.2026
//
// **Снимок, а не ссылки на живые классы, и на этот раз заморозка идёт
// ПО ПЛАНУ, а не по аварии.** V5 морозили 26.10 после того, как
// у людей перестал открываться дневник; V6 — 27.10, уже спокойно;
// здесь то же действие сделано ПЕРВЫМ шагом правки модели, до того
// как форма сдвинулась.
//
// # Чем доказано, что морозить было обязательно
//
// Не рассуждением о риске, а замером по `Tools/номер-сборки.txt`:
//
//     280   собрана из worktree на 6777711, залита, роздана ОБЕИМ
//           группам TestFlight, принята внешней, привязана к версии 1.0.
//           В перечне того, что она несёт сверх 279: «фото момента
//           у записи дня (поле, экран, обмен ассетом CloudKit, СХЕМА V7)»
//     281   роздана обеим группам, привязана к версии 1.0
//     282   роздана обеим группам, принята внешней, привязана к версии
//
// То есть форма `7.0.0` существует **вне репозитория**, на телефонах,
// и поправить её на месте значит сломать её у людей — ровно то, что
// случилось 26.10 с формой 304.
//
// > **Правка модели обязана идти вместе с новой версией — либо
// > не идти вовсе.** Правило записано в шапке V6 после аварии;
// > здесь оно исполнено, а не пересказано.
//
// # Чем проверен этот снимок
//
// Машинно, и проверка сильнее любого глаза: `SchemaShapeTests`
// требует от формы `7.0.0` отпечаток `bc29886f0a13fedcb9d98de2af8c5c34`
// и **316** свойств. Оба числа записаны 27.10.2026, за день до этого
// снимка, прогоном самого сторожа («замерено bc29886f…, 316 свойств»),
// а не рукой. Подогнать 128-битный хеш перенабором нельзя.
//
// Снят не перенабором: взят блок V6 (21 класс, 315 свойств, уже
// принятый прогоном) плюс одно поле `LogEvent.photo` —
// `@Attribute(.externalStorage) var photo: Data?`, то самое, которым
// V7 от V6 и отличается. Арифметика сошлась сама: 315 + 1 = 316.
//
// **Сверка с git дала ОДНО расхождение и один ложный плюс, и второй
// важнее первого.** Разбор `git show HEAD:TogoShared/Models/*.swift`
// против блока V6 назвал у `LogEvent` два лишних поля — `photo`
// и `parts`. `parts` поля не существует: это **локальная переменная
// внутри вычисляемого свойства** (`LogEvent.swift:233`), и однострочный
// разбор не отличает её от члена класса.
//
// > **Это тот же класс ошибки разбора, который в этом файле
// > спотыкался уже трижды** — дважды на `@Attribute(.externalStorage)
// > перед `var` (потерянный `DogDocument.image` у V3 и у снимка V5),
// > теперь на локальной переменной. Разница в знаке: аннотация давала
// > снимок БЕДНЕЕ настоящего, локальная переменная — БОГАЧЕ.
// > Поймало не чтение, а записанный счёт: 316 против 317.
//
// Тела вычисляемых свойств и методов опущены намеренно — на форму
// хранилища они не влияют, а лишний код разошёлся бы с оригиналом.

nonisolated enum TogoSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
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
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        @Relationship(deleteRule: .cascade, inverse: \LabResult.dog)
        var labResultsStorage: [LabResult]?
        @Relationship(deleteRule: .cascade, inverse: \VetVisit.dog)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .cascade, inverse: \Diagnosis.dog)
        var diagnosesStorage: [Diagnosis]?
        @Relationship(deleteRule: .cascade, inverse: \Prescription.dog)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var kindRaw: String = DocumentKind.other.rawValue
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
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
        var expiry: Date?
        var shelfAfterOpenDays: Int = 0
        var gramsPerDay: Int = 0
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
        @Attribute(.externalStorage) var photo: Data?
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
        var editedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
        var clinic: Clinic?
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var doseSlotsData: [DoseSlot] = []
        var unitRaw: String = MedUnit.tab.rawValue
        var massPerUnitMcg: Double?
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var stockLeftAmount: Double?
        var packAmount: Double?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int = 0
        var remindBeforeExpiry: Bool = false
        var canGiveOutside: Bool = false
        var prescriptionNumber: String?
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        var deletedAt: Date?
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?
        var changedAt: Date = Date()
        var deletedAt: Date?

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

    @Model
    final class Clinic {
        var id: UUID = UUID()
        var name: String = ""
        var detail: String?
        var isLab: Bool = false
        var phone: String?
        var createdAt: Date = Date()
        var changedAt: Date = Date()
        var deletedAt: Date?
        @Relationship(deleteRule: .nullify, inverse: \CareTask.clinic)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .nullify, inverse: \VetVisit.clinic)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .nullify, inverse: \Prescription.clinic)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class LabResult {
        var id: UUID = UUID()
        var sampledOn: Date = Date()
        var sampledAt: Date?
        var laboratory: String = ""
        var reportNumber: String = ""
        var section: String = ""
        var indicator: String = ""
        var value: Double?
        var belowLimit: Double?
        var aboveLimit: Double?
        var textValue: String?
        var unit: String = ""
        var referenceLow: Double?
        var referenceHigh: Double?
        var method: String?
        var labMark: String = ""
        var note: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class VetVisit {
        var id: UUID = UUID()
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var reasonRaw: String = VisitReason.checkup.rawValue
        var conclusion: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Diagnosis {
        var id: UUID = UUID()
        var wording: String = ""
        var statusRaw: String = DiagnosisStatus.hypothesis.rawValue
        var madeOn: Date = Date()
        var madeBy: String = ""
        var evidence: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Prescription {
        var id: UUID = UUID()
        var number: String = ""
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var dogWeightKg: Double?
        var medicationName: String = ""
        var dosage: String = ""
        var schedule: String = ""
        var duration: String = ""
        var pharmacyForm: String?
        var controlFromWeeks: Int = 0
        var controlToWeeks: Int = 0
        var dispensed: String = ""
        var instruction: String = ""
        var source: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
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
}

/// Восьмая форма: у документа появились дата события, направление
/// и клиника.
///
/// **Решение Виктории 28.10.2026** — на предложение она ответила
/// дословно «да звучит отлично», а замысел назвала так: «не просто
/// записывать данные, а фотографировать результаты и подписывать их
/// правильно — что это такое, чтоб потом быстро находить документы
/// по датам и то, какие были сделаны анализы и в каком направлении».
///
/// Отличие от V7 — **четыре свойства у двух моделей**, и все четыре
/// опциональные:
///
/// | Модель | Свойство | Зачем |
/// |---|---|---|
/// | `DogDocument` | `occurredOn: Date?` | когда случилось то, о чём документ. `addedAt` отвечает про телефон: бланк от 16.10 сняли 27-го |
/// | | `directionRaw: String?` | направление анализа: гормоны, ОАК, биохимия, визуальное, микробиология, прививки, прочее |
/// | | `clinic: Clinic?` | где делали — связь со справочником, как у `CareTask`, `VetVisit` и `Prescription` |
/// | `Clinic` | `documentsStorage: [DogDocument]?` | обратная сторона той же связи |
///
/// **Четвёртое свойство — не украшение и не задел.** Зеркало CloudKit
/// отказывается открывать хранилище у связи без обратной:
/// `CloudKit integration requires that all relationships have
/// an inverse, the following do not:` — замер `togo-1e` 07.10.2026,
/// и это был не красный тест, а контейнер, не открывшийся вовсе.
/// Объявив `DogDocument.clinic` и не объявив обратную, мы получили бы
/// у человека молчаливый откат в память: рабочий экран, отметка дозы,
/// запись в никуда.
///
/// Разбор каждого поля — у объявления (`TogoShared/Models/DogDocument.swift`),
/// а не здесь: читают их там. Здесь — только то, что делает форму
/// формой.
///
/// ```
/// сущностей      21 → 21     ни одной новой, ни одной удалённой
/// переименований 0
/// удалений полей 0
/// новых свойств  4, ВСЕ опциональные
/// ```
///
/// **Почему `directionRaw` опционально БЕЗ значения по умолчанию,
/// в отличие от соседнего `kindRaw`.** У `kindRaw` умолчание `.other`
/// стоит нарочно — это ключ группировки списка, и пустым он рассыпал
/// бы показ. У направления умолчания быть не должно: «направления
/// нет» (паспорт, договор) и «направление прочее» (цитология) —
/// разные состояния, и умолчанием `.other` все паспорта собрались бы
/// в группу «прочие анализы», которой они не являются. Для миграции
/// разницы нет: опциональное без умолчания CoreData выводит так же.
///
/// Поэтому стадия `.lightweight` — по тому же доводу, что V6 → V7:
/// опциональные поля CoreData выводит сам, а у записей, пришедших
/// с V7, ни даты события, ни направления, ни клиники не будет —
/// и это верно, их там и не было. Выдумать их миграцией нечем,
/// а подставить `addedAt` вместо `occurredOn` значило бы сказать
/// за человека, что анализ сдан в день съёмки; запись потом читает
/// врач.
///
/// Здесь перечислены настоящие классы приложения, и это законно ровно
/// потому, что V7 выше — снимок.
nonisolated enum TogoSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    /// **Заморожена 28.10.2026 снимком — ПЕРЕД тем, как к `Medication`
    /// добавили `startedAt`.** Снимок собран машиной, а не руками:
    /// снимок V6 плюс единственная разница V7 — `LogEvent.photo`
    /// с `.externalStorage` (`ea2efc3`). Разница проверена разбором
    /// живых классов: хранимые поля всех 21 сущности совпали со снимком
    /// V6 ровно до этой строки. Сборки 280–284 уехали людям с этой формой.
    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
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
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        @Relationship(deleteRule: .cascade, inverse: \LabResult.dog)
        var labResultsStorage: [LabResult]?
        @Relationship(deleteRule: .cascade, inverse: \VetVisit.dog)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .cascade, inverse: \Diagnosis.dog)
        var diagnosesStorage: [Diagnosis]?
        @Relationship(deleteRule: .cascade, inverse: \Prescription.dog)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var kindRaw: String = DocumentKind.other.rawValue
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
        // Четыре поля формы, уехавшей в сборке 284. Снимок без них
        // совпадал с V7 по контрольной сумме, и SwiftData отказывал
        // при открытии: «Duplicate version checksums across stages
        // detected» — приложение падало до первого теста.
        var occurredOn: Date?
        var directionRaw: String?
        var clinic: Clinic?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
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
        var expiry: Date?
        var shelfAfterOpenDays: Int = 0
        var gramsPerDay: Int = 0
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
        @Attribute(.externalStorage) var photo: Data?
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
        var editedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
        var clinic: Clinic?
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var doseSlotsData: [DoseSlot] = []
        var unitRaw: String = MedUnit.tab.rawValue
        var massPerUnitMcg: Double?
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var stockLeftAmount: Double?
        var packAmount: Double?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int = 0
        var remindBeforeExpiry: Bool = false
        var canGiveOutside: Bool = false
        var prescriptionNumber: String?
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        var deletedAt: Date?
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?
        var changedAt: Date = Date()
        var deletedAt: Date?

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

    @Model
    final class Clinic {
        var id: UUID = UUID()
        var name: String = ""
        var detail: String?
        var isLab: Bool = false
        var phone: String?
        var createdAt: Date = Date()
        var changedAt: Date = Date()
        var deletedAt: Date?
        @Relationship(deleteRule: .nullify, inverse: \CareTask.clinic)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .nullify, inverse: \VetVisit.clinic)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .nullify, inverse: \Prescription.clinic)
        var prescriptionsStorage: [Prescription]?

        init() {}
        @Relationship(deleteRule: .nullify, inverse: \DogDocument.clinic)
        var documentsStorage: [DogDocument]?
    }

    @Model
    final class LabResult {
        var id: UUID = UUID()
        var sampledOn: Date = Date()
        var sampledAt: Date?
        var laboratory: String = ""
        var reportNumber: String = ""
        var section: String = ""
        var indicator: String = ""
        var value: Double?
        var belowLimit: Double?
        var aboveLimit: Double?
        var textValue: String?
        var unit: String = ""
        var referenceLow: Double?
        var referenceHigh: Double?
        var method: String?
        var labMark: String = ""
        var note: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class VetVisit {
        var id: UUID = UUID()
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var reasonRaw: String = VisitReason.checkup.rawValue
        var conclusion: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Diagnosis {
        var id: UUID = UUID()
        var wording: String = ""
        var statusRaw: String = DiagnosisStatus.hypothesis.rawValue
        var madeOn: Date = Date()
        var madeBy: String = ""
        var evidence: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Prescription {
        var id: UUID = UUID()
        var number: String = ""
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var dogWeightKg: Double?
        var medicationName: String = ""
        var dosage: String = ""
        var schedule: String = ""
        var duration: String = ""
        var pharmacyForm: String?
        var controlFromWeeks: Int = 0
        var controlToWeeks: Int = 0
        var dispensed: String = ""
        var instruction: String = ""
        var source: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
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
}

/// V9 — снимок с 29.10.2026; до того стояла на живых классах.
///
/// **28.10.2026: `Medication.startedAt`** — с какого дня идёт схема.
/// Просьба Виктории: «нужно добавить дату лечения или начала схемы, если
/// начали раньше, а заполнили „сегодня"». Поле необязательное: у схем,
/// заведённых до V8, оно пустое, и это «начало не названо», а не «сегодня».
///
/// > Следующая правка модели обязана сперва заморозить ЭТУ версию
/// > снимком, сверив хранимые поля живых классов со снимком V7,
/// > и только потом менять классы.
// MARK: - V9 · снимок · Medication.startedAt
//
// **Эта форма пришла из облачной сессии 28.10.2026 под номером V8 —
// и номер был занят.** Локальная сессия в тот же день завела свою
// V8 (`DogDocument.occurredOn/direction/clinic`), собрала из неё
// сборку 284 и РАЗДАЛА её обеим группам TestFlight. Две разные формы
// под одним `Schema.Version(8, 0, 0)` — это `Cannot use staged
// migration with an unknown model version` у всякого, кто поставил
// 284: его хранилище объявляет себя восьмой формой, а план описывает
// восьмую иначе.
//
// Замер 29.10.2026, которым коллизия установлена:
//
//     наша V8   Schema.Version(8,0,0)   DogDocument.occurredOn/direction/clinic
//     их  V8    Schema.Version(8,0,0)   Medication.startedAt
//     контроль  поле startedAt: у нас 0 вхождений, у них 1;
//               «var name» — 1 у обоих, то есть запрос жив
//
// Разведены так: **V8 остаётся за тем, что уже уехало людям**, и она
// заморожена снимком; новое поле становится V9 на живых классах
// (с 29.10.2026 — тоже снимок, живые классы ушли в V10).
// Обратный порядок был бы хуже вдвое — пришлось бы менять форму,
// которая стоит на телефонах, и переписывать её снимок задним числом.
//
// > **Номер версии схемы — это не имя правки, а адрес формы
// > на чужом телефоне.** Занять его второй раз нельзя, даже если
// > правка меньше.
nonisolated enum TogoSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    /// **Заморожена 29.10.2026 снимком — ПЕРЕД тем, как к `Episode`
    /// добавили `dogID`.** Снимок собран машиной: снимок V8 плюс две
    /// разницы живых классов, найденные разбором хранимых полей всех
    /// 21 сущности — `Medication.startedAt` (сама V9) и `Dog.photo`
    /// с `.externalStorage` (`1d5a69c`, правлено в живых классах
    /// до сведения линий и в снимок V8 не попавшее). Расхождений
    /// живых классов с этим снимком — 0. С этой формой собрана 285
    /// (заметки к ней — `ca26ce7`, «сведение схем»).
    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
    }

    @Model
    final class Dog {
        var id: UUID = UUID()
        var name: String = ""
        @Attribute(.externalStorage) var photo: Data?
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
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        @Relationship(deleteRule: .cascade, inverse: \LabResult.dog)
        var labResultsStorage: [LabResult]?
        @Relationship(deleteRule: .cascade, inverse: \VetVisit.dog)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .cascade, inverse: \Diagnosis.dog)
        var diagnosesStorage: [Diagnosis]?
        @Relationship(deleteRule: .cascade, inverse: \Prescription.dog)
        var prescriptionsStorage: [Prescription]?

        init() {}
    }

    @Model
    final class DogDocument {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(.externalStorage) var image: Data?
        var addedAt: Date = Date()
        var note: String?
        var kindRaw: String = DocumentKind.other.rawValue
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
        // Четыре поля формы, уехавшей в сборке 284. Снимок без них
        // совпадал с V7 по контрольной сумме, и SwiftData отказывал
        // при открытии: «Duplicate version checksums across stages
        // detected» — приложение падало до первого теста.
        var occurredOn: Date?
        var directionRaw: String?
        var clinic: Clinic?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
    final class HeatRecord {
        var id: UUID = UUID()
        var startedAt: Date = Date()
        var endedAt: Date?
        var note: String?
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
        var expiry: Date?
        var shelfAfterOpenDays: Int = 0
        var gramsPerDay: Int = 0
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
        @Attribute(.externalStorage) var photo: Data?
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
        var editedBy: String?
        var changedAt: Date = Date()
        var dog: Dog?

        init() {}
    }

    @Model
    final class CareTask {
        var id: UUID = UUID()
        var title: String = ""
        var detail: String = ""
        var kindRaw: String = CareKind.periodic.rawValue
        var categoryRaw: String = CareCategory.grooming.rawValue
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
        var clinic: Clinic?
        var intervalDays: Int = 30
        var scheduledDate: Date?
        var remindDaysBefore: Int = 14
        var lastDone: Date?
        var streak: Int = 0
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int = 0
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Medication {
        var id: UUID = UUID()
        var startedAt: Date?
        var name: String = ""
        var doseText: String = ""
        var times: [Int] = []
        var doseSlotsData: [DoseSlot] = []
        var unitRaw: String = MedUnit.tab.rawValue
        var massPerUnitMcg: Double?
        var fastingMinutes: Int = 0
        var fastingBeforeMinutes: Int = 0
        var minutesAfterMeal: Int = 0
        var isPaused: Bool = false
        var stockLeft: Int = 0
        var stockTotal: Int = 0
        var stockLeftAmount: Double?
        var packAmount: Double?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int = 0
        var remindBeforeExpiry: Bool = false
        var canGiveOutside: Bool = false
        var prescriptionNumber: String?
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var changedAt: Date = Date()
        var deletedAt: Date?
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
        var deletedAt: Date?
        var skippedAt: Date?
        var skippedBy: String?
        var medication: Medication?
        var awaitedMedicationID: UUID?
        var awaitedMedicationName: String?

        init() {}
    }

    @Model
    final class WeightEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var kg: Double = 0
        var dog: Dog?
        var changedAt: Date = Date()
        var deletedAt: Date?

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

    @Model
    final class Clinic {
        var id: UUID = UUID()
        var name: String = ""
        var detail: String?
        var isLab: Bool = false
        var phone: String?
        var createdAt: Date = Date()
        var changedAt: Date = Date()
        var deletedAt: Date?
        @Relationship(deleteRule: .nullify, inverse: \CareTask.clinic)
        var careTasksStorage: [CareTask]?
        @Relationship(deleteRule: .nullify, inverse: \VetVisit.clinic)
        var vetVisitsStorage: [VetVisit]?
        @Relationship(deleteRule: .nullify, inverse: \Prescription.clinic)
        var prescriptionsStorage: [Prescription]?

        init() {}
        @Relationship(deleteRule: .nullify, inverse: \DogDocument.clinic)
        var documentsStorage: [DogDocument]?
    }

    @Model
    final class LabResult {
        var id: UUID = UUID()
        var sampledOn: Date = Date()
        var sampledAt: Date?
        var laboratory: String = ""
        var reportNumber: String = ""
        var section: String = ""
        var indicator: String = ""
        var value: Double?
        var belowLimit: Double?
        var aboveLimit: Double?
        var textValue: String?
        var unit: String = ""
        var referenceLow: Double?
        var referenceHigh: Double?
        var method: String?
        var labMark: String = ""
        var note: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class VetVisit {
        var id: UUID = UUID()
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var reasonRaw: String = VisitReason.checkup.rawValue
        var conclusion: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Diagnosis {
        var id: UUID = UUID()
        var wording: String = ""
        var statusRaw: String = DiagnosisStatus.hypothesis.rawValue
        var madeOn: Date = Date()
        var madeBy: String = ""
        var evidence: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
        var dog: Dog?

        init() {}
    }

    @Model
    final class Prescription {
        var id: UUID = UUID()
        var number: String = ""
        var date: Date = Date()
        var clinic: Clinic?
        var doctor: String = ""
        var dogWeightKg: Double?
        var medicationName: String = ""
        var dosage: String = ""
        var schedule: String = ""
        var duration: String = ""
        var pharmacyForm: String?
        var controlFromWeeks: Int = 0
        var controlToWeeks: Int = 0
        var dispensed: String = ""
        var instruction: String = ""
        var source: String = ""
        var changedAt: Date = Date()
        var deletedAt: Date?
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
}

// MARK: - V10 · живые классы · Episode.dogID
//
// **Эпизод был общим на всех собак.** `Episode` не знал, чей он:
// две рвоты у щенка гасили вердикты «просится» и у пожилой собаки
// в том же доме, а «эпизод» висел на её экране без единого её
// инцидента. Решение Виктории 29.10.2026 («да, всё поправь», схема
// включительно).
//
// ```
// сущностей      21 → 21
// новых свойств  1, опциональное: Episode.dogID: UUID?
// удалений, переименований  0
// ```
//
// Ссылка — идентификатором, а не связью `Dog ↔ Episode`: связь
// потребовала бы второго свойства у `Dog` (обратной стороны) и правки
// снимков обмена, а вопрос у читателей один — «чей», и на него
// отвечает `UUID`. Пустой `dogID` у эпизодов, пришедших с V9, значит
// «чей — не записано», и такой эпизод читается по-старому, общим:
// выдумать хозяина миграцией нечем.
//
// > Следующая правка модели обязана сперва заморозить ЭТУ версию
// > снимком, сверив хранимые поля живых классов со снимком V9.
nonisolated enum TogoSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Dog.self, DogDocument.self, DayOut.self, HeatRecord.self, FoodStock.self, LogEvent.self, CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, TrainingStep.self, TrainingSession.self, ProcedureSkill.self, Clinic.self, LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self, FamilyMember.self, Episode.self, Trip.self]
    }
}

nonisolated enum TogoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TogoSchemaV1.self, TogoSchemaV2.self, TogoSchemaV3.self,
         TogoSchemaV4.self, TogoSchemaV5.self, TogoSchemaV6.self,
         TogoSchemaV7.self, TogoSchemaV8.self, TogoSchemaV9.self,
         TogoSchemaV10.self]
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
            // Десять полей под экраны хендоффа, все опциональные или
            // со значением по умолчанию, ни одного удаления, набор
            // сущностей тот же. У тех, кто пришёл с V4, «годен до»
            // и «вскрыт» останутся пустыми — и это верно: приложение
            // этих дат не знало, а выдумывать их миграцией значило бы
            // напечатать срок, которого человек не вводил, на экране
            // про лекарство.
            .lightweight(fromVersion: TogoSchemaV4.self, toVersion: TogoSchemaV5.self),
            // Одиннадцать надгробий `deletedAt: Date?`, все опциональные,
            // ни одного удаления и ни одного переименования, набор
            // сущностей тот же. У записей, пришедших с V5, надгробие
            // останется пустым — и это верно: пустое надгробие и значит
            // «запись жива».
            //
            // **Эта стадия — единственное, что открывает хранилище
            // пяти розданных сборок.** Без неё форма 304 не совпадает
            // ни с одной версией плана, и человек получает «Дневник
            // не открылся» при целом файле на диске.
            .lightweight(fromVersion: TogoSchemaV5.self, toVersion: TogoSchemaV6.self),
            // Одно поле: `LogEvent.photo: Data?` с `.externalStorage`.
            // Опциональное, удалений и переименований ноль, сущностей
            // 21 → 21. Тот же случай, что V5 → V6, и тот же довод:
            // у записей, пришедших с V6, фотографии не будет — её там
            // и не было, а выдумать её миграцией нечем.
            .lightweight(fromVersion: TogoSchemaV6.self, toVersion: TogoSchemaV7.self),
            // Четыре свойства: `DogDocument.occurredOn`,
            // `DogDocument.directionRaw`, `DogDocument.clinic`
            // и обратная сторона той же связи `Clinic.documentsStorage`.
            // Все опциональные, удалений и переименований ноль,
            // сущностей 21 → 21.
            //
            // **Эта стадия — единственное, что открывает хранилище
            // сборок 280, 281 и 282**, розданных обеим группам
            // TestFlight и привязанных к версии 1.0. Без неё форма 316
            // не совпадает ни с одной версией плана, и человек получает
            // «Дневник не открылся» при целом файле на диске — ровно
            // то, что случилось 26.10 с формой 304.
            //
            // У документов, пришедших с V7, дата события, направление
            // и клиника останутся пустыми, и это верно: приложение
            // этих величин не знало. Подставить `addedAt`
            // в `occurredOn` миграцией было бы хуже пустоты — вышло бы,
            // что человек сказал «анализ сдан в день съёмки», а он
            // этого не говорил.
            .lightweight(fromVersion: TogoSchemaV7.self, toVersion: TogoSchemaV8.self),
            // V8 → V9: необязательное `Medication.startedAt`. Поле
            // добавляется пустым, ничего не переносится — `.lightweight`.
            //
            // Стадия заведена 29.10.2026 при сведении двух линий: эта
            // правка пришла из облачной сессии как V8, а номер уже
            // был занят формой, уехавшей в сборке 284. Разбор —
            // у объявления `TogoSchemaV9`.
            .lightweight(fromVersion: TogoSchemaV8.self, toVersion: TogoSchemaV9.self),
            // V9 → V10: необязательное `Episode.dogID`. Добавляется
            // пустым — у прежних эпизодов хозяин не записан, и они
            // читаются общими, как читались до сих пор.
            .lightweight(fromVersion: TogoSchemaV9.self, toVersion: TogoSchemaV10.self),
        ]
    }
}
