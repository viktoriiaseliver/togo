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
        let v3Записи = поля(TogoSchemaV3.self, "LogEvent")

        // Ровно три поля появились в сборке 46 — коммит 4081a47.
        #expect(v2Записи.subtracting(v1Записи) == ["enteredAt", "originRaw", "isDayOnly"])
        #expect(v1Записи.subtracting(v2Записи).isEmpty, "в сборке 46 ничего не удалено")
        #expect(v3Записи == v2Записи, "после сборки 46 лента не менялась")

        let v2Лечение = поля(TogoSchemaV2.self, "Medication")
        let v3Лечение = поля(TogoSchemaV3.self, "Medication")

        // Ровно одно поле появилось после сборки 46 — коммит de07bda.
        #expect(v3Лечение.subtracting(v2Лечение) == ["fastingBeforeMinutes"])
        #expect(v2Лечение.subtracting(v3Лечение).isEmpty, "ничего не удалено")

        // Набор сущностей тот же во всех трёх — значит ни одной модели
        // не завели и не убрали, и стадии правда лёгкие.
        let имена = { (версия: any VersionedSchema.Type) in
            Set(Schema(versionedSchema: версия).entitiesByName.keys)
        }
        #expect(имена(TogoSchemaV1.self) == имена(TogoSchemaV3.self))
        #expect(имена(TogoSchemaV2.self) == имена(TogoSchemaV3.self))
        #expect(имена(TogoSchemaV3.self).count == 16)
    }

    @Test("В плане перечислены все формы хранилища, что уехали из репозитория")
    func планПолон() {
        #expect(TogoMigrationPlan.schemas.count == 3,
                "сборка 36, сборка 46 и нынешняя — версию, которой в плане нет, открыть нечем")
        #expect(TogoMigrationPlan.stages.count == 2)
        #expect(Persistence.schema.version == TogoSchemaV3.versionIdentifier,
                "приложение открывает хранилище последней версией плана")
    }
}
