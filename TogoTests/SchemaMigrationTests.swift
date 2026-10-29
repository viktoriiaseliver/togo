import Testing
import Foundation
import SwiftData
@testable import Togo

/// Единственная проверка, которая отличает план миграции от обещания.
///
/// План можно написать и не заметить, что он ничего не делает: версии
/// в нём могут ссылаться на те же классы, что и нынешняя схема, — тогда
/// все три версии одинаковы, стадии пустые, а старое хранилище
/// по-прежнему не открывается. Поэтому здесь не «план существует»,
/// а честный круг: завести базу прежней формы, положить в неё записи,
/// открыть нынешней схемой и пересчитать всё, что положили.
///
/// **Почему это важнее обычных тестов.** Остальные наборы работают
/// с хранилищем в памяти — оно каждый раз новое и про переход между
/// версиями не говорит ничего. Ровно поэтому прогон на чистом
/// симуляторе был зелёным в тот вечер, когда на симуляторе с данными
/// падало сохранение.
@Suite("Миграция хранилища", .serialized)
@MainActor
struct SchemaMigrationTests {

    // MARK: Хранилище на диске

    /// Своя база на каждую проверку: миграция — операция над файлом,
    /// и соседний тест не должен на неё влиять.
    private func заводимПапку() throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "togo-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Togo.store")
    }

    private func убираем(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func конфигурация(_ schema: Schema, _ url: URL) -> ModelConfiguration {
        // CloudKit выключен явно: миграцию проверяем саму по себе,
        // зеркало в облако добавило бы к ней чужие отказы.
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }

    /// Открыть нынешней схемой — тем же способом, каким это делает
    /// приложение в `Persistence`.
    private func открываемНынешней(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: Persistence.schema,
                           migrationPlan: TogoMigrationPlan.self,
                           configurations: конфигурация(Persistence.schema, url))
    }

    // MARK: Сборка 36 → сейчас

    @Test("Хранилище сборки 36 открывается нынешней схемой и ничего не теряет")
    func изСборки36() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        let когда = Date(timeIntervalSince1970: 1_756_000_000)

        // 1. База ровно той формы, что уехала тестировщикам.
        do {
            let схема = Schema(versionedSchema: TogoSchemaV1.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)

            let собака = TogoSchemaV1.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            собака.breed = "Шипперке"
            собака.dailyNormGrams = 120
            собака.rewards = ["сыр", "индейка"]
            собака.isOnTreatment = true
            context.insert(собака)

            let выход = TogoSchemaV1.LogEvent()
            выход.kindRaw = LogKind.outing.rawValue
            выход.date = когда
            выход.authorName = "Виктория"
            выход.outcomeRaw = OutingOutcome.both.rawValue
            выход.dog = собака
            context.insert(выход)

            let еда = TogoSchemaV1.LogEvent()
            еда.kindRaw = LogKind.meal.rawValue
            еда.date = когда.addingTimeInterval(3600)
            еда.authorName = "Тео"
            еда.grams = 60
            еда.dog = собака
            context.insert(еда)

            let схемаЛечения = TogoSchemaV1.Medication()
            схемаЛечения.name = "Lévothyrox"
            схемаЛечения.doseText = "66 мкг"
            схемаЛечения.times = [7 * 60, 19 * 60]
            схемаЛечения.fastingMinutes = 45
            схемаЛечения.dog = собака
            context.insert(схемаЛечения)

            let доза = TogoSchemaV1.DoseRecord()
            доза.scheduledAt = когда
            доза.givenAt = когда.addingTimeInterval(60)
            доза.givenBy = "Виктория"
            доза.medication = схемаЛечения
            context.insert(доза)

            let уход = TogoSchemaV1.CareTask()
            уход.title = "Когти"
            уход.intervalDays = 21
            уход.dog = собака
            context.insert(уход)

            let запас = TogoSchemaV1.FoodStock()
            запас.brand = "Acana"
            запас.packGrams = 3000
            запас.packsLeft = 0.5
            запас.gramsPerDay = 120
            запас.dog = собака
            context.insert(запас)

            let мама = TogoSchemaV1.FamilyMember()
            мама.name = "Мама"
            мама.roleRaw = FamilyRole.caregiver.rawValue
            context.insert(мама)

            try context.save()
        }

        // 2. Та же база нынешней схемой и планом.
        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, "собака должна пережить переход")
        let собака = try #require(собаки.first)
        #expect(собака.name == "Стич")
        #expect(собака.weightKg == 4.1)
        #expect(собака.breed == "Шипперке")
        #expect(собака.dailyNormGrams == 120, "опциональное число не должно обнулиться")
        #expect(собака.rewards == ["сыр", "индейка"], "массив строк переживает переход")
        #expect(собака.isOnTreatment)

        let записи = try context.fetch(FetchDescriptor<LogEvent>())
        #expect(записи.count == 2, "обе записи ленты на месте")
        #expect(Set(записи.map(\.kindRaw)) == [LogKind.outing.rawValue, LogKind.meal.rawValue])
        let выход = try #require(записи.first { $0.kind == .outing })
        #expect(выход.date == когда, "время записи не сдвинулось")
        #expect(выход.authorName == "Виктория")
        #expect(выход.outcome == .both)
        #expect(записи.first { $0.kind == .meal }?.grams == 60)

        // Связь — не украшение: без неё лента у собаки окажется пустой,
        // хотя записи в базе есть.
        #expect(собака.events.count == 2, "связь собака → записи пережила переход")
        #expect(собака.medications.count == 1)
        #expect(собака.careTasks.count == 1)
        #expect(собака.stocks.count == 1)

        let схемаЛечения = try #require(собака.medications.first)
        #expect(схемаЛечения.name == "Lévothyrox")
        #expect(схемаЛечения.times == [7 * 60, 19 * 60])
        #expect(схемаЛечения.fastingMinutes == 45)
        #expect(схемаЛечения.doses.count == 1, "связь лечение → дозы пережила переход")
        #expect(схемаЛечения.doses.first?.isGiven == true)

        #expect(try context.fetch(FetchDescriptor<FamilyMember>()).count == 1)

        // 3. Новые поля у старых записей — со значением по умолчанию,
        //    а не мусором.
        #expect(выход.enteredAt == nil, "у записи из сборки 36 момента внесения нет")
        #expect(выход.origin == .logged)
        #expect(!выход.isDayOnly)
        #expect(схемаЛечения.fastingBeforeMinutes == 0)

        // 4. Правило чтения для старых схем: окно «до» равно окну «после».
        //    Оно живёт в `fastingBefore`, а не в данных, — и после миграции
        //    обязано продолжать работать.
        #expect(схемаЛечения.fastingBefore == 45,
                "у схемы из сборки 36 окно натощак «до» читается как окно «после»")
    }

    // MARK: Сборка 46 → сейчас

    @Test("Хранилище сборки 46 открывается нынешней схемой и ничего не теряет")
    func изСборки46() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        let когда = Date(timeIntervalSince1970: 1_757_000_000)
        let внесли = когда.addingTimeInterval(86_400)

        do {
            let схема = Schema(versionedSchema: TogoSchemaV2.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)

            let собака = TogoSchemaV2.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            context.insert(собака)

            // Три поля, которых в сборке 36 ещё не было: они должны
            // не появиться заново, а доехать со значениями.
            let поПамяти = TogoSchemaV2.LogEvent()
            поПамяти.kindRaw = LogKind.dose.rawValue
            поПамяти.date = когда
            поПамяти.authorName = "Виктория"
            поПамяти.enteredAt = внесли
            поПамяти.originRaw = RecordOrigin.recalled.rawValue
            поПамяти.isDayOnly = true
            поПамяти.dog = собака
            context.insert(поПамяти)

            let схемаЛечения = TogoSchemaV2.Medication()
            схемаЛечения.name = "Lévothyrox"
            схемаЛечения.fastingMinutes = 45
            схемаЛечения.dog = собака
            context.insert(схемаЛечения)

            try context.save()
        }

        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)

        let запись = try #require(try context.fetch(FetchDescriptor<LogEvent>()).first)
        #expect(запись.kind == .dose)
        #expect(запись.date == когда)
        #expect(запись.enteredAt == внесли, "момент внесения не должен потеряться")
        #expect(запись.origin == .recalled, "происхождение записи не должно потеряться")
        #expect(запись.isRecalled)
        #expect(запись.isDayOnly, "«известен только день» не должно потеряться")
        #expect(запись.dog?.name == "Стич")

        let схемаЛечения = try #require(try context.fetch(FetchDescriptor<Medication>()).first)
        #expect(схемаЛечения.fastingMinutes == 45)
        #expect(схемаЛечения.fastingBeforeMinutes == 0, "новое поле приходит со своим нулём")
        #expect(схемаЛечения.fastingBefore == 45)
    }

    // MARK: После перехода в базу можно писать

    @Test("После перехода запись сохраняется — то самое, что падало")
    func записьПослеПерехода() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        do {
            let схема = Schema(versionedSchema: TogoSchemaV1.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)
            let собака = TogoSchemaV1.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            context.insert(собака)
            try context.save()
        }

        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)
        let собака = try #require(try context.fetch(FetchDescriptor<Dog>()).first)

        // Ровно тот шаг, который на симуляторе с данными падал
        // в `NSManagedObjectContext.save`: новое поле в старой базе.
        let схемаЛечения = Medication(name: "Lévothyrox", doseText: "66 мкг",
                                      times: [7 * 60], fastingMinutes: 45)
        схемаЛечения.fastingBeforeMinutes = 30
        схемаЛечения.dog = собака
        context.insert(схемаЛечения)

        let запись = LogEvent(kind: .dose, authorName: "Виктория")
        запись.isDayOnly = true
        запись.dog = собака
        context.insert(запись)

        // Не `try?`: молчаливый отказ здесь и есть проверяемая беда.
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Medication>()).first?.fastingBeforeMinutes == 30)
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).first?.isDayOnly == true)
    }

    @Test("Второе открытие уже переведённой базы ничего не ломает")
    func переходИдемпотентен() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        do {
            let схема = Schema(versionedSchema: TogoSchemaV1.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)
            let собака = TogoSchemaV1.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            context.insert(собака)
            try context.save()
        }

        do {
            let контейнер = try открываемНынешней(url)
            #expect(try ModelContext(контейнер).fetch(FetchDescriptor<Dog>()).count == 1)
        }

        let контейнер = try открываемНынешней(url)
        #expect(try ModelContext(контейнер).fetch(FetchDescriptor<Dog>()).count == 1,
                "переведённая база открывается тем же планом ещё раз")
    }

    // MARK: Сторож: версии не должны оказаться копиями нынешней

    @Test("V1 и V2 — настоящие снимки, а не ссылки на нынешнюю схему")
    func версииОтличаются() {
        func поля(_ версия: any VersionedSchema.Type, _ сущность: String) -> Set<String> {
            let схема = Schema(versionedSchema: версия)
            return Set((схема.entitiesByName[сущность]?.properties ?? []).map(\.name))
        }

        let v1Записи = поля(TogoSchemaV1.self, "LogEvent")
        let v2Записи = поля(TogoSchemaV2.self, "LogEvent")
        let v4Записи = поля(TogoSchemaV4.self, "LogEvent")

        // Ровно три поля появились в сборке 46 — коммит 4081a47.
        #expect(v2Записи.subtracting(v1Записи) == ["enteredAt", "originRaw", "isDayOnly"])
        #expect(v1Записи.subtracting(v2Записи).isEmpty, "в сборке 46 ничего не удалено")
        #expect(v4Записи == v2Записи, "после сборки 46 лента не менялась")

        // Ровно одно поле появилось в сборке 141 — коммит de07bda.
        let v2Лечение = поля(TogoSchemaV2.self, "Medication")
        let v3Лечение = поля(TogoSchemaV3.self, "Medication")
        #expect(v3Лечение.subtracting(v2Лечение) == ["fastingBeforeMinutes"])
        #expect(v2Лечение.subtracting(v3Лечение).isEmpty, "ничего не удалено")

        // И ровно одно — в нынешней, ради общего дневника: у спора
        // двух телефонов о схеме должно быть чем разрешаться.
        let v4Лечение = поля(TogoSchemaV4.self, "Medication")
        #expect(v4Лечение.subtracting(v3Лечение) == ["changedAt"])
        #expect(v3Лечение.subtracting(v4Лечение).isEmpty, "ничего не удалено")

        // Доза помнит, чего ждёт, когда схема ещё не приехала.
        let v4Доза = поля(TogoSchemaV4.self, "DoseRecord")
        #expect(v4Доза.subtracting(поля(TogoSchemaV3.self, "DoseRecord"))
                == ["awaitedMedicationID", "awaitedMedicationName"])

        // Набор сущностей тот же во всех трёх — значит ни одной модели
        // не завели и не убрали, и стадии правда лёгкие.
        let имена = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }
        #expect(имена(TogoSchemaV1.self) == имена(TogoSchemaV4.self))
        #expect(имена(TogoSchemaV2.self) == имена(TogoSchemaV4.self))
        #expect(имена(TogoSchemaV4.self).count == 16)
    }

    /// Что именно V5 добавила к V4 — **списком, а не числом**, и ничего
    /// не удалила.
    ///
    /// **Записано поимённо нарочно.** Число полей сходится и при
    /// перепутанных местах: заведи «срок после вскрытия» вместо «годен
    /// до» — счётчик промолчит, а человек с открытым флаконом увидит
    /// не тот срок. Имя поля ловит это, число — нет.
    ///
    /// # Переписан 07.10.2026, и прежняя редакция была неверна по смыслу
    ///
    /// Он назывался «V5 заводит тринадцать полей под экраны хендоффа»
    /// и требовал, чтобы **набор сущностей V5 совпадал с V4**, а кроме
    /// `Medication`, `FoodStock` и `LogEvent` не менялось ничего.
    /// В тот день это было правдой. К вечеру V5 выросла на пять
    /// сущностей и ещё одиннадцать полей — законно, решением Виктории
    /// и шагом 0 медслоя, — и сторож покраснел **на честном росте**.
    ///
    /// Это второй раз за день, когда утверждение «ровно столько»
    /// ломается о законный рост: утром так же пришлось переписать
    /// «во всех версиях ровно шестнадцать сущностей».
    ///
    /// > **Утверждение «ровно столько» стареет при каждом росте,
    /// > а утверждение «не убыло, и прирост назван» — не стареет
    /// > никогда.**
    ///
    /// И имя теста было вторым утверждением, стареющим молча: «заводит
    /// тринадцать полей» читали ВМЕСТО кода. У нас это уже стоило
    /// пяти дней чужой истории на Gamut.
    @Test("V5 только добавляет к V4, и каждое добавление названо по имени")
    func пятаяВерсияТолькоДобавляет() {
        func поля(_ версия: any VersionedSchema.Type, _ сущность: String) -> Set<String> {
            let схема = Schema(versionedSchema: версия)
            return Set((схема.entitiesByName[сущность]?.properties ?? []).map(\.name))
        }
        let сущности = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }

        // Прирост по именам: сущность → что у неё появилось.
        // Пустое множество значит «не менялась ни одним полем».
        let приростПолей: [String: Set<String>] = [
            // Десять полей хендоффа + номер назначения (шаг 0 медслоя).
            // Плюс `massPerUnitMcg` — числовая доза, `43f05a5` (08.10.2026).
            // Причина взята у автора прироста, а не придумана здесь:
            // счёт таблеток отвечал не на тот вопрос. Врач меняет силу
            // таблетки с 0,05 на 0,1 мг — счёт остаётся «2», столбик
            // не шевельнётся, а доза выросла вдвое. Масса хранится
            // В ОДНОЙ единице (микрограммы) и НА ЕДИНИЦУ ФОРМЫ: пара
            // «значение + единица» позволила бы сложить 0,1 мг с 50 мкг
            // и получить 50,1. Снос базы разрешён её словом 08.10.2026
            // под этот случай.
            // **НАДГРОБИЙ ЗДЕСЬ НЕТ, и это замер, а не упущение.**
            // `deletedAt` у одиннадцати типов пришёл 26.10.2026
            // коммитом `f546719` — то есть ПОСЛЕ того, как V5 уехала
            // пятью сборками. Он живёт в V6, и сверяет его
            // `шестаяВерсияДобавляетОдниНадгробия` ниже.
            //
            // Записать его сюда значило бы сказать, что форма 304,
            // лежащая на пяти телефонах, содержала надгробия. Она
            // их не содержала — ровно поэтому приложение и не
            // открылось.
            "Medication": ["unitRaw", "doseSlotsData", "stockLeftAmount", "packAmount",
                           "courseEnd", "expiry", "openedAt", "shelfAfterOpenDays",
                           "remindBeforeExpiry", "canGiveOutside",
                           "prescriptionNumber", "massPerUnitMcg"],
            "FoodStock": ["expiry", "shelfAfterOpenDays"],
            "LogEvent": ["editedBy"],
            // Шаг 0 медслоя, 07.10.2026: прививка получила партию, срок
            // и клинику; документ — тип, номер, кем выдан и срок.
            "CareTask": ["vaccineBatch", "vaccineValidUntil", "clinic"],
            "DogDocument": ["kindRaw", "number", "issuedBy", "validUntil", "changedAt"],
            // Обратные стороны связей к четырём медицинским сущностям.
            // Без них хранилище не открывается вовсе — зеркало CloudKit
            // требует обратной у каждой связи.
            "Dog": ["labResultsStorage", "vetVisitsStorage",
                    "diagnosesStorage", "prescriptionsStorage"],
            // Обмен взвешиваний, 07.10.2026 вечером. Спор двух
            // телефонов решать было нечем: `date` — день, когда
            // взвесили, а не когда правили запись.
            "WeightEntry": ["changedAt"],
        ]

        // Прирост сущностей — тоже по именам.
        let новыеСущности: Set<String> = [
            "Clinic",                                        // шаг 0
            "LabResult", "VetVisit", "Diagnosis", "Prescription",  // медслой
        ]

        // 1. Ничего не убыло — ни сущности, ни поля. Это и есть
        //    основание назвать стадию облегчённой: удаление поля CoreData
        //    сам не выводит, а шесть розданных сборок несут V4.
        #expect(сущности(TogoSchemaV4.self).subtracting(сущности(TogoSchemaV5.self)).isEmpty, """
            из V5 исчезла сущность, которая была в V4. Это НЕ та
            миграция, которую CoreData выводит сам.
            """)
        for сущность in сущности(TogoSchemaV4.self).sorted() {
            let убыло = поля(TogoSchemaV4.self, сущность)
                .subtracting(поля(TogoSchemaV5.self, сущность))
            #expect(убыло.isEmpty, "из `\(сущность)` исчезло: \(убыло.sorted())")
        }

        // 2. Прирост сущностей — ровно названный.
        let приросло = сущности(TogoSchemaV5.self).subtracting(сущности(TogoSchemaV4.self))
        #expect(приросло == новыеСущности, """
            сущности V5 приросли не теми, что названы здесь.
            названо  \(новыеСущности.sorted())
            выросло  \(приросло.sorted())

            Новая сущность — это НЕ то, что CoreData выводит сам
            без оговорок, и она обязана быть названа вместе с решением,
            по которому заведена.
            """)

        // 3. Прирост полей у старых сущностей — ровно названный.
        for сущность in сущности(TogoSchemaV4.self).sorted() {
            let выросло = поля(TogoSchemaV5.self, сущность)
                .subtracting(поля(TogoSchemaV4.self, сущность))
            #expect(выросло == (приростПолей[сущность] ?? []), """
                у `\(сущность)` прирост не совпал с названным.
                названо  \((приростПолей[сущность] ?? []).sorted())
                выросло  \(выросло.sorted())

                Либо допиши имя сюда вместе с причиной, либо убери поле.
                Число здесь не годится: оно сходится и при перепутанных
                местах — «срок после вскрытия» вместо «годен до» даёт
                тот же счёт и не тот срок у человека с открытым флаконом.
                """)
        }

        // Срок годности и срок после вскрытия — ДВА поля, и это главное
        // в хендоффе. Одним полем разница «годен до» против «вскрыт,
        // дальше N дней» потерялась бы молча — там, где ошибка
        // измеряется дозой.
        #expect(поля(TogoSchemaV5.self, "Medication")
            .isSuperset(of: ["expiry", "openedAt", "shelfAfterOpenDays"]))
    }

    /// Что V6 добавила к V5 — **одиннадцать надгробий и ровно они**.
    ///
    /// Заведён 26.10.2026 вместе с заморозкой V5. Предмет у него тот же,
    /// что у соседнего теста про V4→V5, а причина завести отдельный —
    /// в том, что наряд на эту правку назвал **двенадцать** полей,
    /// и двенадцатым стоял `Medication.massPerUnitMcg`. Он не новый:
    /// вошёл 08.10 коммитом `43f05a5`, тем же, что записал отпечаток
    /// 304, — то есть лежит внутри формы V5. Список поимённый ловит
    /// такую ошибку, счёт «двенадцать» её бы пропустил.
    @Test("V6 добавляет к V5 ровно одиннадцать надгробий и ничего больше")
    func шестаяВерсияДобавляетОдниНадгробия() {
        func поля(_ версия: any VersionedSchema.Type, _ сущность: String) -> Set<String> {
            let схема = Schema(versionedSchema: версия)
            return Set((схема.entitiesByName[сущность]?.properties ?? []).map(\.name))
        }
        let сущности = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }

        // Одиннадцать типов обмена, у которых удаление должно доезжать
        // до второго человека. `LogEvent` в списке НЕТ: его надгробие
        // живёт с V4.
        let сНадгробием: Set<String> = [
            "CareTask", "Clinic", "Diagnosis", "Dog", "DogDocument",
            "DoseRecord", "LabResult", "Medication", "Prescription",
            "VetVisit", "WeightEntry",
        ]

        // 1. Набор сущностей не менялся — основание для `.lightweight`.
        #expect(сущности(TogoSchemaV6.self) == сущности(TogoSchemaV5.self), """
            набор сущностей V5 и V6 разошёлся. Новая сущность — это НЕ
            то, что CoreData выводит сам без оговорок.
            """)

        // 2. Ничего не убыло ни у одной сущности. Удаление поля
        //    CoreData сам не выводит, а V5 роздана пятью сборками.
        for сущность in сущности(TogoSchemaV5.self).sorted() {
            let убыло = поля(TogoSchemaV5.self, сущность)
                .subtracting(поля(TogoSchemaV6.self, сущность))
            #expect(убыло.isEmpty, "из `\(сущность)` исчезло: \(убыло.sorted())")
        }

        // 3. Прирост — ровно `deletedAt` и ровно у этих одиннадцати.
        //    Проверяется в ОБЕ стороны: и что у названных прибавилось,
        //    и что у остальных не прибавилось ничего. Односторонняя
        //    проверка пропустила бы двенадцатое поле у любого типа.
        var сПриростом: Set<String> = []
        for сущность in сущности(TogoSchemaV5.self).sorted() {
            let выросло = поля(TogoSchemaV6.self, сущность)
                .subtracting(поля(TogoSchemaV5.self, сущность))
            if !выросло.isEmpty { сПриростом.insert(сущность) }
            #expect(выросло == (сНадгробием.contains(сущность) ? ["deletedAt"] : []), """
                у `\(сущность)` прирост V5 → V6 не тот.
                ждём    \(сНадгробием.contains(сущность) ? ["deletedAt"] : [])
                выросло \(выросло.sorted())

                В этой стадии заводятся ТОЛЬКО надгробия. Любое другое
                поле здесь означает, что форму меняют под уже поднятым
                номером — то есть повторяют дефект 26.10.
                """)
        }
        #expect(сПриростом == сНадгробием, """
            надгробия стоят не у тех типов.
            названо  \(сНадгробием.sorted())
            выросло  \(сПриростом.sorted())
            """)

        // 4. `LogEvent` надгробие уже имел — иначе «одиннадцать»
        //    превратилось бы в двенадцать молча.
        #expect(поля(TogoSchemaV5.self, "LogEvent").contains("deletedAt"), """
            у `LogEvent` надгробие должно жить ещё с V4. Если его там
            нет, значит счёт новых полей не одиннадцать, и арифметика
            `304 + 11 = 315` в `SchemaShapeTests` неверна.
            """)

        // 5. И `massPerUnitMcg` обязан быть УЖЕ в V5 — это та самая
        //    ошибка наряда, из-за которой тест и заведён.
        #expect(поля(TogoSchemaV5.self, "Medication").contains("massPerUnitMcg"), """
            `massPerUnitMcg` должен лежать внутри формы V5: он вошёл
            08.10 коммитом `43f05a5` вместе с отпечатком 304. Если его
            в V5 нет — снимок снят не с того коммита.
            """)

        // 6. Все надгробия опциональные. Это и есть то, чем стадия
        //    объявлена облегчённой, и проверять это надо у СХЕМЫ,
        //    а не глазами по объявлению.
        let v6 = Schema(versionedSchema: TogoSchemaV6.self)
        for сущность in сНадгробием.sorted() {
            let свойство = v6.entitiesByName[сущность]?.properties
                .first { $0.name == "deletedAt" }
            #expect(свойство?.isOptional == true, """
                `\(сущность).deletedAt` не опционально. У прежних записей
                заполнить его нечем, `.lightweight` не выведется,
                а зеркало CloudKit на таком поле не заводится.
                """)
        }
    }

    /// Что V7 добавила к V6 — **одно поле `LogEvent.photo` и ровно оно**.
    ///
    /// Заведён 28.10.2026 вместе с заморозкой V7, и до этого дня стадию
    /// V6 → V7 не называл поимённо никто: её прирост держался только
    /// счётом (`SchemaShapeTests`, 315 + 1 = 316). Счёт сходится
    /// и при обмене одного поля на другое, поэтому у каждой стадии
    /// должен быть свой поимённый сторож — у V4 → V5 и V5 → V6 они
    /// есть, у V6 → V7 не было.
    @Test("V7 добавляет к V6 ровно фотографию у записи и ничего больше")
    func седьмаяВерсияДобавляетОдноФото() {
        func поля(_ версия: any VersionedSchema.Type, _ сущность: String) -> Set<String> {
            let схема = Schema(versionedSchema: версия)
            return Set((схема.entitiesByName[сущность]?.properties ?? []).map(\.name))
        }
        let сущности = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }

        #expect(сущности(TogoSchemaV7.self) == сущности(TogoSchemaV6.self), """
            набор сущностей V6 и V7 разошёлся. Новая сущность — это НЕ
            то, что CoreData выводит сам без оговорок.
            """)

        for сущность in сущности(TogoSchemaV6.self).sorted() {
            let убыло = поля(TogoSchemaV6.self, сущность)
                .subtracting(поля(TogoSchemaV7.self, сущность))
            #expect(убыло.isEmpty, "из `\(сущность)` исчезло: \(убыло.sorted())")

            let выросло = поля(TogoSchemaV7.self, сущность)
                .subtracting(поля(TogoSchemaV6.self, сущность))
            #expect(выросло == (сущность == "LogEvent" ? ["photo"] : []), """
                у `\(сущность)` прирост V6 → V7 не тот.
                ждём    \(сущность == "LogEvent" ? ["photo"] : [])
                выросло \(выросло.sorted())
                """)
        }

        // Опциональность — то, чем стадия объявлена облегчённой,
        // и спрашивать её надо у СХЕМЫ, а не глазами по объявлению.
        let фото = Schema(versionedSchema: TogoSchemaV7.self)
            .entitiesByName["LogEvent"]?.properties.first { $0.name == "photo" }
        #expect(фото?.isOptional == true, """
            `LogEvent.photo` не опционально. У прежних записей заполнить
            его нечем, `.lightweight` не выведется, а зеркало CloudKit
            на таком поле не заводится.
            """)
    }

    /// Что V8 добавила к V7 — **четыре свойства и ровно они**.
    ///
    /// Заведён 28.10.2026 вместе с заморозкой V7 и подъёмом до V8.
    /// Список поимённый, а не счётом «четыре», по той же причине,
    /// по которой заведён сосед про надгробия: наряд на ту правку
    /// называл двенадцать полей, а их было одиннадцать, и число
    /// пропустило бы ошибку.
    ///
    /// **Четвёртое свойство здесь — обратная сторона связи, и его
    /// легче всего забыть:** читателей у `Clinic.documentsStorage`
    /// сегодня ноль, то есть ни один экран не покраснеет от его
    /// отсутствия. Покраснеет человек — зеркало CloudKit отказывается
    /// открывать хранилище у связи без обратной
    /// (`CloudKit integration requires that all relationships have
    /// an inverse`, замер `togo-1e` 07.10.2026), и это не красный
    /// тест, а контейнер, не открывшийся вовсе.
    @Test("V8 добавляет к V7 ровно четыре свойства и ничего больше")
    func восьмаяВерсияДобавляетЧетыреСвойства() {
        func поля(_ версия: any VersionedSchema.Type, _ сущность: String) -> Set<String> {
            let схема = Schema(versionedSchema: версия)
            return Set((схема.entitiesByName[сущность]?.properties ?? []).map(\.name))
        }
        let сущности = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }

        // Ожидаемый прирост по сущностям — поимённо и в ОБЕ стороны:
        // и что у названных прибавилось то, и что у остальных
        // не прибавилось ничего.
        let прирост: [String: Set<String>] = [
            "DogDocument": ["occurredOn", "directionRaw", "clinic"],
            "Clinic": ["documentsStorage"],
        ]

        // 1. Набор сущностей не менялся — основание для `.lightweight`.
        #expect(сущности(TogoSchemaV8.self) == сущности(TogoSchemaV7.self), """
            набор сущностей V7 и V8 разошёлся. Справочник клиник живёт
            с V5, и новая связь на него сущности не добавляет; новая
            сущность здесь — это НЕ то, что CoreData выводит сам
            без оговорок.
            """)

        // 2. Ничего не убыло. Удаление поля `.lightweight` не выводит,
        //    а V7 роздана тремя сборками.
        for сущность in сущности(TogoSchemaV7.self).sorted() {
            let убыло = поля(TogoSchemaV7.self, сущность)
                .subtracting(поля(TogoSchemaV8.self, сущность))
            #expect(убыло.isEmpty, "из `\(сущность)` исчезло: \(убыло.sorted())")
        }

        // 3. Прирост — ровно названный, и только у названных.
        var сПриростом: Set<String> = []
        for сущность in сущности(TogoSchemaV7.self).sorted() {
            let выросло = поля(TogoSchemaV8.self, сущность)
                .subtracting(поля(TogoSchemaV7.self, сущность))
            if !выросло.isEmpty { сПриростом.insert(сущность) }
            #expect(выросло == (прирост[сущность] ?? []), """
                у `\(сущность)` прирост V7 → V8 не тот.
                ждём    \((прирост[сущность] ?? []).sorted())
                выросло \(выросло.sorted())

                В этой стадии заводятся ТОЛЬКО дата события,
                направление и связь с клиникой. Любое другое поле
                здесь означает, что форму меняют под уже поднятым
                номером — то есть повторяют дефект 26.10.
                """)
        }
        #expect(сПриростом == Set(прирост.keys), """
            поля выросли не у тех типов.
            названо  \(прирост.keys.sorted())
            выросло  \(сПриростом.sorted())
            """)

        // 4. Все четыре опциональные. Это и есть то, чем стадия
        //    объявлена облегчённой, и спрашивать надо у СХЕМЫ.
        let v8 = Schema(versionedSchema: TogoSchemaV8.self)
        for (сущность, имена) in прирост.sorted(by: { $0.key < $1.key }) {
            for имя in имена.sorted() {
                let свойство = v8.entitiesByName[сущность]?.properties
                    .first { $0.name == имя }
                #expect(свойство?.isOptional == true, """
                    `\(сущность).\(имя)` не опционально. У прежних
                    записей заполнить его нечем, `.lightweight`
                    не выведется, а зеркало CloudKit на таком поле
                    не заводится.
                    """)
            }
        }

        // 5. Связь обязана быть связью с ОБЕИХ сторон, а не парой
        //    скаляров: без обратной зеркало CloudKit не открывает
        //    хранилище вовсе. Спрашивается у СХЕМЫ, потому что
        //    `@Relationship(inverse:)` в объявлении — намерение,
        //    а то, что лежит в схеме, — результат.
        //
        // **Ось первой редакции мерила SDK, а не модель, и это замер
        // 28.10.2026, а не осторожность.** Стояло
        // `свойство?.isRelationship == true`, и прогон дал КРАСНОЕ
        // на обоих концах живой, объявленной и работающей связи.
        // Причина в SwiftData: `isRelationship` — требование протокола
        // `SchemaProperty`, у `Schema.Attribute` своя реализация,
        // а у `Schema.Relationship` СВОЕЙ НЕТ, и свидетелем встаёт
        // умолчание из расширения протокола
        // (`SwiftData.swiftinterface:1035, 1046, 1104`).
        //
        // > **Сторож на `isRelationship` дал бы ложный красный
        // > на любой связи проекта** — то есть отправил бы чинить
        // > здоровый код. Поймал не глаз, а контроль ниже.
        //
        // Ось взята та же, которой пользуется `SchemaShapeTests.замер`:
        // приведение к типу. Оно спрашивает «что это за объект»,
        // а не «что объект о себе говорит».
        func связь(_ сущность: String, _ имя: String) -> Schema.Relationship? {
            v8.entitiesByName[сущность]?.properties
                .first { $0.name == имя } as? Schema.Relationship
        }

        // КОНТРОЛЬ, и он снимается в ТОМ ЖЕ замере, что предмет:
        // `CareTask.clinic` — связь, живущая с V5, проверенная круговым
        // тестом архива и обменом. Покраснеет она — сломана ось,
        // а не моя модель, и читать две строки ниже нельзя.
        #expect(связь("CareTask", "clinic") != nil, """
            КОНТРОЛЬ НЕ ПРОШЁЛ: `CareTask.clinic` — связь с V5,
            и если ось не видит её, то она не видит НИ ОДНОЙ связи.
            Две проверки ниже в этом случае ничего не говорят о модели.
            """)

        #expect(связь("DogDocument", "clinic") != nil, """
            `DogDocument.clinic` не связь. Строкой имя клиники хранить
            нельзя: шестнадцать организаций карты рассыплются
            на столько групп, сколько было опечаток.
            """)
        #expect(связь("Clinic", "documentsStorage") != nil, """
            `Clinic.documentsStorage` не связь — то есть у связи
            документа с клиникой нет обратной стороны. Зеркало
            CloudKit такое хранилище не открывает вовсе, и у человека
            это молчаливый откат в память: рабочий экран, отметка
            дозы, запись в никуда.
            """)
    }

    // MARK: Главная приёмка — старая база открывается новой схемой

    /// Фотография собаки переезжает в файл — и обязана доехать.
    ///
    /// 28.10.2026 `Dog.photo` получил `@Attribute(.externalStorage)`:
    /// до этого байты лежали в строке таблицы, и каждый запрос собак
    /// поднимал их в память (14 экранов с `@Query dogs`). Опция меняет
    /// не поле, а **способ хранения**, и это тот род правки, который
    /// проходит мимо всех сторожей схемы:
    ///
    /// ```
    /// SchemaShapeTests.замер    опции атрибута в отпечаток НЕ кладёт
    /// поле                      не добавилось
    /// тип поля                  не изменился
    /// отпечаток и счёт свойств  ПРЕЖНИЕ → все сторожа ЗЕЛЁНЫЕ
    /// форма хранилища           ДРУГАЯ
    /// ```
    ///
    /// > **Правка, которой не видит ни один сторож, опаснее красного
    /// > теста.** Красное держит выпуск; здесь выпуск не держало
    /// > ничего, а цена ошибки — фотография собаки у человека,
    /// > который ставит обновление.
    ///
    /// Поэтому проверка ЗДЕСЬ, у миграции, а не у формы схемы: ось —
    /// «байты дошли», а не «поле объявлено». Сравниваются именно
    /// байты, а не факт непустоты: при неудачном переносе поле
    /// осталось бы не пустым, а ДРУГИМ, и `!= nil` прошло бы как успех.
    @Test("Фотография собаки переживает переход V7 → V8 байт в байт")
    func фотоПереживаетВосьмую() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        // Узнаваемый снимок, а не случайные байты: если данные
        // подменятся, по содержимому будет видно, чем именно.
        let снимок = Data((0..<4096).map { UInt8($0 % 251) })

        do {
            let схема = Schema(versionedSchema: TogoSchemaV7.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)

            let собака = TogoSchemaV7.Dog()
            собака.name = "Стич"
            собака.photo = снимок
            context.insert(собака)

            // Вторая собака БЕЗ фотографии — в той же базе нарочно:
            // перенос пустого поля ломается отдельно от переноса
            // непустого, и «у всех есть фото» скрыло бы это.
            let безФото = TogoSchemaV7.Dog()
            безФото.name = "Второй"
            context.insert(безФото)

            try context.save()
        }

        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)
        let собаки = try context.fetch(FetchDescriptor<Dog>())

        #expect(собаки.count == 2, """
            после перехода V7 → V8 собак не две: миграция потеряла
            записи, и сверять байты уже не на чем.
            """)

        let стич = try #require(собаки.first { $0.name == "Стич" })
        #expect(стич.photo == снимок, """
            фотография не дошла байт в байт после смены способа
            хранения на .externalStorage.
            было \(снимок.count) байт, стало \(стич.photo?.count ?? -1).
            Человек увидит чёрную заглушку вместо собаки, и вернуть
            снимок будет откуда — только из его галереи, если он там
            остался.
            """)

        // ЗАМЕР 28.10.2026, и он перевернул ожидание этого теста.
        //
        // Первая редакция требовала `второй.photo == nil` — и упала:
        // SwiftData переносит `nil` как `Data()` НУЛЕВОЙ ДЛИНЫ.
        // Это поведение системы, а не наш дефект, и чинить его
        // в хранилище нечем.
        //
        // > Сторож писался ради байтов фотографии — и поймал не их,
        // > а соседнее: поле, которое перестало быть пустым. Вторая
        // > собака заведена здесь именно затем, что перенос ПУСТОГО
        // > значения ломается отдельно от непустого.
        //
        // Поэтому ось теста переведена с «поле пустое» на то, что
        // решает для человека: СЧИТАЕТСЯ ли это фотографией.
        // Правило живёт одной дорогой — `Dog.снимок`, — и три места,
        // спрашивавшие «есть ли поле», переведены на неё: иначе
        // ноль байт уехал бы в App Group подложкой и дал бы чёрный
        // экран вместо собаки.
        let второй = try #require(собаки.first { $0.name == "Второй" })
        #expect(второй.снимок == nil, """
            у собаки без фотографии снимок считается существующим.
            Поле после переноса хранит \(второй.photo?.count ?? -1) байт,
            и правило «пустое — не фотография» его не отсекло.
            Отсюда чёрная подложка вместо собаки: пустые байты
            доезжают до хранилища фонов как установленный снимок.
            """)
        // А вот у собаки СО снимком правило не должно ничего отнять —
        // иначе «пустое — не фото» съело бы живую фотографию.
        #expect(стич.снимок == снимок, "правило непустоты отняло живой снимок")
    }

    /// **То, из-за чего вся эта правка, и чего не проверял ни один тест
    /// до 26.10.2026.**
    ///
    /// Соседние тесты заводят базу из V1 и V2 — снимков, замороженных
    /// давно. Форму V5 не заводил никто, потому что V5 ссылалась
    /// на живые классы: база «на V5» получалась тождественной нынешней,
    /// и переход проверять было нечем. Ровно в этой слепой зоне
    /// и случилась авария: `f546719` сменил форму V5 под неизменным
    /// номером, и пять розданных сборок перестали опознаваться.
    ///
    /// Теперь V5 — снимок, то есть в бинарнике ДВЕ разные формы, и этот
    /// круг наконец выразим: завести базу формы 304, закрыть, открыть
    /// схемой V6 и **пересчитать записи**. Не «открылась», а «записи
    /// на месте и столько же».
    @Test("Хранилище розданных сборок 273–277 открывается схемой V6 и ничего не теряет")
    func изРозданнойПятой() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        let когда = Date(timeIntervalSince1970: 1_761_000_000)

        // 1. База ровно той формы, что лежит на пяти телефонах.
        do {
            let схема = Schema(versionedSchema: TogoSchemaV5.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)

            let собака = TogoSchemaV5.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            собака.breed = "Шипперке"
            собака.rewards = ["сыр", "индейка"]
            context.insert(собака)

            // Схема лечения — самый дорогой случай: именно её отмена
            // не доезжала до мамы и давала напоминания о дозах.
            let лечение = TogoSchemaV5.Medication()
            лечение.name = "Lévothyrox"
            лечение.doseText = "66 мкг"
            лечение.massPerUnitMcg = 66
            лечение.dog = собака
            context.insert(лечение)

            let доза = TogoSchemaV5.DoseRecord()
            доза.scheduledAt = когда
            доза.givenAt = когда.addingTimeInterval(60)
            доза.givenBy = "Виктория"
            доза.medication = лечение
            context.insert(доза)

            let вес = TogoSchemaV5.WeightEntry()
            вес.date = когда
            вес.kg = 4.2
            вес.dog = собака
            context.insert(вес)

            let уход = TogoSchemaV5.CareTask()
            уход.title = "Когти"
            уход.dog = собака
            context.insert(уход)

            let анализ = TogoSchemaV5.LabResult()
            анализ.indicator = "T4"
            анализ.value = 16.75
            анализ.dog = собака
            context.insert(анализ)

            let запись = TogoSchemaV5.LogEvent()
            запись.kindRaw = LogKind.outing.rawValue
            запись.date = когда
            запись.authorName = "Виктория"
            запись.dog = собака
            context.insert(запись)

            try context.save()
        }

        // 2. Та же база нынешней схемой и планом. Это и есть ответ
        //    на вопрос «откроется ли у неё дневник».
        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)

        // 3. Записи на месте — поимённо и по счёту.
        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, "собака должна пережить переход V5 → V6")
        let собака = try #require(собаки.first)
        #expect(собака.name == "Стич")
        #expect(собака.weightKg == 4.1)
        #expect(собака.breed == "Шипперке")
        #expect(собака.rewards == ["сыр", "индейка"])

        #expect(try context.fetch(FetchDescriptor<Medication>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DoseRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CareTask>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<LabResult>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 1)

        // 4. Связи целы: без них лента у собаки пуста, хотя записи есть.
        #expect(собака.events.count == 1, "связь собака → записи пережила переход")
        #expect(собака.medications.count == 1)
        #expect(собака.weights.count == 1)
        #expect(собака.careTasks.count == 1)
        #expect(собака.labResults.count == 1)

        let лечение = try #require(собака.medications.first)
        #expect(лечение.name == "Lévothyrox")
        #expect(лечение.massPerUnitMcg == 66, "числовая доза не должна потеряться")
        #expect(лечение.doses.count == 1, "связь лечение → дозы пережила переход")

        // 5. Надгробия у переехавших записей ПУСТЫЕ. Это не косметика:
        //    непустое надгробие означало бы, что миграция пометила
        //    удалёнными живые записи — и человек увидел бы пустой
        //    дневник при целых данных, то есть ровно ту беду,
        //    от которой заводились надгробия.
        #expect(собака.deletedAt == nil, "живая собака не должна приехать удалённой")
        #expect(лечение.deletedAt == nil, "живая схема лечения — тем более")
        #expect(собака.canBeShown, "собака обязана показываться после перехода")

        // 6. И в переведённую базу можно писать — то самое, что падало.
        let ещёЗапись = LogEvent(kind: .meal, authorName: "Тео")
        ещёЗапись.dog = собака
        context.insert(ещёЗапись)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 2)
    }

    /// **База сборки 284 открывается схемой V9 и ничего не теряет.**
    ///
    /// Заведён 29.10.2026, и заведён по пробелу, а не для полноты.
    /// В наборе были тесты на формы 36, 46 и 273–277 — и ни одного
    /// на ту форму, что стоит у Виктории прямо сейчас. То есть
    /// единственный переход, который случится на живом телефоне
    /// в этот раз, не спрашивал никто.
    ///
    /// Пробел открылся после сведения двух линий: V8 заморожена
    /// снимком, `Medication.startedAt` стал V9, и между ними появилась
    /// новая стадия. Проверить её было нечем.
    ///
    /// > **Набор тестов на миграции прикрывает прошлое и молчит
    /// > о ближайшем переходе.** Каждая новая версия заводит стадию,
    /// > на которую теста ещё нет, и заметно это ровно в тот день,
    /// > когда сборка уже собрана.
    ///
    /// Чего он НЕ доказывает: что база откроется на её телефоне.
    /// Здесь форма собрана снимком `TogoSchemaV8`, а на телефоне —
    /// та, что записала сборка 284. Совпадение проверено отпечатком
    /// (`SchemaShapeTests`), но отпечаток — не файл с диска, и приёмка
    /// на устройстве остаётся отдельной работой.
    @Test("Хранилище сборки 284 открывается схемой V9 и ничего не теряет")
    func изРозданнойВосьмой() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        let когда = Date(timeIntervalSince1970: 1_761_700_000)

        // 1. База ровно той формы, что уехала людям в 284.
        do {
            let схема = Schema(versionedSchema: TogoSchemaV8.self)
            let контейнер = try ModelContainer(for: схема, configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)

            let собака = TogoSchemaV8.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.7
            собака.isOnTreatment = true
            context.insert(собака)

            // Схема лечения без даты начала: в 284 этого поля не было
            // вовсе, и ровно его добавляет стадия V8 → V9.
            let лечение = TogoSchemaV8.Medication()
            лечение.name = "Lévothyrox"
            лечение.doseText = "88 мкг"
            лечение.massPerUnitMcg = 88
            лечение.prescriptionNumber = "2026/0881"
            лечение.dog = собака
            context.insert(лечение)

            let доза = TogoSchemaV8.DoseRecord()
            доза.scheduledAt = когда
            доза.givenAt = когда.addingTimeInterval(120)
            доза.givenBy = "Виктория"
            доза.medication = лечение
            context.insert(доза)

            // Документ с полями, которые и сделали эту форму восьмой:
            // дата события, направление и клиника.
            let клиника = TogoSchemaV8.Clinic()
            клиника.name = "Вет-центр"
            context.insert(клиника)

            let документ = TogoSchemaV8.DogDocument()
            документ.title = "Анализ Т4"
            документ.occurredOn = когда
            документ.directionRaw = DocumentDirection.allCases.first?.rawValue
            документ.clinic = клиника
            документ.dog = собака
            context.insert(документ)

            try context.save()
        }

        // 2. Та же база нынешней схемой и планом.
        let контейнер = try открываемНынешней(url)
        let context = ModelContext(контейнер)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, "собака должна пережить переход V8 → V9")
        let собака = try #require(собаки.first)
        #expect(собака.name == "Стич")
        #expect(собака.weightKg == 4.7)
        #expect(собака.isOnTreatment, "признак лечения не должен сброситься")
        #expect(собака.deletedAt == nil, "живая собака не должна приехать удалённой")

        let лечение = try #require(собака.medications.first)
        #expect(лечение.name == "Lévothyrox")
        #expect(лечение.massPerUnitMcg == 88, "числовая доза не должна потеряться")
        #expect(лечение.prescriptionNumber == "2026/0881")
        #expect(лечение.doses.count == 1, "связь лечение → дозы пережила переход")

        // 3. Новое поле пустое — и это верно, а не дефект: в 284
        //    приложение даты начала не знало, и выдумать её миграцией
        //    было бы хуже пустоты. Человек не говорил, с какого дня
        //    идёт курс.
        #expect(лечение.startedAt == nil, """
            дата начала схемы приехала заполненной из формы, где поля
            не было. Значит миграция её ВЫДУМАЛА — а это утверждение
            о лечении, которого человек не делал.
            """)

        // 4. Документ и его связи целы: именно они делают форму восьмой.
        let документы = try context.fetch(FetchDescriptor<DogDocument>())
        #expect(документы.count == 1)
        let документ = try #require(документы.first)
        #expect(документ.title == "Анализ Т4")
        #expect(документ.occurredOn != nil, "дата события документа пережила переход")
        #expect(документ.clinic?.name == "Вет-центр", "связь документ → клиника цела")

        // 5. И в переведённую базу можно писать.
        let ещёЗапись = LogEvent(kind: .meal, authorName: "Тео")
        ещёЗапись.dog = собака
        context.insert(ещёЗапись)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 1)
    }

    @Test("В плане перечислены все формы хранилища, что уехали из репозитория")
    func планПолон() {
        #expect(TogoMigrationPlan.schemas.count == 10, """
            сборка 36 (V1), сборка 46 (V2), сборка 141 (V3), сборки
            191–271 (V4), сборки 273–277 (V5), сборка 279 (V6),
            сборки 280–282 (V7), 284 (V8) и 285 (V9) — версию, которой
            в плане нет, открыть нечем. V8 заморожена снимком до того,
            как облачная правка `Medication.startedAt` стала V9; V9 —
            до того, как к эпизоду добавили `dogID` (V10).
            V3 заморожена снимком 23.09, V4 — 05.10, V5 — 26.10,
            V6 — 27.10, V7 — 28.10: до заморозки каждая ссылалась
            на живые классы, и первая же правка модели меняла её форму
            под неизменным номером. У V5 это и случилось: `f546719`
            добавил одиннадцать надгробий, и пять розданных сборок
            перестали открываться.
            V6 заморожена ПЕРЕД тем, как к `LogEvent` добавили `photo`, —
            то есть в той форме, с которой 279 уехала людям. V7 — перед
            тем, как к документу добавили дату события, направление
            и клинику, то есть в той форме, с которой уехали 280–282.
            """)
        // Восьмая стадия — V8 → V9, заведена 29.10.2026 при сведении
        // двух линий: облачная правка пришла под занятым номером 8.
        // Девятая — V9 → V10, `Episode.dogID`, 29.10.2026.
        #expect(TogoMigrationPlan.stages.count == 9)
        #expect(Persistence.schema.version == TogoSchemaV10.versionIdentifier,
                "приложение открывает хранилище последней версией плана")
    }

    // MARK: Форма, которой в плане нет

    /// **Случай, которого не может быть ни в одном тесте выше.** Там база
    /// заводится из V1 или V2 — обе в плане, обе открываются. Форма, которой
    /// в плане нет, из такой базы не возникает никогда, поэтому зелёный
    /// прогон миграции не говорил о ней ничего.
    ///
    /// А встречается она чаще всех остальных: номер сборки — это число
    /// коммитов, и любая дневная сборка через `make device` с промежуточного
    /// коммита оставляет на телефоне форму, которой в плане нет по построению.
    /// Снимка в плане три — сборки 36, 46 и нынешняя.
    ///
    /// Важно не то, что такую базу нельзя открыть: это законно и неизбежно.
    /// Важно, **что приложение делает дальше.** Лестница отката в
    /// `openContainer` доходит до хранилища в памяти, а оно открывается
    /// всегда — мигрировать в нём нечего. Человек получает не сообщение,
    /// а пустой дневник, и его собственный, целый, лежит рядом на диске.
    @Test("Хранилище формы, которой нет в плане, не подменяется пустым дневником")
    func неизвестнаяФорма() throws {
        let url = try заводимПапку()
        defer { убираем(url) }

        // 1. База «дневной сборки» — и в ней запись, которую нельзя потерять.
        do {
            let схема = Schema(versionedSchema: TogoSchemaDev.self)
            let контейнер = try ModelContainer(for: схема,
                                               configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)
            let собака = TogoSchemaDev.Dog()
            собака.name = "Стич"
            собака.weightKg = 4.1
            context.insert(собака)
            try context.save()
        }

        // 2. Исходное условие: нынешняя схема такую базу открыть не может.
        //    Если этот #expect однажды перестанет срабатывать, значит
        //    SwiftData научилась опознавать чужую форму — и проверка ниже
        //    потеряла смысл, а не «просто позеленела».
        #expect(throws: (any Error).self) { try открываемНынешней(url) }

        // 3. Ради чего всё: приложение обязано сказать «дневник не открылся»
        //    и дать восстановление, а не нарисовать пустой.
        let контейнер = Persistence.openContainer(storeURL: url, allowCloud: false)
        #expect(контейнер == nil,
                "нужен StorageFailureScreen, а он показывается только когда контейнер nil")
        #expect(Persistence.isEphemeral == false,
                "хранилище в памяти поверх непустого файла — это подмена дневника пустым")

        // 4. И файл обязан остаться на месте: восстанавливать будет нечего,
        //    если приложение его тронет.
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                "файл дневника не трогаем — из него человек и будет восстанавливаться")
    }

    // MARK: Та же версия, другая форма — случай второго телефона

    /// **Чего не проверяет ни один тест выше, включая соседний.**
    /// `неизвестнaяФорма()` заводит базу версии `2.5.0` — номера, которого
    /// в плане нет вовсе. Это другая дорога внутри SwiftData: версию
    /// не нашли, открывать нечем, отказ.
    ///
    /// Здесь дорога обратная и встречается она у живых людей:
    /// **номер версии ТОТ ЖЕ, что у нынешней схемы, а форма другая.**
    /// `TogoSchemaV5` ссылается на живые классы, поэтому её форма ползёт
    /// при каждой правке модели, а номер `5.0.0` стоит на месте с 07.10.2026
    /// (`SchemaVersions.swift:1509-1566` — там это названо решением, а не
    /// недосмотром). Значит на телефоне, где стоит сборка от 07.10, лежит
    /// база с номером `5.0.0` и формой **уже** нынешней; стадии
    /// «5.0.0 → 5.0.0» не существует и быть не может — между двумя
    /// одинаковыми номерами миграции нет.
    ///
    /// Цена названа в самом `SchemaVersions.swift:1562-1566`: следующая
    /// сборка даёт такому человеку «Дневник не открылся». Проверяется
    /// здесь не то, что база не открылась — это законно, — а **что
    /// приложение делает дальше**: лестница отката в `openContainer`
    /// доходит до хранилища в памяти, и человек получил бы пустой дневник
    /// поверх своего целого.
    ///
    /// **Чем этот снимок отличается от формы на телефоне, и это сказано
    /// вслух.** Там форма уже нынешней на три ХРАНИМЫХ ПОЛЯ
    /// (`WeightEntry.changedAt` — `05ced4a`, `DogDocument.changedAt` —
    /// `847e59a`, `Medication.massPerUnitMcg` — `43f05a5`; замер
    /// сверкой множеств свойств 14.10.2026). Здесь — на одну СУЩНОСТЬ.
    /// Обе величины входят в форму хранилища, но доказательства, что
    /// SwiftData отвечает на них одинаково, у меня нет: измерено, что
    /// она отвечает отказом на более узкую форму под тем же номером.
    /// Снимок полей потребовал бы копии двадцати одного класса — тех
    /// самых четырёхсот строк, которые Виктория отменила вслух.
    @Test("Хранилище ТОЙ ЖЕ версии 5.0.0, но другой формы, не подменяется пустым дневником")
    func тотЖеНомерДругаяФорма() throws {
        // 0. Было ли что проверять. Без этих двух строк весь тест ниже
        //    прошёл бы на схеме, совпадающей с нынешней: база открылась
        //    бы штатно, `#expect(throws:)` покраснел бы — но покраснел бы
        //    он на своей же ошибке, а не на дефекте приложения.
        #expect(TogoSchemaV5СУженнаяФорма.versionIdentifier == TogoSchemaV10.versionIdentifier, """
            номер версии снимка разошёлся с нынешним — а весь смысл этой
            проверки в том, что номера СОВПАДАЮТ. С разными номерами это
            повтор соседнего теста про форму не из плана.
            """)
        #expect(TogoSchemaV5СУженнаяФорма.models.count == TogoSchemaV10.models.count - 1, """
            снимок обязан быть уже нынешней схемы ровно на одну сущность.
            Совпали — значит фильтр ничего не убрал (сущность переименовали
            или сняли), и база заведётся нынешней формой: тест станет
            зелёным, не проверив ничего.
            """)

        let url = try заводимПапку()
        defer { убираем(url) }

        // 1. База «телефона со сборкой до 07.10»: номер 5.0.0, форма уже.
        //    И в ней запись, которую человек потерять не должен.
        do {
            let схема = Schema(versionedSchema: TogoSchemaV5СУженнаяФорма.self)
            let контейнер = try ModelContainer(for: схема,
                                               configurations: конфигурация(схема, url))
            let context = ModelContext(контейнер)
            let собака = Dog(name: "Стич", weightKg: 4.7)
            context.insert(собака)
            try context.save()
        }

        // 2. Исходное условие, и оно же — сам замер. Если этот `#expect`
        //    однажды перестанет срабатывать, значит SwiftData научилась
        //    открывать расходящуюся форму под тем же номером: тогда вся
        //    тревога про «Дневник не открылся» снимается, а проверка ниже
        //    теряет смысл — и это надо заметить, а не считать зеленью.
        #expect(throws: (any Error).self) { try открываемНынешней(url) }

        // 3. Ради чего всё: отказ обязан быть ГРОМКИМ. `nil` показывает
        //    `StorageFailureScreen` с восстановлением; хранилище в памяти
        //    показало бы онбординг чистой установки поверх целого дневника.
        let контейнер = Persistence.openContainer(storeURL: url, allowCloud: false)
        #expect(контейнер == nil,
                "нужен StorageFailureScreen, а он показывается только когда контейнер nil")
        #expect(Persistence.isEphemeral == false,
                "хранилище в памяти поверх непустого файла — это подмена дневника пустым")

        // 4. Файл цел: из него человек и будет восстанавливаться.
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                "файл дневника не трогаем — из него человек и будет восстанавливаться")
    }
}

/// Форма хранилища второго телефона: **тот же номер `5.0.0`, что у нынешней
/// схемы, и набор сущностей уже на одну.**
///
/// Живёт только в тестах; в приложение такая схема не уезжает и в
/// `TogoMigrationPlan` не входит — она и не должна туда входить, иначе
/// в плане оказались бы две версии с одним номером.
///
/// **Почему набор строится фильтром, а не списком.** Список из двадцати
/// имён устарел бы молча: добавили сущность в `TogoSchemaV5` — и снимок
/// стал бы уже не на одну, а на две, то есть проверял бы уже не тот
/// предмет. Фильтр идёт за живым набором, а то, что он действительно
/// что-то убрал, проверяется первым `#expect` в самом тесте.
///
/// `ProcedureSkill` выбрана потому, что она единственная из двадцати одной
/// **ни с кем не связана** (`TogoShared/Models/Training.swift:92` — ни
/// одного `@Relationship`, и ни одна модель на неё не ссылается). Убрать
/// связанную значило бы оставить в схеме связь на отсутствующую сущность —
/// а такое хранилище не открывается вовсе, и тест мерил бы не форму,
/// а оборванную связь.
enum TogoSchemaV5СУженнаяФорма: VersionedSchema {
    static var versionIdentifier: Schema.Version { TogoSchemaV10.versionIdentifier }

    /// Модели берутся у **V10 — живых классов**, а не у снимка.
    /// (С V9 на V10 переведено 29.10.2026: V9 стала снимком, и правило
    /// ниже сработало бы в третий раз.)
    ///
    /// 29.10.2026 здесь стояла `TogoSchemaV8.models`, и после того как
    /// V8 стала снимком, тест заводил контейнер на снимочных типах,
    /// а код работал с живыми: SwiftData роняло приложение первым же
    /// чтением — «Failed to cast model Togo.Dog … to Dog», два
    /// перезапуска раннера и ни одного выполненного теста.
    ///
    /// > **Снимок и живой класс — разные типы с одним именем.** Всё,
    /// > что собирает контейнер для РАБОТЫ (а не для проверки старой
    /// > формы), обязано брать модели у последней версии плана.
    static var models: [any PersistentModel.Type] {
        TogoSchemaV10.models.filter { ObjectIdentifier($0) != ObjectIdentifier(ProcedureSkill.self) }
    }
}

/// Снимок «дневной сборки»: форма хранилища, которой нет ни в одной версии
/// плана. Живёт только в тестах — в приложение такая схема не уезжает.
///
/// Отличается от сборки 46 одной лишней сущностью. Способ выбран самый
/// дешёвый из честных: набор сущностей входит в форму хранилища, поэтому
/// такая база заведомо не совпадает ни с V1, ни с V2, ни с V3 — то есть
/// воспроизводит состояние телефона, на котором стояла сборка
/// с промежуточного коммита.
enum TogoSchemaDev: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 5, 0)

    typealias CareTask = TogoSchemaV2.CareTask
    typealias Medication = TogoSchemaV2.Medication
    typealias DoseRecord = TogoSchemaV2.DoseRecord
    typealias WeightEntry = TogoSchemaV2.WeightEntry
    typealias DayOut = TogoSchemaV2.DayOut
    typealias Dog = TogoSchemaV2.Dog
    typealias DogDocument = TogoSchemaV2.DogDocument
    typealias FamilyMember = TogoSchemaV2.FamilyMember
    typealias Episode = TogoSchemaV2.Episode
    typealias Trip = TogoSchemaV2.Trip
    typealias FoodStock = TogoSchemaV2.FoodStock
    typealias HeatRecord = TogoSchemaV2.HeatRecord
    typealias LogEvent = TogoSchemaV2.LogEvent
    typealias TrainingStep = TogoSchemaV2.TrainingStep
    typealias TrainingSession = TogoSchemaV2.TrainingSession
    typealias ProcedureSkill = TogoSchemaV2.ProcedureSkill

    static var models: [any PersistentModel.Type] {
        [CareTask.self, Medication.self, DoseRecord.self, WeightEntry.self, DayOut.self,
         Dog.self, DogDocument.self, FamilyMember.self, Episode.self, Trip.self,
         FoodStock.self, HeatRecord.self, LogEvent.self, TrainingStep.self,
         TrainingSession.self, ProcedureSkill.self, DevBuildNote.self]
    }

    /// Имя латиницей, в отличие от имён тестов вокруг, и это не вкусовщина:
    /// CoreData делает из имени класса имя сущности, а кириллическое имя
    /// роняет `NSKnownKeysDictionary` необработанным `NSUnknownKeyException` —
    /// падает не тест, а весь процесс, и прогон показывает «0 tests passed».
    @Model
    final class DevBuildNote {
        var id: UUID = UUID()
        var text: String = ""

        init() {}
    }
}
