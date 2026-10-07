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

    /// Медицинская карточка переживает переустановку целиком.
    ///
    /// **Замер 07.10.2026: архив терял 38 скалярных полей** — семнадцать
    /// у собаки, четыре у дела ухода, тринадцать у схемы лечения,
    /// четыре у дозы. Среди них номер чипа, номер паспорта, номер
    /// страховки, врач и клиника с телефонами, приметы для объявления
    /// о пропаже, **дата прививки**, **единица дозы**, срок курса, срок
    /// годности, запас и **отметки пропущенных доз**.
    ///
    /// Сторож паритета (`ArchiveParityTests`) этого не ловил и не мог:
    /// он проверяет каскадные СВЯЗИ, то есть что коллекции уезжают.
    ///
    /// > **Сторож на связи не видит полей, а медицинская карточка
    /// > состоит из полей.**
    ///
    /// Поэтому здесь круговой тест: заполнить ВСЁ → выгрузить →
    /// восстановить в пустое хранилище → сверить поимённо. Без него
    /// тридцать восемь полей уезжали в ноль молча, и ни один
    /// существующий тест этого не замечал: все они проверяли то, что
    /// в снимке есть.
    @Test("Медкнижка переезжает целиком: тридцать восемь полей, которых архив не нёс")
    func медкнижкаПереезжаетЦеликом() throws {
        let старый = контекст()
        let стич = завестиСтича(в: старый)

        стич.sexRaw = DogSex.female.rawValue
        стич.isNeutered = true
        стич.wakeMinuteOfDay = 6 * 60 + 15
        стич.sleepMinuteOfDay = 22 * 60 + 45
        стич.chipNumber = "250269606000000"
        стич.passportNumber = "FR 123456"
        стич.insuranceNumber = "POL-77-2026"
        стич.vetName = "д-р Моро"
        стич.vetPhone = "+33 4 93 00 00 00"
        стич.clinicName = "Clinique des Alpes"
        стич.clinicPhone = "+33 4 93 11 11 11"
        стич.distinctiveMarks = "белое пятно на груди, шрам на левой лапе"
        стич.sitterFood = "60 г утром и вечером"
        стич.sitterDose = "½ таблетки в 8:00"
        стич.sitterWalks = "7:00, 13:00, 19:00"
        стич.sitterForbidden = "курица, кукуруза"
        стич.sitterEscalation = "кровь или рвота — звонить сразу"

        let прививка = CareTask(title: "Бешенство", detail: "Nobivac Rabies",
                                intervalDays: 365, category: .medical)
        прививка.scheduledDate = Date(timeIntervalSince1970: 1_790_000_000)
        прививка.remindDaysBefore = 14
        прививка.streak = 3
        прививка.dog = стич
        старый.insert(прививка)

        let схема = try #require(стич.medications.first)
        схема.unitRaw = MedUnit.tab.rawValue
        схема.minutesAfterMeal = 45
        схема.courseEnd = Date(timeIntervalSince1970: 1_795_000_000)
        схема.expiry = Date(timeIntervalSince1970: 1_800_000_000)
        схема.openedAt = Date(timeIntervalSince1970: 1_780_000_000)
        схема.shelfAfterOpenDays = 28
        схема.remindBeforeExpiry = true
        схема.stockLeft = 17
        схема.stockTotal = 30
        схема.stockLeftAmount = 8.5
        схема.packAmount = 30
        схема.canGiveOutside = true
        схема.doseSlotsData = [DoseSlot(minuteOfDay: 7 * 60, quantity: 0.5)]

        let пропущенная = DoseRecord(scheduledAt: Date(timeIntervalSince1970: 1_770_000_000))
        пропущенная.skippedAt = Date(timeIntervalSince1970: 1_770_003_600)
        пропущенная.skippedBy = "Виктория"
        пропущенная.medication = схема
        старый.insert(пропущенная)
        try старый.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)

        // Собака: семнадцать полей.
        #expect(собака.sexRaw == DogSex.female.rawValue, "пол потерян — с ним уходит календарь течки")
        #expect(собака.isNeutered == true)
        #expect(собака.wakeMinuteOfDay == 6 * 60 + 15, "режим дня потерян")
        #expect(собака.sleepMinuteOfDay == 22 * 60 + 45)
        #expect(собака.chipNumber == "250269606000000", "номер чипа потерян — его спрашивают в клинике")
        #expect(собака.passportNumber == "FR 123456")
        #expect(собака.insuranceNumber == "POL-77-2026")
        #expect(собака.vetName == "д-р Моро", "врач потерян — он нужен, когда хозяина нет рядом")
        #expect(собака.vetPhone == "+33 4 93 00 00 00")
        #expect(собака.clinicName == "Clinique des Alpes")
        #expect(собака.clinicPhone == "+33 4 93 11 11 11")
        #expect(собака.distinctiveMarks?.isEmpty == false, "приметы потеряны — это объявление о пропаже")
        #expect(собака.sitterFood == "60 г утром и вечером")
        #expect(собака.sitterDose == "½ таблетки в 8:00")
        #expect(собака.sitterWalks == "7:00, 13:00, 19:00")
        #expect(собака.sitterForbidden == "курица, кукуруза")
        #expect(собака.sitterEscalation == "кровь или рвота — звонить сразу")

        // Уход: дата прививки.
        let восстановленнаяПрививка = try #require(
            собака.careTasks.first { $0.title == "Бешенство" })
        #expect(восстановленнаяПрививка.scheduledDate == прививка.scheduledDate, """
            дата прививки потеряна. Медкнижка без дат прививок — это
            «каждые 365 дней от неизвестного дня», и ветеринару она
            не отвечает ни на один вопрос.
            """)
        #expect(восстановленнаяПрививка.remindDaysBefore == 14)
        #expect(восстановленнаяПрививка.streak == 3)
        #expect(восстановленнаяПрививка.kindRaw == прививка.kindRaw)

        // Схема лечения: тринадцать полей.
        let восстановленнаяСхема = try #require(собака.medications.first)
        #expect(восстановленнаяСхема.unitRaw == MedUnit.tab.rawValue, """
            единица дозы потеряна. «0,5» без единицы не значит ничего:
            половина таблетки, половина миллилитра и половина капли —
            три разные дозы, и ошибка здесь не путаница в дневнике,
            а передозировка.
            """)
        #expect(восстановленнаяСхема.minutesAfterMeal == 45)
        #expect(восстановленнаяСхема.courseEnd == схема.courseEnd, "срок курса потерян")
        #expect(восстановленнаяСхема.expiry == схема.expiry, "срок годности потерян")
        #expect(восстановленнаяСхема.openedAt == схема.openedAt)
        #expect(восстановленнаяСхема.shelfAfterOpenDays == 28)
        #expect(восстановленнаяСхема.remindBeforeExpiry == true)
        #expect(восстановленнаяСхема.stockLeft == 17, "запас потерян — по нему считается «пора покупать»")
        #expect(восстановленнаяСхема.stockTotal == 30)
        #expect(восстановленнаяСхема.stockLeftAmount == 8.5)
        #expect(восстановленнаяСхема.packAmount == 30)
        #expect(восстановленнаяСхема.canGiveOutside == true)
        #expect(восстановленнаяСхема.doseSlotsData.count == 1)
        #expect(восстановленнаяСхема.doseSlotsData.first?.quantity == 0.5)

        // Доза: пропуск — факт лечения.
        let пропуск = try #require(
            восстановленнаяСхема.doses.first { $0.skippedAt != nil })
        #expect(пропуск.skippedBy == "Виктория", """
            отметка «пропущено» потеряна. Врач спрашивает «сколько раз
            пропустили», и архив отвечал «ни разу» вместо правды:
            отсутствие отметки читается как «дали».
            """)
    }

    /// Навыки подготовки к процедурам — их снимка не было ВОВСЕ.
    ///
    /// Замер `togo-1e`, проверен этой сессией со стороны сборщика:
    /// слово `ProcedureSkill` встречалось в `Backup.swift`
    /// и `BackupArchive.swift` **ноль раз**.
    ///
    /// **Корневым массивом, а не полем собаки, и это не стиль:**
    /// у `ProcedureSkill` нет связи с собакой вовсе — ни `dog`,
    /// ни обратной. Положить его внутрь `DogSnapshot` значило бы
    /// придумать принадлежность, которой в модели нет, и при двух
    /// собаках решать за человека, чей навык.
    ///
    /// Тест нужен именно круговой: сторож паритета не увидел бы
    /// проводки — его список моделей написан руками, и новый снимок
    /// в него не попадает сам.
    @Test("Навыки процедур переезжают — корневым списком, без собаки")
    func навыкиПроцедурПереезжают() throws {
        let старый = контекст()
        _ = завестиСтича(в: старый)
        let навык = ProcedureSkill(title: "Дать лапу",
                                   detail: "для забора крови",
                                   targetDate: Date(timeIntervalSince1970: 1_800_000_000))
        навык.statusRaw = SkillStatus.learning.rawValue
        навык.successes = 7
        навык.attempts = 10
        старый.insert(навык)
        try старый.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let навыки = try новый.fetch(FetchDescriptor<ProcedureSkill>())
        #expect(навыки.count == 1, """
            навыков восстановлено \(навыки.count) из одного. Снимка
            у них не было вовсе: человек, переехавший на новый телефон,
            терял подготовку к процедурам целиком — и узнал бы об этом
            у ветеринара.
            """)
        let восстановленный = try #require(навыки.first)
        #expect(восстановленный.title == "Дать лапу")
        #expect(восстановленный.detail == "для забора крови")
        #expect(восстановленный.statusRaw == SkillStatus.learning.rawValue, "ступень навыка потеряна")
        #expect(восстановленный.successes == 7, "накопленный прогресс потерян")
        #expect(восстановленный.attempts == 10)
        #expect(восстановленный.targetDate == навык.targetDate)
    }

    /// «Заменить» обязано чистить навыки, иначе повторное восстановление
    /// их удваивает: опознать «тот же навык» нечем — ни `id` в снимке,
    /// ни связи, а склейка по названию собрала бы в одну группу всё,
    /// что названия не заполнило (наш класс, оплаченный сегодня
    /// четырьмя случаями).
    @Test("Повторное «заменить» не задваивает навыки процедур")
    func навыкиНеЗадваиваются() throws {
        let context = контекст()
        _ = завестиСтича(в: context)
        context.insert(ProcedureSkill(title: "Стоять при осмотре", detail: "у врача"))
        try context.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: context, appVersion: "1.0.0")
        )
        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .replace)
        try BackupService.restore(try BackupService.decode(данные), into: context, strategy: .replace)

        #expect(try context.fetch(FetchDescriptor<ProcedureSkill>()).count == 1, """
            навыки задвоились: «заменить» их не чистит, а опознать
            при вставке нечем.
            """)
    }

    /// Пометка «часа не помню» — оговорка, без которой число лжёт.
    ///
    /// `WalkRhythm:71` отбрасывает записи с `isDayOnly`, прежде чем
    /// считать обычное время выхода, и делает это нарочно: промежуток
    /// между двумя полуночами не промежуток. Архив флаг терял — и после
    /// восстановления дозаписанные «вчера, часа не помню» становились
    /// неотличимы от точных, то есть приложение начинало советовать
    /// время выхода, посчитанное по часам, которых никто не знал.
    ///
    /// **Это потеря не поля, а ОГОВОРКИ:** число остаётся, его граница
    /// исчезает.
    @Test("«Часа не помню» переживает перенос и не превращается в точное время")
    func оговоркаПереживаетПеренос() throws {
        let старый = контекст()
        let стич = завестиСтича(в: старый)
        let дозапись = LogEvent(kind: .outing,
                                date: Date().addingTimeInterval(-86_400),
                                authorName: "Виктория")
        дозапись.isDayOnly = true
        дозапись.enteredAt = Date()
        дозапись.editedBy = "Тео"
        дозапись.origin = .recalled
        дозапись.reactionTrigger = .dog
        дозапись.reactionDistance = .close
        дозапись.dog = стич
        старый.insert(дозапись)
        try старый.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        let восстановленная = try #require(собака.events.first { $0.isDayOnly })
        #expect(восстановленная.isDayOnly, """
            пометка «часа не помню» потеряна. После восстановления
            запись неотличима от точной, и `WalkRhythm` посчитает
            по ней обычное время выхода — то есть приложение скажет
            «обычно выходите в 7» по часам, которых никто не знал.
            """)
        #expect(восстановленная.enteredAt != nil, "когда записали — потеряно")
        #expect(восстановленная.originRaw == дозапись.originRaw, """
            чем записали — потеряно. У дозаписи текстом это главное:
            «разобрано из фразы, а не нажато» говорит второму человеку,
            насколько записи доверять.
            """)
        #expect(восстановленная.reactionTriggerRaw == дозапись.reactionTriggerRaw, """
            на что отреагировала собака — потеряно. Это и есть то,
            ради чего инцидент заводят; без него у человека остаётся
            «был инцидент» без единой детали.
            """)
        #expect(восстановленная.reactionDistanceRaw == дозапись.reactionDistanceRaw)
        #expect(восстановленная.editedBy == "Тео", """
            кто поправил запись — потеряно. Поле заведено с доводом
            «та же причина, что у `deletedBy`», и `deletedBy` проведён,
            а этот нет: рассуждение скопировалось, проводка нет.
            """)
    }

    /// Выезды переживают переустановку — то, чего архив не умел вовсе.
    ///
    /// **До 07.10.2026 `DogSnapshot` их не хранил**, при том что
    /// `TodayScreen` читает выезды запросом и меняет по ним поведение
    /// главного экрана, а «Удалить все данные» про них знает. Человек,
    /// переезжающий на новый телефон, терял их все и узнать об этом
    /// не мог: пустого места на экране не возникает, запись просто
    /// не находится через месяц.
    ///
    /// Круговой тест, а не сверка полей: `ArchiveParityTests` проверяет,
    /// что поле ОБЪЯВЛЕНО, и слеп к тому, заполняется ли оно при сборке
    /// и читается ли при восстановлении. Это и есть разница между
    /// «имя упомянуто» и «от упоминания что-то происходит».
    @Test("Выезды переезжают на новый телефон вместе с собакой")
    func выездыПереезжают() throws {
        let старый = контекст()
        let стич = завестиСтича(в: старый)
        let выезд = DayOut(startedAt: Date().addingTimeInterval(-8 * 3600), plannedHours: 6)
        выезд.endedAt = Date().addingTimeInterval(-2 * 3600)
        выезд.note = "к врачу и по делам"
        выезд.dog = стич
        старый.insert(выезд)
        // Второй — незакрытый: день ещё идёт, и это отдельное состояние.
        let идущий = DayOut(startedAt: Date().addingTimeInterval(-3600), plannedHours: 4)
        идущий.dog = стич
        старый.insert(идущий)
        try старый.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        #expect(собака.daysOut.count == 2, """
            выездов восстановлено \(собака.daysOut.count) из двух.
            Выезд существует только вместе с собакой (связь каскадная),
            то есть он часть её дневника, а не настройка.
            """)
        let закрытый = собака.daysOut.first { $0.endedAt != nil }
        #expect(закрытый?.plannedHours == 6)
        #expect(закрытый?.note == "к врачу и по делам")
        #expect(собака.daysOut.contains { $0.endedAt == nil }, """
            идущий выезд приехал закрытым — «день ещё идёт» потерялось.
            Пустой `endedAt` здесь не отсутствие данных, а состояние.
            """)
    }

    /// Слияние по кличке не склеивает по ПУСТОЙ кличке.
    ///
    /// **Нашлось замером путей, заводящих `Dog`, а не поиском этого
    /// дефекта.** Условие слияния спрашивало
    /// `existingDogNames.contains(snapshot.name)`: если в хранилище
    /// лежит хоть одна безымянная запись, в наборе кличек есть `""`,
    /// и безымянная собака из архива сливалась с ней — её отметки
    /// уезжали чужой записи, про которую мы даже не знаем, что это.
    @Test("Безымянная из архива не сливается с безымянной из хранилища")
    func безымянныеНеСклеиваются() throws {
        let context = контекст()
        // В хранилище — пустая запись, какие человек и видел на кадре.
        let местная = Dog(name: "", weightKg: 0)
        context.insert(местная)
        try context.save()

        // В архиве — ДРУГАЯ безымянная, и у неё история: такой стала
        // настоящая собака, которой кличку затёрло слиянием профиля.
        let источник = контекст()
        let затёртая = завестиСтича(в: источник)
        затёртая.name = ""
        try источник.save()
        let данные = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "1.0.0")
        )

        try BackupService.restore(try BackupService.decode(данные),
                                  into: context, strategy: .merge)

        #expect(местная.events.isEmpty, """
            отметки из архива приписались местной безымянной записи.
            Пустая кличка кличкой не является, и склеивать по ней —
            то же, что склеивать по отсутствию признака: группировка
            по полю со значением по умолчанию собирает в одну группу
            всё, что это поле не заполнило.
            """)
        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 2, """
            собак \(собаки.count): безымянная из архива должна была
            завестись своей записью, а не слиться с местной.
            """)
    }

    /// Обратный край: по НАСТОЯЩЕЙ кличке слияние обязано работать —
    /// иначе человек, доливающий свой архив в свой дневник, получит
    /// вторую «Стич».
    @Test("По настоящей кличке слияние по-прежнему склеивает")
    func поКличкеСклеиваетсяКакПрежде() throws {
        let context = контекст()
        _ = завестиСтича(в: context)
        try context.save()

        let данные = try BackupService.encode(
            try BackupService.archive(context: context, appVersion: "1.0.0")
        )
        try BackupService.restore(try BackupService.decode(данные),
                                  into: context, strategy: .merge)

        #expect(try context.fetch(FetchDescriptor<Dog>()).count == 1, """
            после долива своего же архива собак стало больше одной —
            слияние по кличке перестало работать вовсе.
            """)
    }

    /// Файлы, сохранённые ДО появления выездов в архиве, обязаны
    /// читаться. Поле опциональное именно за этим, и проверяется это
    /// отсутствием ключа, а не пустым массивом: у старого файла ключа
    /// нет вовсе.
    @Test("Файл без выездов читается — у старых файлов этого поля нет")
    func старыйФайлБезВыездовЧитается() throws {
        let старый = контекст()
        _ = завестиСтича(в: старый)
        var архив = try BackupService.archive(context: старый, appVersion: "1.0.0")
        архив.dogs[0].daysOut = nil

        let новый = контекст()
        try BackupService.restore(try BackupService.decode(try BackupService.encode(архив)),
                                  into: новый, strategy: .replace)

        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        #expect(собака.name == "Стич", "файл без выездов не прочитался вовсе")
        #expect(собака.daysOut.isEmpty)
        #expect(собака.events.count == 2, "остальное из файла потерялось")
    }

    /// Третья поверхность дефекта «пустые собаки» (отзыв 06.10.2026,
    /// сборка 271). Архив замыкал круг: безымянная попала в хранилище,
    /// уехала в файл и приезжала обратно после любой починки приёма.
    @Test("Пустая собака из архива не восстанавливается, если за ней ничего нет")
    func безымяннаяБезИсторииНеВосстанавливается() throws {
        let старый = контекст()
        _ = завестиСтича(в: старый)
        // Ровно то, что видел человек: кличка пустая, вес нулевой,
        // за записью ничего не стоит.
        let пустая = Dog(name: "", weightKg: 0)
        старый.insert(пустая)

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let собаки = try новый.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, """
            восстановлено \(собаки.count) собак вместо одной: безымянная
            приехала из архива обратно. Клички: \
            \(собаки.map { $0.name.isEmpty ? "«»" : $0.name })
            """)
        #expect(собаки.first?.name == "Стич")
    }

    /// Обратный край, и он важнее первого.
    ///
    /// **Писать только «безымянные не восстанавливаются» нельзя:**
    /// отрицательное утверждение выполняется и тогда, когда
    /// не восстановилось вообще ничего. А цена ошибки здесь — не лишняя
    /// строка в списке, а дневник человека: все одиннадцать связей `Dog`
    /// каскадные, и безымянной бывает настоящая собака, которой кличку
    /// затёрло слиянием.
    @Test("Безымянная собака с историей из архива восстанавливается целиком")
    func безымяннаяСИсториейВосстанавливается() throws {
        let старый = контекст()
        let затёртая = завестиСтича(в: старый)
        // Та же собака, у которой кличку обнулило слияние: история
        // на месте, подписи нет.
        затёртая.name = ""

        let данные = try BackupService.encode(
            try BackupService.archive(context: старый, appVersion: "1.0.0")
        )
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)

        let собаки = try новый.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, """
            собака с историей не восстановилась из-за пустой клички —
            починка косметики съела дневник.
            """)
        #expect(собаки.first?.events.count == 2, """
            отметки потеряны: восстановили собаку, но не то, ради чего
            её восстанавливают.
            """)
        #expect(собаки.first?.medications.count == 1)
        #expect(собаки.first?.stocks.count == 2)
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
