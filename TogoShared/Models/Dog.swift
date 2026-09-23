import Foundation
import SwiftData

@Model
final class Dog {
    /// Своё устойчивое имя.
    ///
    /// `persistentModelID` живёт только внутри одного хранилища: после
    /// восстановления из архива он другой. Выбранная собака должна
    /// переживать перенос на новый телефон, поэтому у неё свой ключ —
    /// как у всех остальных записей.
    var id: UUID = UUID()
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
    /// Чем кормят. Пишется из запаса корма — отдельно это поле не правят:
    /// иначе марка в профиле и марка на упаковке начинают расходиться.
    var foodBrand: String = ""
    /// Порция за раз. Хранится ради старых бэкапов и виджета; правильное
    /// значение здесь всегда `servingGrams` — его пишет `setDailyGrams`.
    /// Единственное настоящее число про количество еды — `dailyNormGrams`.
    var portionGrams: Int = 0
    var mealsPerDay: Int = 2
    var mealTimes: [Int] = [7 * 60 + 30, 18 * 60 + 30]   // минуты от полуночи

    /// Во сколько собака встаёт и ложится. Из этого окна раскладываются
    /// кормления и выходы: у одной семьи день начинается в шесть,
    /// у другой в девять, и общая таблица тут не работает.
    var wakeMinuteOfDay: Int = 7 * 60
    var sleepMinuteOfDay: Int = 23 * 60
    var forbiddenFoods: [String] = []

    /// Сколько собака съедает за сутки — единственное хранимое число
    /// про количество еды.
    ///
    /// Раньше их было два: «порция за раз» и «норма в день», и какое
    /// из них главное, решала ветка в `dailyGrams`. Из-за этого на одной
    /// карточке стояли рядом два числа, которые не сходились: поменять
    /// «грамм за раз» было можно, а «выходит в день» не двигалось.
    /// Осталось одно, а порция считается делением.
    ///
    /// Опциональность — след старой схемы: у собак, заведённых до этой
    /// правки, поле пустое, и его заполняет `FeedingMigration`.
    var dailyNormGrams: Int?

    /// Чем платим на занятиях. У каждой собаки своя иерархия.
    var rewards: [String] = []

    // MARK: Инструкция ситтеру
    //
    // Пять строк вместо истории болезни: еда, доза, прогулки, запреты,
    // эскалация. Пишет хозяйка один раз, ситтер только читает.
    // Диагноза здесь нет намеренно — ситтеру он не нужен, а лишнее
    // медицинское в чужих руках это лишний риск.
    var sitterFood: String = ""
    var sitterDose: String = ""
    var sitterWalks: String = ""
    var sitterForbidden: String = ""
    var sitterEscalation: String = ""
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

    /// Когда этот телефон в последний раз трогал профиль.
    ///
    /// Нужно для спора двух телефонов: вес и порцию правят оба, и решение
    /// Виктории от 23.09.2026 — **побеждает та правка, что позже**.
    /// У профиля нет поля, где «позже» было бы опасно: вес и порция —
    /// это факты, которые уточняют, а не мнения, которыми меняются.
    ///
    /// Ставится не на экранах, а в `FamilySync` при сохранении: профиль
    /// правят из полутора десятков мест прямыми привязками полей, и
    /// позвать «пометь изменённым» забудут ровно там, где это важнее.
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
    var daysOut: [DayOut] { daysOutStorage ?? [] }
    var heats: [HeatRecord] { heatsStorage ?? [] }
    var stocks: [FoodStock] { stocksStorage ?? [] }


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
        if months < 12 { return String(localized: "\(months) месяцев") }
        let years = months / 12
        let rest = months % 12
        let base = String(localized: "\(years) лет")
        return rest == 0 ? base : base + " " + String(localized: "\(rest) месяцев")
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
    /// Спрашивать можно с двух концов — кто-то знает норму с упаковки,
    /// кто-то отмеряет порцию за раз, — но храним всегда дневную.
    var dailyGrams: Int { dailyNormGrams ?? max(0, portionGrams * mealsPerDay) }

    /// Сколько класть в миску за раз: норма, поделённая на число кормлений.
    ///
    /// Округляем до пяти граммов — точнее на кухонных весах всё равно
    /// не отмерить, а число вроде «103 г» выглядит как требование.
    var servingGrams: Int {
        guard mealsPerDay > 0 else { return dailyGrams }
        return max(5, Int((Double(dailyGrams) / Double(mealsPerDay) / 5).rounded()) * 5)
    }

    /// Задать дневную норму. Порция пересчитывается сама.
    func setDailyGrams(_ grams: Int) {
        dailyNormGrams = max(0, grams)
        portionGrams = servingGrams
    }

    /// Задать порцию за раз — норма получается умножением.
    func setServingGrams(_ grams: Int) {
        setDailyGrams(max(0, grams) * max(1, mealsPerDay))
    }

    /// Держать расход единственного корма равным норме.
    ///
    /// Когда корм один, «сколько в день» у него — это и есть дневная норма,
    /// и отдельно её не спрашивают. Но норму можно поменять в режиме
    /// питания, и без этой синхронизации обратный отсчёт запаса продолжал
    /// бы считать по старой цифре — молча и незаметно.
    func syncSingleFoodShare() {
        guard stocks.count == 1 else { return }
        stocks[0].gramsPerDay = dailyGrams
    }

    /// Поменять число кормлений, не меняя, сколько собака съедает за сутки.
    ///
    /// Это и была самая обидная путаница: человек переводил щенка с двух
    /// кормлений на три, а приложение молча поднимало дневную еду
    /// в полтора раза — потому что хранило порцию, а не норму.
    func setMealsPerDay(_ count: Int) {
        let daily = dailyGrams
        mealsPerDay = max(1, count)
        setDailyGrams(daily)
    }

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

    var isWeightInRange: Bool {
        guard let low = targetWeightLow, let high = targetWeightHigh else { return true }
        return weightKg >= low && weightKg <= high
    }
}
