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

        // Семнадцать полей, добавленных 07.10.2026. Все опциональные:
        // архивы, снятые раньше, этих ключей не знают и обязаны
        // читаться.
        //
        // **Это и есть медицинская карточка собаки, и архив её терял
        // целиком.** Номер чипа, номер паспорта, номер страховки,
        // врач и клиника с телефонами, приметы для объявления
        // о пропаже — всё то, что спрашивают в клинике и в полиции,
        // и всё то, что человек вводит один раз и больше никогда
        // не вспомнит.
        //
        // Пять полей листа ситтера — туда же: их пишут один раз,
        // и переустановка телефона стирала их без следа.
        //
        // `sexRaw` и `isNeutered` не косметика: от них зависит
        // календарь течки, то есть видит ли человек цикл вообще.
        var sexRaw: String?
        var isNeutered: Bool?
        var wakeMinuteOfDay: Int?
        var sleepMinuteOfDay: Int?
        var chipNumber: String?
        var passportNumber: String?
        var insuranceNumber: String?
        var vetName: String?
        var vetPhone: String?
        var clinicName: String?
        var clinicPhone: String?
        var distinctiveMarks: String?
        var sitterFood: String?
        var sitterDose: String?
        var sitterWalks: String?
        var sitterForbidden: String?
        var sitterEscalation: String?

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
        /// Выезды. Опциональность — не стиль: у файлов, сохранённых
        /// до 07.10.2026, этого поля нет, и прочитаться они обязаны.
        /// Та же причина, что у `stocks`, `heats` и `documents`.
        var daysOut: [DayOutSnapshot]?
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

    /// День с человеком: по делам, в дороге, в гостях.
    ///
    /// **Появился в архиве 07.10.2026, и до этого его не было вовсе.**
    /// `DayOut` живёт в приложении давно: `TodayScreen` читает выезды
    /// запросом и меняет по ним поведение главного экрана,
    /// а «Удалить все данные» про них знает. Не знал только перенос.
    ///
    /// Цена молчания: человек, переезжающий на новый телефон, терял все
    /// выезды — и узнать об этом ему было негде. Это не дефект показа,
    /// на который жалуются; это потеря данных, которую обнаруживают
    /// через месяц, если вообще.
    struct DayOutSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var plannedHours: Int
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
        // Добавлено 07.10.2026. Все опциональные: архивы, снятые раньше,
        // этих ключей не знают и обязаны читаться.
        //
        // **`scheduledDate` — это ДАТА ПРИВИВКИ**, и архив терял её
        // молча. Медкнижка собаки без дат прививок — не медкнижка:
        // ветеринару нужен именно день, а не «каждые 365 дней».
        var kindRaw: String?
        var scheduledDate: Date?
        var remindDaysBefore: Int?
        var streak: Int?
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
        // Добавлено 07.10.2026, тринадцать полей, все опциональные.
        //
        // **`unitRaw` — единица дозы.** Без неё «0,5» в восстановленной
        // схеме не значит ничего: половина таблетки, половина миллилитра
        // и половина капли — три разные дозы, и ошибка здесь это
        // не путаница в дневнике, а передозировка.
        //
        // `courseEnd`, `expiry`, `openedAt`, `shelfAfterOpenDays` —
        // срок курса и срок годности; `stock*`, `packAmount` — запас,
        // по которому считается «пора покупать». Всё это человек вводит
        // руками один раз, и восстановление возвращало ему пустые поля.
        var unitRaw: String?
        var minutesAfterMeal: Int?
        var dependsOnMeal: Bool?
        var doseSlots: [DoseSlot]?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int?
        var remindBeforeExpiry: Bool?
        var stockLeft: Int?
        var stockTotal: Int?
        var stockLeftAmount: Double?
        var packAmount: Double?
        var canGiveOutside: Bool?
    }

    struct DoseSnapshot: Codable, Sendable {
        var scheduledAt: Date
        var givenAt: Date?
        var givenBy: String?
        var cancelledAt: Date?
        var cancelReason: String?
        // Добавлено 07.10.2026, опциональные.
        //
        // **`skippedAt` и `skippedBy` — ПРОПУЩЕННАЯ доза**, и это факт
        // лечения, а не его отсутствие: врач спрашивает «сколько раз
        // пропустили», и архив отвечал «ни разу» вместо правды.
        // Отсутствие отметки и отметка «пропущено» — разные вещи,
        // и первая читается как «дали», пока вторая не восстановлена.
        var skippedAt: Date?
        var skippedBy: String?
        var claimedBy: String?
        var claimedAt: Date?
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
            String(localized: "\(dogs.count) собак"),
            String(localized: "\(events) записей"),
            String(localized: "\(members.count) человек"),
        ].joined(separator: " · ")
    }
}
