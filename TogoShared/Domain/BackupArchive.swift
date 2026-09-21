import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Полный слепок дневника: то, что переживает переустановку и переезд
/// на новый телефон.
///
/// Формат намеренно простой — плоский JSON с версией. Его можно открыть
/// текстовым редактором и увидеть, что именно уезжает: приложение,
/// которое хранит здоровье собаки, не имеет права быть чёрным ящиком.
nonisolated struct BackupArchive: Codable, Sendable {
    /// Версия формата. Читатель обязан проверить её первой строкой.
    var formatVersion: Int = 1
    var createdAt: Date
    var appVersion: String

    var dogs: [DogSnapshot]
    var members: [MemberSnapshot]
    var episodes: [EpisodeSnapshot]

    struct DogSnapshot: Codable, Sendable {
        var name: String
        var photo: Data?
        var breed: String?
        var birthDate: Date?
        var weightKg: Double
        var targetWeightLow: Double?
        var targetWeightHigh: Double?
        var foodBrand: String
        var portionGrams: Int
        var mealsPerDay: Int
        var mealTimes: [Int]
        var forbiddenFoods: [String]
        var dailyNormGrams: Int?
        var rewards: [String]
        var trainingFoodFromPortion: Bool
        var markerKindRaw: String
        var sessionLengthMinutes: Int
        var isOnTreatment: Bool
        var createdAt: Date

        var events: [EventSnapshot]
        var weights: [WeightSnapshot]
        var careTasks: [CareTaskSnapshot]
        var medications: [MedicationSnapshot]
        var trainingSteps: [TrainingStepSnapshot]
        var trainingSessions: [TrainingSessionSnapshot]
        var trips: [TripSnapshot]
        /// Появилось позже — у старых файлов этого поля нет.
        var stocks: [StockSnapshot]?
        var heats: [HeatSnapshot]?
        /// Снимки документов. Тоже позже: экрана у них не было вовсе,
        /// а значит, и сохранять было нечего.
        var documents: [DocumentSnapshot]?
    }

    /// Фотография документа целиком: паспорт, потерянный вместе
    /// с телефоном, восстанавливать неоткуда.
    struct DocumentSnapshot: Codable, Sendable {
        var title: String
        var image: Data?
        var addedAt: Date
        var note: String?
    }

    struct StockSnapshot: Codable, Sendable {
        var kindRaw: String
        var brand: String
        var packGrams: Int
        var packsLeft: Double
        var gramsPerDay: Int
        var openedAt: Date?
    }

    struct HeatSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var note: String?
    }

    struct EventSnapshot: Codable, Sendable {
        var id: UUID
        var date: Date
        var kindRaw: String
        var authorName: String
        var isSynced: Bool
        var note: String?
        var outcomeRaw: String?
        var askSignalRaw: String?
        var durationSeconds: Int?
        var stoolFormRaw: String?
        var stoolFlagsRaw: [String]
        var grams: Int?
        var milliliters: Int?
        var fromPortion: Bool
        var incidentKindRaw: String?
        var incidentDetailRaw: String?
        var toldFamily: Bool
        var deletedAt: Date?
        var deletedBy: String?
    }

    struct WeightSnapshot: Codable, Sendable {
        var date: Date
        var kg: Double
    }

    struct CareTaskSnapshot: Codable, Sendable {
        var title: String
        var detail: String
        var intervalDays: Int
        var lastDone: Date?
        var categoryRaw: String
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int
    }

    struct MedicationSnapshot: Codable, Sendable {
        var name: String
        var doseText: String
        var times: [Int]
        var fastingMinutes: Int
        /// Окно натощак ПЕРЕД дозой. Необязательное: архивы, снятые
        /// до появления поля, читаются как прежде, и при восстановлении
        /// окно «до» берётся симметричным — так же, как у схемы,
        /// которая его не заполняла. Терять половину правила молча
        /// нельзя: это лечение.
        var fastingBeforeMinutes: Int?
        var isPaused: Bool
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var doses: [DoseSnapshot]
    }

    struct DoseSnapshot: Codable, Sendable {
        var scheduledAt: Date
        var givenAt: Date?
        var givenBy: String?
        var cancelledAt: Date?
        var cancelReason: String?
    }

    struct TrainingStepSnapshot: Codable, Sendable {
        var cue: String
        var place: String
        var person: String
        var distanceMeters: Int
        var statusRaw: String
        var consecutiveGoodSessions: Int
        var order: Int
    }

    struct TrainingSessionSnapshot: Codable, Sendable {
        var startedAt: Date
        var durationSeconds: Int
        var cue: String
        var place: String
        var person: String
        var distanceMeters: Int
        var markDelaysMs: [Int]
        var successes: Int
        var attempts: Int
        var gramsUsed: Int
        var observationsRaw: [String]
        var countsTowardProgress: Bool
    }

    struct TripSnapshot: Codable, Sendable {
        var destination: String
        var startDate: Date
        var endDate: Date
        var transportRaw: String
        var travelHours: Double
        var lodging: String
        var participants: [String]
        var departureMinuteOfDay: Int
        var packedItems: [String]
    }

    struct MemberSnapshot: Codable, Sendable {
        var name: String
        var roleRaw: String
        var note: String?
        var isMe: Bool
        var customPermissionsRaw: [String]?
        var isOnDuty: Bool
        var dutyUntil: Date?
        var accessExpiresAt: Date?
        var acceptedAt: Date?
    }

    struct EpisodeSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var title: String
        var detail: String
    }

    /// Коротко для экрана: что именно уедет в файл.
    var summary: String {
        let events = dogs.reduce(0) { $0 + $1.events.count }
        return [
            Fmt.plural(dogs.count, "собака", "собаки", "собак"),
            Fmt.plural(events, "запись", "записи", "записей"),
            Fmt.plural(members.count, "человек", "человека", "человек"),
        ].joined(separator: " · ")
    }
}
