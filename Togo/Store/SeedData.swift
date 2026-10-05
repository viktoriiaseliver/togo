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

    /// Завести выбранные дела ухода.
    ///
    /// Один и тот же цикл стоял и в онбординге, и на экране ухода —
    /// вместе с деталью, о которой легко забыть: у дела «по дате»
    /// без даты нет срока, и оно не напомнит ни о чём. Забыть её в одной
    /// из копий значило бы завести напоминание, которое молчит.
    @MainActor
    @discardableResult
    static func addCare(_ chosen: Set<String>, to dog: Dog, context: ModelContext) -> Int {
        var added = 0
        for suggestion in careSuggestions where chosen.contains(suggestion.id) {
            let task = suggestion.makeTask()
            if task.kind == .dated {
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: 30, to: .now)
            }
            task.dog = dog
            context.insert(task)
            added += 1
        }
        // Не записалось — отвечаем нулём: иначе экран покажет
        // заведённые дела, которых в хранилище нет.
        if added > 0, !context.persist(otherwise: {}) { return 0 }
        return added
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

    /// Что лежит в демо-базе UI-тестов.
    ///
    /// Заведено 24.09.2026 ради одного состояния, которое **нечем было
    /// снять**: выходов нет дольше суток, а записи за сегодня есть.
    /// Именно его прислала кадром мама — шапка «Записей нет с 22 сент.»
    /// стояла над едой в 15:23. Демо-набор сюда не попадал никогда:
    /// в нём два выхода за сегодня, и ветка тишины не рисуется вовсе.
    ///
    /// Правило проекта: прежде чем проверять поверхность, проверь, что
    /// её МОЖНО проверить. Непроверяемое лечится входом, а не взглядом.
    enum Scenario: String {
        /// Обычный день: два выхода и завтрак.
        case today
        /// Выходов нет двое суток, еда за сегодня записана.
        case silence
        /// Дневник вели четыре дня и забросили восемнадцать дней назад.
        ///
        /// Заведён 05.10.2026 ради ступени, которую **не видел глазами
        /// никто ни на одной поверхности** — `.unknown(.silence)`
        /// у вердикта и «отметок мочи нет с …» на виджете. Починка
        /// 28.09 сняла оттуда «Не писал 434 ч. Это дольше, чем он
        /// когда-либо терпел», и проверена она была только арифметикой.
        ///
        /// **Почему отдельный сценарий, а не дни в `silence`.** Казалось
        /// бы, `silence` уже годится: выход там позавчера, `outcome`
        /// у него `.both`, а `.both` считается мочой
        /// (`Diary.urineEvents`) — то есть `signals.urineSilence`
        /// срабатывает. Но вердикта на экране не будет: событий
        /// в `silence` два, `daysOfData` даёт 3, `minimumDaysOfData`
        /// равен 4, и `guard` про нехватку данных стоит ВЫШЕ тишины.
        /// Экран честно отвечает «записей всего за 3 дня».
        ///
        /// Дописать дни в `silence` значило бы сдвинуть вердикт
        /// под живым UI-тестом `ТишинаДольшеСуток`, который снимает
        /// там шапку героя. Поэтому миры разные.
        case urineSilence

        /// Три смысла янтаря разом — и ни один из них до 05.10.2026
        /// не был достижим ни одним сценарием.
        ///
        /// **Как это нашлось.** togo-5a снял все 12 кадров (`rc` 0,
        /// `TEST SUCCEEDED`, 12 выполнено) и искал янтарь `#F7C75F`
        /// с допуском 20: **ноль попаданий на двенадцати кадрах**. Ноль
        /// из двенадцати — край диапазона, то есть симптом инструмента,
        /// пока не доказано обратное. Он это и проверил той же меркой,
        /// сменив только цель: лайм нашёлся на 10 кадрах из 12, от 5 896
        /// до 280 856 пикселей. Значит мерка работает, а янтаря нет
        /// в мире.
        ///
        /// Причина была в данных, не в навигации:
        ///
        /// - препарата с окном натощак в демо не было вовсе;
        /// - `ProcedureSkill` заводились без статуса, то есть
        ///   в `.notStarted`, а янтарь у `.learning`;
        /// - отметок с `MarkAccuracy.almost` не было ни одной.
        ///
        /// Виктория отдельным решением оставила янтарю все три смысла
        /// против требования хендоффа «янтарь только натощак» — то есть
        /// в коде защищено поведение, которого **никто ни разу
        /// не видел**. Это ровно тот класс, что карточка Live Activity,
        /// которую нельзя было построить вне живой активности: «состояние
        /// недостижимо, кадра нет» лечится входом, а «кадр не снят» —
        /// взглядом, и путать их дорого.
        ///
        /// Три состояния живут на разных экранах нарочно: «Сегодня»,
        /// «Уход» и дрессировка. На одном они столкнулись бы, а правило
        /// хендоффа «не больше одного мотива на экран» и здравый смысл
        /// требуют проверять их по отдельности.
        case amber
    }

    @MainActor
    static func makePreviewContainer(_ scenario: Scenario = .today) -> ModelContainer {
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
            calendar.date(minuteOfDay: hour * 60 + minute, on: startOfDay)
        }

        let события: [LogEvent]
        switch scenario {
        // Янтарь живёт поверх обычного дня: ступень янтаря — не особый
        // мир, а строка на нормальном экране, и проверять её надо
        // в нормальном окружении.
        case .today, .amber:
            let morning = LogEvent(kind: .outing, date: at(7, 2), authorName: "Виктория")
            morning.outcome = .urine
            let breakfast = LogEvent(kind: .meal, date: at(7, 34), authorName: "Виктория")
            breakfast.grams = 60
            breakfast.note = "съел всё"
            let second = LogEvent(kind: .outing, date: at(8, 15), authorName: "Тео")
            second.outcome = .both
            события = [morning, breakfast, second]

        case .silence:
            // Последний выход — позавчера вечером: больше суток, значит
            // герой уходит в ветку тишины. Еда — сегодня днём, ровно как
            // на кадре: именно она и делает шапку «записей нет» ложной.
            let позавчера = calendarNow.date(byAdding: .day, value: -2, to: at(18, 40)) ?? at(18, 40)
            let выход = LogEvent(kind: .outing, date: позавчера, authorName: "Виктория")
            выход.outcome = .both
            let обед = LogEvent(kind: .meal, date: at(15, 23), authorName: "Мама")
            обед.grams = 70
            события = [выход, обед]

        case .urineSilence:
            // Четыре дня нормального дневника — и восемнадцать дней
            // молчания. Четыре не из головы: `minimumDaysOfData`
            // равен четырём, и ниже этого вердикт отвечает «записей
            // мало», не доходя до тишины вовсе.
            //
            // Интервалы мочи нужны настоящие: без них вердикт уходит
            // в `.ambiguous` через `guard` про `typical`. Внутри дня
            // они часов по шесть, через ночь — по двенадцать, и все
            // шире окна `sameEmptyingWindow`, то есть в медиану попадут.
            func днейНазад(_ дней: Int, _ час: Int, _ минута: Int) -> Date {
                calendarNow.date(byAdding: .day, value: -дней, to: at(час, минута))
                    ?? at(час, минута)
            }
            func выход(_ дней: Int, _ час: Int, _ минута: Int,
                       _ исход: OutingOutcome, _ автор: String = "Виктория") -> LogEvent {
                let событие = LogEvent(kind: .outing, date: днейНазад(дней, час, минута),
                                       authorName: автор)
                событие.outcome = исход
                return событие
            }
            func еда(_ дней: Int, _ час: Int, _ минута: Int, _ граммов: Int) -> LogEvent {
                let событие = LogEvent(kind: .meal, date: днейНазад(дней, час, минута),
                                       authorName: "Виктория")
                событие.grams = граммов
                return событие
            }

            события = [
                выход(21, 7, 10, .urine), еда(21, 7, 40, 60),
                выход(21, 13, 20, .urine), выход(21, 19, 5, .both, "Тео"),
                выход(20, 7, 5, .both), еда(20, 7, 35, 60),
                выход(20, 14, 0, .urine), выход(20, 20, 10, .urine, "Тео"),
                выход(19, 7, 15, .urine), еда(19, 7, 45, 60),
                выход(19, 13, 40, .both), выход(19, 19, 30, .urine),
                // Последние отметки — и дальше тишина. Ровно та картина,
                // на которой приложение говорило «дольше, чем он
                // когда-либо терпел»: знает оно только, что никто
                // ничего не отмечал.
                выход(18, 7, 0, .urine), еда(18, 7, 30, 60),
            ]
        }

        for event in события {
            event.dog = dog
            context.insert(event)
        }

        if scenario == .amber {
            добавитьЯнтарь(to: dog, context: context)
        }

        return container
    }

    /// Три янтарных состояния — препарат натощак, навык «учится»,
    /// отметка «почти вовремя».
    ///
    /// Времена здесь считаются **от «сейчас»**, а не ставятся часами:
    /// окно натощак открыто ровно двадцать минут от момента запуска.
    /// Абсолютный час сделал бы кадр зелёным или красным в зависимости
    /// от того, когда его снимают, — то есть сторож работал бы
    /// по расписанию.
    @MainActor
    private static func добавитьЯнтарь(to dog: Dog, context: ModelContext) {
        // 1. Натощак. Окно считается от ОТМЕТКИ дозы
        //    (`FeedingGate`, `fastingMinutes`), поэтому дозу надо не просто
        //    назначить, а отметить данной: назначенная и не отмеченная
        //    окна не открывает вовсе.
        let левотироксин = Medication(name: "Левотироксин",
                                      doseText: "½ таблетки",
                                      times: [8 * 60, 20 * 60],
                                      fastingMinutes: 40)
        левотироксин.unit = .tab
        левотироксин.doseSlotsData = [DoseSlot(minuteOfDay: 8 * 60, quantity: 0.5),
                                      DoseSlot(minuteOfDay: 20 * 60, quantity: 1)]
        левотироксин.setStock(14)
        левотироксин.packAmount = 30
        левотироксин.stockTotal = 30
        левотироксин.dog = dog
        context.insert(левотироксин)

        let доза = DoseRecord(scheduledAt: Date.now.addingTimeInterval(-20 * 60))
        доза.givenAt = доза.scheduledAt
        доза.givenBy = "Виктория"
        доза.medication = левотироксин
        context.insert(доза)

        // 2. Навык «учится». Статус ставится явно: конструктор оставляет
        //    `.notStarted`, и демо-набор восемь месяцев не выходил
        //    из серого.
        let лапа = ProcedureSkill(title: "Дать лапу и не забирать",
                                  detail: "5 дней подряд · по 2 минуты")
        лапа.statusRaw = SkillStatus.learning.rawValue
        лапа.attempts = 7
        лапа.successes = 4
        context.insert(лапа)

        // 3. «Почти вовремя». `MarkAccuracy.from(delayMilliseconds:)`
        //    даёт `.almost` на 501–1000 мс; 640 и 870 — внутри, 420 —
        //    `.onTime`, чтобы на экране стояли обе ступени и янтарь
        //    было с чем сравнить.
        let занятие = TrainingSession(cue: "Лапу", place: "кухня",
                                      person: "Виктория", distanceMeters: 0)
        занятие.markDelaysMs = [420, 640, 870]
        занятие.attempts = 3
        занятие.successes = 2
        занятие.dog = dog
        context.insert(занятие)
    }
}
