import Foundation
import SwiftData

/// Стартовые напоминания и демо-данные.
///
/// На первом запуске приложение не выдумывает записей за человека: оно ставит
/// только те повторяющиеся дела, которые есть у любой собаки, и то — с пустой
/// датой последнего раза, чтобы срок считался с сегодня.
enum SeedData {
    static func attachStarterCare(to dog: Dog, context: ModelContext) {
        for task in starterCareTasks() {
            task.dog = dog
            context.insert(task)
        }
        let weight = WeightEntry(kg: dog.weightKg)
        weight.dog = dog
        context.insert(weight)
    }

    static func starterCareTasks() -> [CareTask] {
        let grooming: [(String, String, Int)] = [
            ("Вычесать", "2 раза в неделю · в линьку каждый день", 3),
            ("Когти", "каждые 3 недели", 21),
            ("Купать", "раз в 2 месяца", 60),
            ("Уши и зубы", "раз в неделю", 7),
        ]
        let medical: [(String, String, Int, Int?, Int?)] = [
            ("Антипаразитарка", "раз в месяц", 30, nil, nil),
            ("Капли от клещей", "раз в 4 недели", 28, 4, 10),
            ("Бешенство", "раз в год · нужна для поездок", 365, nil, nil),
            ("Комплексная", "раз в год", 365, nil, nil),
            ("Взвесить", "раз в две недели", 14, nil, nil),
        ]

        var tasks = grooming.map { CareTask(title: $0.0, detail: $0.1, intervalDays: $0.2, category: .grooming) }
        tasks += medical.map { title, detail, days, seasonStart, seasonEnd in
            let task = CareTask(title: title, detail: detail, intervalDays: days, category: .medical)
            task.seasonStartMonth = seasonStart
            task.seasonEndMonth = seasonEnd
            return task
        }
        return tasks
    }

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
    @MainActor
    static func makePreviewContainer() -> ModelContainer {
        let container = Persistence.container(inMemory: true)
        let context = container.mainContext

        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.breed = "Шипперке"
        dog.foodBrand = "Acana ягнёнок"
        dog.portionGrams = 60
        dog.targetWeightLow = 4.0
        dog.targetWeightHigh = 4.3
        dog.rewards = ["сыр", "индейка", "мячик"]
        dog.forbiddenFoods = ["курица", "кукуруза"]
        context.insert(dog)
        attachStarterCare(to: dog, context: context)

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
