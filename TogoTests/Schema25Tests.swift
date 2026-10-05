import Testing
import Foundation
import SwiftData
@testable import Togo

/// Форма сборки 25 — единственная розданная, которой нет в плане.
///
/// **Почему про неё отдельный файл.** В App Store Connect девятнадцать
/// залитых сборок; план миграции описывает формы сборок 36 (V1),
/// 46 (V2), 141 (V3), 191–271 (V4) и нынешнюю (V5). Форма **сборки 25**
/// (27.08.2026) в плане не описана никак: дифф хранимых полей по git
/// даёт 192 поля против 204 у V1 — нет `Dog.sitter*` ×5,
/// `DoseRecord.changedAt/skippedAt/skippedBy`, `LogEvent.changedAt`,
/// `Medication.minutesAfterMeal/stockLeft/stockTotal`.
///
/// И она роздана людям: `/v1/betaGroups/<id>/builds` отдаёт её
/// во внутренней группе «Свои» (во внешних «Друзьях» её нет).
/// Спрашивать надо именно этим запросом — обратное направление,
/// `/v1/builds/<id>/betaGroups`, отвечает `403`, а `externalBuildState`
/// у внутренней раздачи навсегда остаётся `READY_FOR_BETA_SUBMISSION`
/// и читается как «не роздана».
///
/// **Что до этого файла было измерено, а что нет.** Измерена ФОРМА.
/// Исход открытия не мерил никто — а «форма не описана» и «дневник
/// не откроется» это два разных утверждения, и второе из первого
/// не следует: `.lightweight` выводит добавление поля сам, и теоретически
/// мог бы вывести все двенадцать.
///
/// Снимок формы 25 собран не руками: взят блок `TogoSchemaV1` и из него
/// **вырезаны** ровно те двенадцать полей, которых по git на сборке 25
/// не было. Применённость вырезания подтверждена до прогона — каждое
/// из двенадцати найдено и снято, и множества полей всех четырёх классов
/// сверены с формой сборки 25 побайтно. Подделка, не совпавшая молча,
/// дала бы зелёный прогон и вывод, ОБРАТНЫЙ правде.
@Suite("Форма сборки 25 — розданная и не описанная планом")
struct Schema25Tests {

    private func заводимПапку() throws -> URL {
        let папка = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("togo-25-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: папка, withIntermediateDirectories: true)
        return папка.appendingPathComponent("Togo.store")
    }

    private func убираем(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func конфигурация(_ схема: Schema, _ url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: схема, url: url, cloudKitDatabase: .none)
    }

    /// Опыт, которого не делал никто: что происходит с базой сборки 25.
    ///
    /// Утверждение здесь — о ПОВЕДЕНИИ, а не о строке в логе: зелёный
    /// тест при печатающемся отказе хранилища и был бы тем самым
    /// дефектом, от которого весь этот файл.
    @Test("База сборки 25 не открывается планом, но и не подменяется пустым дневником")
    func формаДвадцатьПятойНеОткрывается() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        // 1. База августовской сборки, и в ней собака, которую нельзя потерять.
        do {
            let схема = Schema(versionedSchema: TogoSchema25.self)
            let контейнер = try ModelContainer(for: схема,
                                               configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)
            let собака = TogoSchema25.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            context.insert(собака)
            try context.save()
        }

        // 2. Исход опыта: нынешняя схема такую базу открыть НЕ может.
        //    Номер версии у неё тот же, что у V1 (1.0.0) — так его и запишет
        //    сборка без плана миграции, — а форма другая, и по форме
        //    SwiftData её не опознаёт. То есть двенадцать добавленных полей
        //    `.lightweight` сам не выводит: он переводит форму, КОТОРУЮ
        //    опознал, а не любую.
        let схема5 = Schema(versionedSchema: TogoSchemaV5.self)
        #expect(throws: (any Error).self) {
            _ = try ModelContainer(for: схема5,
                                   migrationPlan: TogoMigrationPlan.self,
                                   configurations: конфигурация(схема5, url))
        }

        // 3. Ради чего опыт: человек с августовской сборкой обязан увидеть
        //    «дневник не открылся» и дорогу к восстановлению, а не пустой
        //    дневник поверх своего целого.
        let контейнер = Persistence.openContainer(storeURL: url, allowCloud: false)
        #expect(контейнер == nil,
                "нужен StorageFailureScreen, а он показывается только при nil")
        #expect(Persistence.isEphemeral == false,
                "хранилище в памяти поверх непустого файла — подмена дневника пустым")

        // 4. И файл цел: из него человек и будет восстанавливаться.
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}

/// Снимок формы сборки 25: `TogoSchemaV1` минус двенадцать полей.
///
/// Номер версии тот же, что у V1, и это не опечатка: сборка 25 вышла
/// **до** появления плана миграции (21.09, сборка 46), а схема без
/// `VersionedSchema` записывает в хранилище версию по умолчанию —
/// `1.0.0`. То есть у базы сборки 25 тот же номер версии, что у V1,
/// и другая форма. Ровно этот случай SwiftData и зовёт «unknown model
/// version».
nonisolated enum TogoSchema25: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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
        var isPaused: Bool = false
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
