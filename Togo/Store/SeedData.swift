import Foundation
import SwiftData

/// Стартовые напоминания и демо-данные.
///
/// На первом запуске приложение не выдумывает записей за человека: оно ставит
/// только те повторяющиеся дела, которые есть у любой собаки, и то — с пустой
/// датой последнего раза, чтобы срок считался с сегодня.
enum SeedData {
    /// На первом запуске приложение не навязывает девять дел разом.
    /// Оно заводит только вес — и предлагает выбрать уход самому.
    static func attachStarterCare(to dog: Dog, context: ModelContext) {
        let weight = WeightEntry(kg: dog.weightKg)
        weight.dog = dog
        context.insert(weight)
    }

    /// Что можно предложить завести. Человек отмечает нужное — и только оно
    /// попадает в приложение. Интервалы здесь ориентировочные и правятся.
    struct CareSuggestion: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var detail: String
        var kind: CareKind
        var intervalDays: Int
        var category: CareCategory
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        /// Отмечено по умолчанию — то, что нужно почти всем.
        var isDefault: Bool = false

        func makeTask() -> CareTask {
            let task = CareTask(title: title, detail: detail, kind: kind,
                                intervalDays: intervalDays, category: category)
            task.seasonStartMonth = seasonStartMonth
            task.seasonEndMonth = seasonEndMonth
            return task
        }
    }

    static let careSuggestions: [CareSuggestion] = [
        // Каждый день
        CareSuggestion(title: "Зубы", detail: "чистить каждый день — налёт твердеет за сутки",
                       kind: .daily, intervalDays: 1, category: .grooming, isDefault: true),
        CareSuggestion(title: "Вычесать", detail: "каждый день в линьку, иначе пару раз в неделю",
                       kind: .daily, intervalDays: 1, category: .grooming),
        CareSuggestion(title: "Лапы после улицы", detail: "особенно зимой, где реагенты",
                       kind: .daily, intervalDays: 1, category: .grooming),
        CareSuggestion(title: "Глаза", detail: "протереть, если текут",
                       kind: .daily, intervalDays: 1, category: .grooming),

        // Регулярно
        CareSuggestion(title: "Когти", detail: "когда стучат по полу — уже пора",
                       kind: .periodic, intervalDays: 21, category: .grooming, isDefault: true),
        CareSuggestion(title: "Уши", detail: "осмотреть и почистить, если нужно",
                       kind: .periodic, intervalDays: 7, category: .grooming, isDefault: true),
        CareSuggestion(title: "Купать", detail: "чаще, чем раз в месяц, обычно не надо",
                       kind: .periodic, intervalDays: 60, category: .grooming),
        CareSuggestion(title: "Взвесить", detail: "видно раньше, чем на глаз",
                       kind: .periodic, intervalDays: 14, category: .medical, isDefault: true),
        CareSuggestion(title: "Антипаразитарка", detail: "от глистов, по назначению врача",
                       kind: .periodic, intervalDays: 90, category: .medical, isDefault: true),
        CareSuggestion(title: "Капли от клещей", detail: "в сезон, раз в месяц",
                       kind: .periodic, intervalDays: 30, category: .medical,
                       seasonStartMonth: 4, seasonEndMonth: 10, isDefault: true),

        // По дате
        CareSuggestion(title: "Прививка от бешенства", detail: "раз в год, нужна для поездок",
                       kind: .dated, intervalDays: 365, category: .medical, isDefault: true),
        CareSuggestion(title: "Комплексная прививка", detail: "раз в год",
                       kind: .dated, intervalDays: 365, category: .medical),
        CareSuggestion(title: "Осмотр у врача", detail: "раз в год, у пожилых чаще",
                       kind: .dated, intervalDays: 365, category: .medical),
        CareSuggestion(title: "Чистка зубов у врача", detail: "по показаниям",
                       kind: .dated, intervalDays: 365, category: .medical),
    ]

    /// Подготовка к процедурам — то, что приложение может предложить само,
    /// потому что уже знает про забор крови и поездку.
    static func procedureSkills() -> [ProcedureSkill] {
        [
            ProcedureSkill(title: "Дать лапу и не забирать", detail: "5 дней подряд · по 2 минуты"),
            ProcedureSkill(title: "Стоять при осмотре", detail: "спокойно 10 секунд"),
            ProcedureSkill(title: "Сам заходит в переноску", detail: "нужно к поездке"),
            ProcedureSkill(title: "Терпит намордник", detail: "пригодится у врача и в транспорте"),
        ]
    }

    /// Демо-набор для превью и UI-тестов. В обычный запуск не попадает.
    private static let calendarNow = Calendar.current

    @MainActor
    static func makePreviewContainer() -> ModelContainer {
        let container = Persistence.container()
        let context = container.mainContext

        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.breed = "Шипперке"
        dog.foodBrand = "Acana ягнёнок"
        dog.setServingGrams(60)
        dog.targetWeightLow = 4.0
        dog.targetWeightHigh = 4.3
        dog.rewards = ["сыр", "индейка", "мячик"]
        dog.forbiddenFoods = ["курица", "кукуруза"]
        context.insert(dog)
        attachStarterCare(to: dog, context: context)

        for suggestion in careSuggestions.filter(\.isDefault) {
            let task = suggestion.makeTask()
            if task.kind == .periodic {
                task.lastDone = calendarNow.date(byAdding: .day, value: -task.intervalDays / 2, to: .now)
            }
            if task.kind == .dated {
                task.scheduledDate = calendarNow.date(byAdding: .day, value: 40, to: .now)
            }
            task.dog = dog
            context.insert(task)
        }

        let me = FamilyMember(name: "Виктория", role: .owner, isMe: true)
        let teo = FamilyMember(name: "Тео", role: .coOwner)
        teo.isOnDuty = true
        teo.dutyUntil = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: .now)
        [me, teo,
         FamilyMember(name: "Мама", role: .caregiver),
         FamilyMember(name: "Лея", role: .helper),
         FamilyMember(name: "Dr. Ferrand", role: .observer)].forEach(context.insert)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int) -> Date {
            startOfDay.addingTimeInterval(Double(hour * 60 + minute) * 60)
        }

        let morning = LogEvent(kind: .outing, date: at(7, 2), authorName: "Виктория")
        morning.outcome = .urine
        let breakfast = LogEvent(kind: .meal, date: at(7, 34), authorName: "Виктория")
        breakfast.grams = 60
        breakfast.note = "съел всё"
        let second = LogEvent(kind: .outing, date: at(8, 15), authorName: "Тео")
        second.outcome = .both
        for event in [morning, breakfast, second] {
            event.dog = dog
            context.insert(event)
        }

        return container
    }
}
