import Foundation
import SwiftData

@Model
final class Dog {
    var name: String = ""
    var photo: Data?
    var breed: String?
    var birthDate: Date?
    var weightKg: Double = 0

    /// Коридор веса называет врач. Приложение не считает норму само
    /// и не ставит целей по проценту.
    var targetWeightLow: Double?
    var targetWeightHigh: Double?

    // Питание
    var foodBrand: String = ""
    var portionGrams: Int = 0
    var mealsPerDay: Int = 2
    var mealTimes: [Int] = [7 * 60 + 30, 18 * 60 + 30]   // минуты от полуночи
    var forbiddenFoods: [String] = []

    /// Чем платим на занятиях. У каждой собаки своя иерархия.
    var rewards: [String] = []
    /// Корм на занятия берётся из дневной порции, а не сверх неё —
    /// поэтому лимита на лакомства в приложении нет.
    var trainingFoodFromPortion: Bool = true
    var markerKindRaw: String = MarkerKind.clicker.rawValue
    var sessionLengthMinutes: Int = 3

    /// Лечение включается в профиле и даёт вкладку «Здоровье».
    var isOnTreatment: Bool = false

    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \LogEvent.dog)
    var events: [LogEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.dog)
    var weights: [WeightEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \CareTask.dog)
    var careTasks: [CareTask] = []

    @Relationship(deleteRule: .cascade, inverse: \Medication.dog)
    var medications: [Medication] = []

    @Relationship(deleteRule: .cascade, inverse: \TrainingStep.dog)
    var trainingSteps: [TrainingStep] = []

    @Relationship(deleteRule: .cascade, inverse: \TrainingSession.dog)
    var trainingSessions: [TrainingSession] = []

    @Relationship(deleteRule: .cascade, inverse: \Trip.dog)
    var trips: [Trip] = []

    init(name: String, weightKg: Double) {
        self.name = name
        self.weightKg = weightKg
    }

    var markerKind: MarkerKind {
        get { MarkerKind(rawValue: markerKindRaw) ?? .clicker }
        set { markerKindRaw = newValue.rawValue }
    }

    var initial: String { String(name.prefix(1)).uppercased() }

    var dailyGrams: Int { portionGrams * mealsPerDay }

    /// Норма воды примерно 50 мл на килограмм — используется только как ориентир
    /// в поездке, где смена воды чаще всего даёт сбой.
    var waterNormMl: Int { Int((weightKg * 50).rounded()) }

    var isWeightInRange: Bool {
        guard let low = targetWeightLow, let high = targetWeightHigh else { return true }
        return weightKg >= low && weightKg <= high
    }
}
