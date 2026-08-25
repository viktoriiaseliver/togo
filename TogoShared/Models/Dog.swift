import Foundation
import SwiftData

@Model
final class Dog {
    var name: String = ""
    var photo: Data?
    var breed: String?
    var birthDate: Date?
    var sexRaw: String = DogSex.unknown.rawValue
    /// Стерилизована или кастрирован. У стерилизованной течки нет,
    /// и календарь цикла ей не нужен.
    var isNeutered: Bool = false
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

    /// Во сколько собака встаёт и ложится. Из этого окна раскладываются
    /// кормления и выходы: у одной семьи день начинается в шесть,
    /// у другой в девять, и общая таблица тут не работает.
    var wakeMinuteOfDay: Int = 7 * 60
    var sleepMinuteOfDay: Int = 23 * 60
    var forbiddenFoods: [String] = []

    /// Дневная норма, если человек её знает. Часто её называет врач
    /// или пишет упаковка — тогда порция за раз считается из неё,
    /// а не наоборот.
    var dailyNormGrams: Int?

    /// Каким кормом кормят. Влажный и сухой по-разному фасуют и по-разному
    /// считают, поэтому вид корма — не украшение, а часть арифметики.
    var foodKindRaw: String = FoodKind.dry.rawValue

    /// Чем платим на занятиях. У каждой собаки своя иерархия.
    var rewards: [String] = []
    /// Корм на занятия берётся из дневной порции, а не сверх неё —
    /// поэтому лимита на лакомства в приложении нет.
    var trainingFoodFromPortion: Bool = true
    var markerKindRaw: String = MarkerKind.clicker.rawValue
    var sessionLengthMinutes: Int = 3

    /// Лечение включается в профиле и даёт вкладку «Здоровье».
    var isOnTreatment: Bool = false

    // MARK: Документы и экстренные контакты
    //
    // Всё это нужно ровно в двух случаях: у врача и когда собака потерялась.
    // Оба раза искать по ящикам некогда.

    var chipNumber: String?
    var passportNumber: String?
    var insuranceNumber: String?
    var vetName: String?
    var vetPhone: String?
    var clinicName: String?
    var clinicPhone: String?
    /// Приметы для объявления, если потерялась.
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

    @Relationship(deleteRule: .cascade, inverse: \HeatRecord.dog)
    var heatsStorage: [HeatRecord]?

    @Relationship(deleteRule: .cascade, inverse: \FoodStock.dog)
    var stocksStorage: [FoodStock]?

    @Relationship(deleteRule: .cascade, inverse: \FoodStock.dog)
    var foodStocksStorage: [FoodStock]?

    init(name: String, weightKg: Double) {
        self.name = name
        self.weightKg = weightKg
    }


    // CloudKit требует, чтобы все связи были опциональными: иначе хранилище
    // не открывается вовсе. Поэтому хранимое свойство — опциональный массив,
    // а наружу торчит обычный: остальному коду про это знать незачем.

    var events: [LogEvent] { eventsStorage ?? [] }
    var weights: [WeightEntry] { weightsStorage ?? [] }
    var careTasks: [CareTask] { careTasksStorage ?? [] }
    var medications: [Medication] { medicationsStorage ?? [] }
    var trainingSteps: [TrainingStep] { trainingStepsStorage ?? [] }
    var trainingSessions: [TrainingSession] { trainingSessionsStorage ?? [] }
    var trips: [Trip] { tripsStorage ?? [] }
    var documents: [DogDocument] { documentsStorage ?? [] }
    var heats: [HeatRecord] { heatsStorage ?? [] }
    var stocks: [FoodStock] { stocksStorage ?? [] }
    var foodStocks: [FoodStock] { foodStocksStorage ?? [] }

    var foodKind: FoodKind {
        get { FoodKind(rawValue: foodKindRaw) ?? .dry }
        set { foodKindRaw = newValue.rawValue }
    }

    var sex: DogSex {
        get { DogSex(rawValue: sexRaw) ?? .unknown }
        set { sexRaw = newValue.rawValue }
    }

    /// Календарь течки нужен только нестерилизованной девочке.
    var tracksHeat: Bool { sex == .female && !isNeutered }

    var markerKind: MarkerKind {
        get { MarkerKind(rawValue: markerKindRaw) ?? .clicker }
        set { markerKindRaw = newValue.rawValue }
    }

    var initial: String { String(name.prefix(1)).uppercased() }

    /// Возраст в месяцах. Нужен не для красоты: щенку до года и собаке
    /// старше семи подходят разные режимы кормления и нагрузки.
    var ageMonths: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.month], from: birthDate, to: .now).month
    }

    var ageDescription: String? {
        guard let months = ageMonths else { return nil }
        if months < 12 { return Fmt.plural(months, "месяц", "месяца", "месяцев") }
        let years = months / 12
        let rest = months % 12
        let base = Fmt.plural(years, "год", "года", "лет")
        return rest == 0 ? base : base + " " + Fmt.plural(rest, "месяц", "месяца", "месяцев")
    }

    enum LifeStage: String, Sendable {
        case puppy, adult, senior

        var title: String {
            switch self {
            case .puppy: "щенок"
            case .adult: "взрослая"
            case .senior: "пожилая"
            }
        }
    }

    /// Возрастные рамки грубые и намеренно такие: у мелких пород старость
    /// начинается позже, чем у крупных, и точную границу называет врач.
    var lifeStage: LifeStage? {
        guard let months = ageMonths else { return nil }
        if months < 12 { return .puppy }
        return months >= 7 * 12 ? .senior : .adult
    }

    /// Сколько собака съедает за сутки.
    ///
    /// Считать можно с двух концов, и оба встречаются одинаково часто:
    /// кто-то знает дневную норму с упаковки, кто-то отмеряет порцию за раз.
    /// Что человек ввёл, то и главное.
    var dailyGrams: Int { dailyNormGrams ?? (portionGrams * mealsPerDay) }

    /// Порция за раз, выведенная из дневной нормы.
    var derivedPortionGrams: Int {
        guard mealsPerDay > 0 else { return portionGrams }
        return max(1, Int((Double(dailyGrams) / Double(mealsPerDay) / 5).rounded()) * 5)
    }

    /// Норма задана дневная, а не по разу.
    var usesDailyNorm: Bool { dailyNormGrams != nil }

    /// Норма воды примерно 50 мл на килограмм — используется только как ориентир
    /// в поездке, где смена воды чаще всего даёт сбой.
    var waterNormMl: Int { Int((weightKg * 50).rounded()) }

    /// Сколько часов в сутках собака бодрствует. Меньше шести не бывает —
    /// это защита от опечатки, а не медицинская норма.
    var awakeMinutes: Int {
        let span = sleepMinuteOfDay - wakeMinuteOfDay
        return span > 0 ? span : span + 24 * 60
    }

    /// Кормления по суткам: ровный шаг, сокращённая ночь, последнее
    /// кормление с запасом до сна. Вся арифметика — в `MealSchedule`.
    func mealPlan(count: Int? = nil) -> MealSchedule.Plan {
        MealSchedule.plan(mealsPerDay: count ?? mealsPerDay,
                          wake: wakeMinuteOfDay,
                          sleep: sleepMinuteOfDay)
    }

    func evenMealTimes(count: Int? = nil) -> [Int] {
        mealPlan(count: count).times
    }

    /// Ночной перерыв при том расписании, которое стоит сейчас.
    var nightGapMinutes: Int {
        MealSchedule.nightGap(mealTimes.sorted())
    }

    var isWeightInRange: Bool {
        guard let low = targetWeightLow, let high = targetWeightHigh else { return true }
        return weightKg >= low && weightKg <= high
    }
}
