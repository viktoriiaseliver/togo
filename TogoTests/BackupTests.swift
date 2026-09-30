import Testing
import Foundation
import SwiftData
@testable import Togo

@Suite("Перенос и восстановление")
@MainActor
struct BackupTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private func завестиСтича(в context: ModelContext) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.breed = "Шипперке"
        dog.foodBrand = "Acana ягнёнок"
        dog.portionGrams = 60
        dog.mealsPerDay = 2
        dog.rewards = ["сыр", "индейка"]
        dog.isOnTreatment = true
        context.insert(dog)

        let выход = LogEvent(kind: .outing, date: Date().addingTimeInterval(-3600), authorName: "Виктория")
        выход.outcome = .both
        выход.dog = dog
        context.insert(выход)

        let еда = LogEvent(kind: .meal, authorName: "Тео")
        еда.grams = 60
        еда.dog = dog
        context.insert(еда)

        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг",
                               times: [7 * 60, 19 * 60], fastingMinutes: 45)
        схема.dog = dog
        context.insert(схема)

        let доза = DoseRecord(scheduledAt: Date().addingTimeInterval(-7200))
        доза.givenAt = Date().addingTimeInterval(-7100)
        доза.givenBy = "Виктория"
        доза.medication = схема
        context.insert(доза)

        let уход = CareTask(title: "Когти", detail: "каждые 3 недели", intervalDays: 21, category: .grooming)
        уход.dog = dog
        context.insert(уход)

        let сухой = FoodStock(kind: .dry, brand: "Acana", packGrams: 3000,
                              packsLeft: 0.5, gramsPerDay: 60)
        сухой.dog = dog
        context.insert(сухой)

        let влажный = FoodStock(kind: .wet, brand: "Паучи", packGrams: 100,
                                packsLeft: 12, gramsPerDay: 60)
        влажный.dog = dog
        context.insert(влажный)

        context.insert(FamilyMember(name: "Виктория", role: .owner, isMe: true))
        let мама = FamilyMember(name: "Мама", role: .caregiver)
        мама.permissions = [.logBasics, .seeMedical, .giveDose, .editTreatment]
        context.insert(мама)

        return dog
    }

    @Test("Файл переживает переустановку: выгрузили — восстановили в пустую базу")
    func roundTrip() throws {
        let старый = контекст()
        _ = завестиСтича(в: старый)

        let архив = try BackupService.archive(context: старый, appVersion: "1.0.0")
        let данные = try BackupService.encode(архив)

        // «Переустановка»: новое пустое хранилище.
        let новый = контекст()
        let прочитанный = try BackupService.decode(данные)
        try BackupService.restore(прочитанный, into: новый, strategy: .replace)

        let собаки = try новый.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)

        let стич = собаки[0]
        #expect(стич.name == "Стич")
        #expect(стич.breed == "Шипперке")
        #expect(стич.portionGrams == 60)
        #expect(стич.rewards == ["сыр", "индейка"])
        #expect(стич.isOnTreatment)
        #expect(стич.events.count == 2)
        #expect(стич.careTasks.count == 1)
        #expect(стич.medications.count == 1)
        #expect(стич.medications.first?.fastingMinutes == 45)
        #expect(стич.medications.first?.doses.count == 1)
        #expect(стич.stocks.count == 2, "запас корма переезжает вместе с собакой")
        #expect(стич.stocks.contains { $0.kind == .wet && $0.packGrams == 100 })
    }

    @Test("Права, выданные поимённо, переезжают вместе с человеком")
    func permissionsSurvive() throws {
        let старый = контекст()
        _ = завестиСтича(в: старый)

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let мама = try новый.fetch(FetchDescriptor<FamilyMember>()).first { $0.name == "Мама" }
        #expect(мама?.hasCustomPermissions == true)
        #expect(мама?.can(.editTreatment) == true)
    }

    @Test("Повторная загрузка того же файла ничего не задваивает")
    func mergeIsIdempotent() throws {
        let context = контекст()
        _ = завестиСтича(в: context)

        let данные = try BackupService.encode(
            try BackupService.archive(context: context, appVersion: "1.0.0")
        )

        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .merge)
        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .merge)

        #expect(try context.fetch(FetchDescriptor<Dog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 2)
    }

    @Test("Слияние доливает только новые записи")
    func mergeAddsOnlyNew() throws {
        let источник = контекст()
        let стич = завестиСтича(в: источник)
        let новая = LogEvent(kind: .water, authorName: "Мама")
        новая.milliliters = 190
        новая.dog = стич
        источник.insert(новая)

        let полный = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "1.0.0")
        )

        // На телефоне уже есть Стич с двумя записями из трёх.
        let телефон = контекст()
        _ = завестиСтича(в: телефон)
        let было = try телефон.fetch(FetchDescriptor<LogEvent>()).count

        let добавлено = try BackupService.restore(
            try BackupService.decode(полный), into: телефон, strategy: .merge
        )
        let стало = try телефон.fetch(FetchDescriptor<LogEvent>()).count

        #expect(добавлено == 3, "все записи из файла новые: идентификаторы у копии свои")
        #expect(стало == было + 3)
        #expect(try телефон.fetch(FetchDescriptor<Dog>()).count == 1, "вторая собака не завелась")
    }

    @Test("Удалённые записи переезжают вместе со следом")
    func deletedKeepTrace() throws {
        let context = контекст()
        let стич = завестиСтича(в: context)
        let удалённая = LogEvent(kind: .note, authorName: "Тео")
        удалённая.note = "ошибся"
        удалённая.deletedAt = Date()
        удалённая.deletedBy = "Тео"
        удалённая.dog = стич
        context.insert(удалённая)

        let данные = try BackupService.encode(
            try BackupService.archive(context: context, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let записи = try новый.fetch(FetchDescriptor<LogEvent>())
        #expect(записи.contains { $0.isDeleted && $0.deletedBy == "Тео" })
        #expect(Diary.active(записи).count == 2, "удалённая в выборки не попадает")
    }

    @Test("Только что добавленное попадает в файл, а не теряется тихо")
    func archiveSeesUnsavedChanges() throws {
        let context = контекст()
        let dog = завестиСтича(в: context)

        // Добавили корм и сразу жмём «сохранить в файл» — так и делают.
        let новый = FoodStock(kind: .wet, brand: "Только что", packGrams: 150,
                              packsLeft: 8, gramsPerDay: 150)
        новый.dog = dog
        context.insert(новый)

        let архив = try BackupService.archive(context: context, appVersion: "1.0.0")
        let корма = архив.dogs.first?.stocks ?? []
        #expect(корма.count == 3, "несохранённое тоже должно уехать в файл")
        #expect(корма.contains { $0.brand == "Только что" })
    }

    // MARK: Все модели схемы

    /// Сколько записей у модели — через открытие экзистенциала, чтобы
    /// пройти все шестнадцать одним циклом.
    private func сколько<T: PersistentModel>(_ model: T.Type, в context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    /// Списки моделей руками дважды расходились со схемой: «Заменить всё»
    /// не трогало пять моделей из шестнадцати. Теперь список один
    /// и берётся из схемы — а этот тест краснеет, если новая модель
    /// появилась в хранилище, а в стирание не попала.
    @Test("Стирание знает каждую модель хранилища")
    func eraseCoversSchema() {
        let вСхеме = Set(Persistence.schema.entities.map(\.name))
        let вСтирании = Set(BackupService.deletionOrder.map { String(describing: $0) })
        #expect(вСхеме == вСтирании, "не стирается: \(вСхеме.subtracting(вСтирании).sorted())")
        #expect(BackupService.deletionOrder.count == вСхеме.count, "модель в списке дважды")
    }

    @Test("«Заменить всё» не оставляет ни одной записи прежнего дневника")
    func replaceErasesEveryModel() throws {
        let context = контекст()
        let стич = завестиСтича(в: context)
        // Каждой модели — хотя бы по одной записи, включая те,
        // что прежний список пропускал.
        let вес = WeightEntry(date: Date(), kg: 4.1); вес.dog = стич; context.insert(вес)
        let течка = HeatRecord(startedAt: Date(), endedAt: nil, note: nil); течка.dog = стич; context.insert(течка)
        let паспорт = DogDocument(title: "Паспорт", image: nil, note: nil); паспорт.dog = стич; context.insert(паспорт)
        let день = DayOut(startedAt: Date()); день.dog = стич; context.insert(день)
        let шаг = TrainingStep(cue: "сидеть", place: "дом", person: "Виктория", distanceMeters: 0, order: 0)
        шаг.dog = стич; context.insert(шаг)
        let занятие = TrainingSession(cue: "сидеть", place: "дом", person: "Виктория", distanceMeters: 0)
        занятие.dog = стич; context.insert(занятие)
        let поездка = Trip(destination: "Лион", startDate: Date(), endDate: Date(), transport: .car)
        поездка.dog = стич; context.insert(поездка)
        context.insert(ProcedureSkill(title: "Дать лапу", detail: "для забора крови"))
        context.insert(Episode(title: "Расстройство", detail: "", startedAt: Date()))
        try context.save()

        for model in BackupService.allModels {
            #expect(try сколько(model, в: context) > 0, "\(model): тест не завёл ни одной записи")
        }

        let пустой = BackupArchive(createdAt: Date(), appVersion: "1.0.0",
                                   dogs: [], members: [], episodes: [])
        try BackupService.restore(пустой, into: context, strategy: .replace)

        for model in BackupService.allModels {
            #expect(try сколько(model, в: context) == 0, "\(model) пережил «Заменить всё»")
        }
    }

    // MARK: Дни с собакой и навыки процедур

    private func завестиДеньИНавык(к собаке: Dog, в context: ModelContext) -> (DayOut, ProcedureSkill) {
        let день = DayOut(startedAt: Date().addingTimeInterval(-5 * 3600), plannedHours: 6)
        день.endedAt = Date().addingTimeInterval(-3600)
        день.note = "к ветеринару и в гости"
        день.dog = собака
        context.insert(день)

        let навык = ProcedureSkill(title: "Стоять при осмотре", detail: "перед УЗИ",
                                   targetDate: Date().addingTimeInterval(7 * 86_400))
        навык.record(success: true)
        навык.record(success: false)
        context.insert(навык)
        return (день, навык)
    }

    @Test("Дни с собакой и навыки процедур переезжают в файле")
    func daysOutAndSkillsRoundTrip() throws {
        let старый = контекст()
        let стич = завестиСтича(в: старый)
        let (день, навык) = завестиДеньИНавык(к: стич, в: старый)

        let данные = try BackupService.encode(try BackupService.archive(context: старый, appVersion: "1.0.0"))
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let дни = try новый.fetch(FetchDescriptor<DayOut>())
        #expect(дни.count == 1)
        #expect(дни.first?.id == день.id)
        #expect(дни.first?.plannedHours == 6)
        #expect(дни.first?.note == "к ветеринару и в гости")
        #expect(дни.first?.endedAt != nil)
        #expect(дни.first?.dog?.name == "Стич", "день приезжает к своей собаке")

        let навыки = try новый.fetch(FetchDescriptor<ProcedureSkill>())
        #expect(навыки.count == 1)
        #expect(навыки.first?.id == навык.id)
        #expect(навыки.first?.title == "Стоять при осмотре")
        #expect(навыки.first?.attempts == 2)
        #expect(навыки.first?.successes == 1)
        #expect(навыки.first?.statusRaw == навык.statusRaw)
        #expect(навыки.first?.targetDate != nil)
    }

    @Test("Слияние не задваивает дни с собакой и навыки")
    func daysOutAndSkillsMergeIdempotent() throws {
        let context = контекст()
        let стич = завестиСтича(в: context)
        _ = завестиДеньИНавык(к: стич, в: context)

        let данные = try BackupService.encode(try BackupService.archive(context: context, appVersion: "1.0.0"))
        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .merge)
        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .merge)

        #expect(try context.fetch(FetchDescriptor<DayOut>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProcedureSkill>()).count == 1)
    }

    @Test("Слияние доливает день и навык к уже заведённой собаке")
    func mergeAddsDaysOutAndSkills() throws {
        let источник = контекст()
        let стич = завестиСтича(в: источник)
        _ = завестиДеньИНавык(к: стич, в: источник)
        let данные = try BackupService.encode(try BackupService.archive(context: источник, appVersion: "1.0.0"))

        let телефон = контекст()
        _ = завестиСтича(в: телефон)
        try BackupService.restore(try BackupService.decode(данные), into: телефон, strategy: .merge)

        let дни = try телефон.fetch(FetchDescriptor<DayOut>())
        #expect(дни.count == 1)
        #expect(дни.first?.dog?.name == "Стич")
        #expect(try телефон.fetch(FetchDescriptor<ProcedureSkill>()).count == 1)
        #expect(try телефон.fetch(FetchDescriptor<Dog>()).count == 1)
    }

    @Test("Старый файл без дней с собакой и навыков читается и восстанавливается")
    func oldArchiveWithoutDaysOutAndSkills() throws {
        let context = контекст()
        let стич = завестиСтича(в: context)
        _ = завестиДеньИНавык(к: стич, в: context)
        let данные = try BackupService.encode(try BackupService.archive(context: context, appVersion: "1.0.0"))

        // Файл, записанный до появления полей: вырезаем их из JSON,
        // а не ставим nil в структуре — так проверяется именно чтение.
        var json = try #require(try JSONSerialization.jsonObject(with: данные) as? [String: Any])
        json.removeValue(forKey: "procedureSkills")
        var собаки = try #require(json["dogs"] as? [[String: Any]])
        for i in собаки.indices { собаки[i].removeValue(forKey: "daysOut") }
        json["dogs"] = собаки
        let старые = try JSONSerialization.data(withJSONObject: json)

        let архив = try BackupService.decode(старые)
        #expect(архив.procedureSkills == nil)
        #expect(архив.dogs.first?.daysOut == nil)

        let новый = контекст()
        try BackupService.restore(архив, into: новый, strategy: .replace)
        #expect(try новый.fetch(FetchDescriptor<Dog>()).count == 1)
        #expect(try новый.fetch(FetchDescriptor<DayOut>()).isEmpty)
        #expect(try новый.fetch(FetchDescriptor<ProcedureSkill>()).isEmpty)
    }

    @Test("Чужой файл отвергается с внятным объяснением")
    func rejectsGarbage() {
        let мусор = Data("это не бэкап".utf8)
        #expect(throws: BackupError.self) {
            try BackupService.decode(мусор)
        }
    }

    @Test("Файл из будущей версии не читаем и говорим почему")
    func rejectsFutureFormat() throws {
        var архив = BackupArchive(createdAt: Date(), appVersion: "9.0.0",
                                  dogs: [], members: [], episodes: [])
        архив.formatVersion = BackupService.currentFormatVersion + 1
        let данные = try BackupService.encode(архив)

        do {
            _ = try BackupService.decode(данные)
            Issue.record("должен был отказаться")
        } catch let error as BackupError {
            #expect(error.errorDescription?.contains("Обнови") == true)
        }
    }

    @Test("Имя файла содержит дату — их складывают в одну папку годами")
    func fileNameHasDate() {
        let дата = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        #expect(BackupService.fileName(at: дата) == "togo-2026-08-25.json")
    }

    @Test("Сводка по файлу читается человеком")
    func summaryReadable() throws {
        let context = контекст()
        _ = завестиСтича(в: context)
        let архив = try BackupService.archive(context: context, appVersion: "1.0.0")
        #expect(архив.summary.contains("1 собака"))
        #expect(архив.summary.contains("2 записи"))
    }
}
