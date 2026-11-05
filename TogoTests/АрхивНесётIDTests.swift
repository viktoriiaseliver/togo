import Testing
import Foundation
import SwiftData
@testable import Togo

/// Архив несёт `id` записей — и восстановление их сохраняет.
///
/// # Что оплатило этот набор
///
/// Решение Виктории 05.11.2026: «Хранить id в архиве». До него `id`
/// нёс один `EventSnapshot`; восстановление при включённом общем
/// дневнике рождало новые `UUID` у собаки, весов, схем, доз, ухода,
/// документов, медкнижки и клиник. Обмен узнаёт запись по `id` — и
/// у второго человека старые записи оставались, а восстановленные
/// приезжали **дублями**: вторая «Стич» со всей историей.
///
/// # Что здесь мерится и чего нет
///
/// ```
/// мерится     id в хранилище до выгрузки и после восстановления —
///             то, по чему обмен узнаёт запись
/// НЕ мерится  сам обмен: CloudKit в тестах нет. Что делает с этими
///             id `SharedDiaryMerge` у второго человека, разобрано
///             в голове `BackupService.restore` по коду, не прогоном
/// ```
///
/// Отрицательный контроль у каждого круга — тот же файл с вырезанными
/// `id` (`безID`), то есть ровно «старый архив». На нём те же
/// проверки обязаны давать обратный ответ: иначе зелёный был бы
/// про то, что хранилище само сохраняет id, а не про архив.
@Suite("Архив несёт id: восстановление узнаёт те же записи")
@MainActor
struct АрхивНесётIDTests {

    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    private static let день = Date(timeIntervalSince1970: 1_790_000_000)

    /// Дневник, в котором есть по записи КАЖДОГО вида с `id`.
    private func наполнить(_ к: ModelContext) {
        let стич = Dog(name: "Стич", weightKg: 4.1)
        к.insert(стич)
        let клиника = Clinic(name: "Vet Riviera")
        к.insert(клиника)

        let запись = LogEvent(kind: .outing, date: Self.день, authorName: "Виктория")
        запись.dog = стич
        к.insert(запись)
        let вес = WeightEntry(date: Self.день, kg: 4.35)
        вес.dog = стич
        к.insert(вес)
        let дело = CareTask(title: "Бешенство", detail: "", intervalDays: 365, category: .medical)
        дело.clinic = клиника
        дело.dog = стич
        к.insert(дело)
        let схема = Medication(name: "Lévothyrox", doseText: "66 мкг",
                               times: [7 * 60], fastingMinutes: 45)
        схема.dog = стич
        к.insert(схема)
        let доза = DoseRecord(scheduledAt: Self.день.addingTimeInterval(7 * 3600))
        доза.medication = схема
        к.insert(доза)
        let анализ = LabResult(sampledOn: Self.день, indicator: "Т4", section: "гормоны",
                               laboratory: "IDEXX", reportNumber: "VF1")
        анализ.dog = стич
        к.insert(анализ)
        let визит = VetVisit(date: Self.день, doctor: "Кочубина")
        визит.clinic = клиника
        визит.dog = стич
        к.insert(визит)
        let диагноз = Diagnosis(wording: "гипотиреоз", madeOn: Self.день)
        диагноз.dog = стич
        к.insert(диагноз)
        let рецепт = Prescription(number: "8935331", date: Self.день, medicationName: "Lévothyrox")
        рецепт.dog = стич
        к.insert(рецепт)
        let документ = DogDocument(title: "Паспорт", image: nil, note: nil)
        документ.dog = стич
        к.insert(документ)
        let запас = FoodStock(kind: .dry, brand: "Acana", packGrams: 3000,
                              packsLeft: 1, gramsPerDay: 60)
        запас.dog = стич
        к.insert(запас)
        let течка = HeatRecord(startedAt: Self.день)
        течка.dog = стич
        к.insert(течка)
        let выезд = DayOut(startedAt: Self.день, plannedHours: 6)
        выезд.dog = стич
        к.insert(выезд)
        let шаг = TrainingStep(cue: "место", place: "кухня", person: "Виктория",
                               distanceMeters: 2, order: 1)
        шаг.dog = стич
        к.insert(шаг)
        let занятие = TrainingSession(cue: "место", place: "кухня",
                                      person: "Виктория", distanceMeters: 2)
        занятие.startedAt = Self.день
        занятие.dog = стич
        к.insert(занятие)
        let поездка = Trip(destination: "Ницца", startDate: Self.день,
                           endDate: Self.день.addingTimeInterval(86_400), transport: .car)
        поездка.dog = стич
        к.insert(поездка)
        к.insert(FamilyMember(name: "Виктория", role: .owner, isMe: true))
        к.insert(Episode(title: "Реакция на самокаты", detail: "", startedAt: Self.день,
                         dogID: стич.id))
        к.insert(ProcedureSkill(title: "Стоять при осмотре", detail: ""))
    }

    /// `id` всего, что лежит в хранилище, — по видам.
    ///
    /// **Массивом, а не множеством**: два объекта с одним id множество
    /// схлопнуло бы в один, и «те же id» прошло бы на дубле.
    private func idПоВидам(_ к: ModelContext) throws -> [String: [UUID]] {
        // Построчно, а не литералом словаря: двадцать одно тяжёлое
        // выражение в одном литерале — работа типизатору, а не тесту.
        var итог: [String: [UUID]] = [:]
        итог["собаки"] = try к.fetch(FetchDescriptor<Dog>()).map(\.id)
        итог["клиники"] = try к.fetch(FetchDescriptor<Clinic>()).map(\.id)
        итог["лента"] = try к.fetch(FetchDescriptor<LogEvent>()).map(\.id)
        итог["веса"] = try к.fetch(FetchDescriptor<WeightEntry>()).map(\.id)
        итог["дела ухода"] = try к.fetch(FetchDescriptor<CareTask>()).map(\.id)
        итог["схемы"] = try к.fetch(FetchDescriptor<Medication>()).map(\.id)
        итог["дозы"] = try к.fetch(FetchDescriptor<DoseRecord>()).map(\.id)
        итог["анализы"] = try к.fetch(FetchDescriptor<LabResult>()).map(\.id)
        итог["визиты"] = try к.fetch(FetchDescriptor<VetVisit>()).map(\.id)
        итог["диагнозы"] = try к.fetch(FetchDescriptor<Diagnosis>()).map(\.id)
        итог["рецепты"] = try к.fetch(FetchDescriptor<Prescription>()).map(\.id)
        итог["документы"] = try к.fetch(FetchDescriptor<DogDocument>()).map(\.id)
        итог["запасы"] = try к.fetch(FetchDescriptor<FoodStock>()).map(\.id)
        итог["течки"] = try к.fetch(FetchDescriptor<HeatRecord>()).map(\.id)
        итог["выезды"] = try к.fetch(FetchDescriptor<DayOut>()).map(\.id)
        итог["шаги"] = try к.fetch(FetchDescriptor<TrainingStep>()).map(\.id)
        итог["занятия"] = try к.fetch(FetchDescriptor<TrainingSession>()).map(\.id)
        итог["поездки"] = try к.fetch(FetchDescriptor<Trip>()).map(\.id)
        итог["люди"] = try к.fetch(FetchDescriptor<FamilyMember>()).map(\.id)
        итог["эпизоды"] = try к.fetch(FetchDescriptor<Episode>()).map(\.id)
        итог["навыки"] = try к.fetch(FetchDescriptor<ProcedureSkill>()).map(\.id)
        return итог
    }

    private func счёт(_ id: [String: [UUID]]) -> [String: Int] {
        id.mapValues(\.count)
    }

    private func множества(_ id: [String: [UUID]]) -> [String: Set<UUID>] {
        id.mapValues { Set($0) }
    }

    /// Тот же файл, но **без `id` у всех снимков, кроме ленты** —
    /// то есть ровно архив, снятый до 05.11.2026. У ленты `id`
    /// обязателен с самого начала, и вырезать его значило бы получить
    /// файл, которого не бывает.
    ///
    /// Вырезается в JSON, а не в структуре: так проверяется именно
    /// чтение файла без ключа, а не присвоение `nil` в памяти.
    private func безID(_ данные: Data) throws -> Data {
        func вырезать(_ узел: Any, родитель: String?) -> Any {
            if var словарь = узел as? [String: Any] {
                if родитель != "events" { словарь.removeValue(forKey: "id") }
                // Ссылка дозы на ожидаемую схему — тоже новое поле.
                словарь.removeValue(forKey: "awaitedMedicationID")
                for (ключ, значение) in словарь {
                    словарь[ключ] = вырезать(значение, родитель: ключ)
                }
                return словарь
            }
            if let массив = узел as? [Any] {
                return массив.map { вырезать($0, родитель: родитель) }
            }
            return узел
        }
        let дерево = try JSONSerialization.jsonObject(with: данные)
        return try JSONSerialization.data(withJSONObject: вырезать(дерево, родитель: nil))
    }

    // MARK: Тесты

    @Test("Выгрузить → заменить: у каждого вида те же id")
    func заменитьСохраняетID() throws {
        let источник = контекст()
        наполнить(источник)
        try источник.save()
        let былоСырое = try idПоВидам(источник)
        let было = множества(былоСырое)

        // Контроль ПЕРВЫМ: было что сравнивать. Пустой вид даёт
        // «те же id» на двух пустых множествах — всегда.
        let пустые = было.filter { $0.value.isEmpty }.keys.sorted()
        #expect(пустые.isEmpty, "в фикстуре пусты виды: \(пустые) — сравнивать нечего")

        let данные = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "тест"))

        // Новый телефон, «Заменить всё».
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый, strategy: .replace)
        let сталоСырое = try idПоВидам(новый)
        let стало = множества(сталоСырое)
        // Чей эпизод (V10) указывает на ту же собаку — её id тоже приехал.
        let эпизод = try #require(try новый.fetch(FetchDescriptor<Episode>()).first)
        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        let чей = try #require(эпизод.dogID, "эпизод собаки после восстановления стал общим")
        #expect(чей == собака.id, "эпизод указывает в никуда: dogID не пережил круг")
        #expect(счёт(сталоСырое) == счёт(былоСырое), """
            число записей после «Заменить всё» \(счёт(сталоСырое)) \
            против \(счёт(былоСырое)) — дубль с тем же id?
            """)

        var разошлось: [String] = []
        for (вид, ids) in было.sorted(by: { $0.key < $1.key }) where стало[вид] != ids {
            разошлось.append("\(вид): было \(ids.count), совпало \(ids.intersection(стало[вид] ?? []).count)")
        }
        #expect(разошлось.isEmpty, """
            после «Заменить всё» у записей другие id: \
            \(разошлось.joined(separator: " · ")). Обмен узнаёт запись \
            по id — восстановленная с новым id уедет второму человеку \
            ДУБЛЕМ, а старая у него останется.
            """)

        // Тот же телефон, «Заменить всё» поверх себя: стирание и вставка
        // тех же id в одном сохранении — путь, которого раньше не было
        // ни у одного вида, кроме ленты.
        try BackupService.restore(try BackupService.decode(данные), into: источник, strategy: .replace)
        let поверхСебя = try idПоВидам(источник)
        #expect(множества(поверхСебя) == было, "«Заменить всё» поверх своего же дневника изменило набор id")
        #expect(счёт(поверхСебя) == счёт(былоСырое), """
            «Заменить всё» поверх своего же дневника оставило рядом \
            старые объекты: \(счёт(поверхСебя)) против \(счёт(былоСырое)). \
            С одним id это два объекта, которые обмен склеит по-своему.
            """)

        // Отрицательный контроль: старый файл без id обязан дать
        // ДРУГИЕ id. Не даёт — значит зелёный выше не про архив.
        let старый = контекст()
        try BackupService.restore(try BackupService.decode(try безID(данные)),
                                  into: старый, strategy: .replace)
        let безIdСтало = множества(try idПоВидам(старый))
        #expect(безIdСтало["собаки"]?.isDisjoint(with: было["собаки"] ?? []) == true, """
            файл БЕЗ id восстановил собаку с прежним id — значит id \
            берётся не из файла, и проверка выше ничего не доказывает.
            """)
        #expect(безIdСтало["лента"] == было["лента"], "id ленты обязателен и в старом файле")
    }

    @Test("Долить тот же файл после переименований — не дублирует ни один вид")
    func доливкаПоIDНеДублирует() throws {
        let источник = контекст()
        наполнить(источник)
        try источник.save()
        let данные = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "тест"))

        // Телефон второго человека: тот же дневник (те же id),
        // а потом он переименовал то, по чему узнаёт естественный ключ.
        // Без id доливка узнала бы эти записи только по содержанию —
        // и не узнала бы.
        func телефонПослеПравок() throws -> ModelContext {
            let телефон = контекст()
            try BackupService.restore(try BackupService.decode(данные), into: телефон, strategy: .replace)
            let стич = try #require(try телефон.fetch(FetchDescriptor<Dog>()).first)
            стич.name = "Стич Второй"
            let дело = try #require(стич.careTasks.first)
            дело.title = "Бешенство (Nobivac)"
            let схема = try #require(стич.medications.first)
            схема.name = "Левотироксин"
            let вес = try #require(стич.weights.first)
            вес.kg = 4.4
            let поездка = try #require(стич.trips.first)
            поездка.destination = "Ницца, вокзал"
            try телефон.save()
            return телефон
        }

        let телефон = try телефонПослеПравок()
        let было = счёт(try idПоВидам(телефон))
        let добавлено = try BackupService.restore(try BackupService.decode(данные),
                                                  into: телефон, strategy: .merge)
        let стало = счёт(try idПоВидам(телефон))

        var задвоилось: [String] = []
        for (вид, n) in стало.sorted(by: { $0.key < $1.key }) where n != было[вид] {
            задвоилось.append("\(вид): \(было[вид] ?? 0) → \(n)")
        }
        #expect(задвоилось.isEmpty, """
            долив того же файла поверх переименованных записей завёл \
            дубли: \(задвоилось.joined(separator: " · ")). Запись с тем \
            же id — та же запись, как бы её ни переименовали.
            """)
        #expect(добавлено == 0, "долив своего же файла сообщил о \(добавлено) новых записях")
        // Профиль дополняет пустое и не трогает вписанное — кличка
        // осталась той, что дал человек, а не вернулась к файлу.
        #expect(try телефон.fetch(FetchDescriptor<Dog>()).first?.name == "Стич Второй")

        // Отрицательный контроль: тот же долив СТАРЫМ файлом (без id)
        // обязан задвоить хотя бы собаку — она переименована, и узнать
        // её по кличке нечем. Не задвоил — тест выше зелен не по id.
        let контрольный = try телефонПослеПравок()
        let доКонтроля = счёт(try idПоВидам(контрольный))
        try BackupService.restore(try BackupService.decode(try безID(данные)),
                                  into: контрольный, strategy: .merge)
        let послеКонтроля = счёт(try idПоВидам(контрольный))
        #expect((послеКонтроля["собаки"] ?? 0) > (доКонтроля["собаки"] ?? 0), """
            старый файл без id НЕ завёл вторую собаку поверх \
            переименованной — значит опознание шло не по id, и проверка \
            выше ничего не доказывает.
            """)
    }

    @Test("Эпизоды и навыки при доливке едут по id и не задваиваются")
    func эпизодыИНавыкиПоID() throws {
        let источник = контекст()
        наполнить(источник)
        try источник.save()
        let данные = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "тест"))

        let телефон = контекст()
        телефон.insert(Dog(name: "Стич", weightKg: 4.2))
        try телефон.save()

        try BackupService.restore(try BackupService.decode(данные), into: телефон, strategy: .merge)
        #expect(try телефон.fetch(FetchDescriptor<Episode>()).count == 1,
                "эпизод с id не доехал при доливке")
        #expect(try телефон.fetch(FetchDescriptor<ProcedureSkill>()).count == 1,
                "навык с id не доехал при доливке")

        try BackupService.restore(try BackupService.decode(данные), into: телефон, strategy: .merge)
        #expect(try телефон.fetch(FetchDescriptor<Episode>()).count == 1, "эпизод задвоился")
        #expect(try телефон.fetch(FetchDescriptor<ProcedureSkill>()).count == 1, "навык задвоился")

        // Старый файл без id — прежнее решение: при доливке
        // эпизодов и навыков не приносит, склейки по названию нет.
        let другой = контекст()
        try BackupService.restore(try BackupService.decode(try безID(данные)),
                                  into: другой, strategy: .merge)
        #expect(try другой.fetch(FetchDescriptor<Episode>()).isEmpty,
                "старый файл без id привёз эпизод при доливке — склейка по названию?")
    }

    @Test("Старый архив без id читается и восстанавливается")
    func старыйАрхивЧитается() throws {
        let источник = контекст()
        наполнить(источник)
        try источник.save()
        let данные = try BackupService.encode(
            try BackupService.archive(context: источник, appVersion: "тест"))
        let старый = try безID(данные)

        // Контроль, что вырезание состоялось: ключа `"id"` в файле
        // осталось ровно столько, сколько записей ленты.
        let вхождений = String(decoding: старый, as: UTF8.self)
            .components(separatedBy: "\"id\"").count - 1
        #expect(вхождений == 1, "в «старом» файле \(вхождений) ключей id, ожидался один (лента)")

        let архив = try BackupService.decode(старый)
        let собака = try #require(архив.dogs.first)
        #expect(собака.id == nil)
        #expect(собака.medications.first?.id == nil)
        #expect(архив.clinics?.first?.id == nil)

        let новый = контекст()
        try BackupService.restore(архив, into: новый, strategy: .replace)
        let стало = счёт(try idПоВидам(новый))
        let было = счёт(try idПоВидам(источник))
        #expect(стало == было, "старый файл восстановился не целиком: \(стало) против \(было)")

        // Решение о версии формата — разбор у `BackupArchive.formatVersion`:
        // id добавлены опциональными, и старые сборки (версия 1) читают
        // новый файл, отбрасывая лишние ключи. Поднять версию — значит
        // отказать им «обнови Togo» на файле, который они прочитать могут.
        #expect(BackupService.currentFormatVersion == 1, """
            версия формата поднята. Новые поля id опциональны; подъём \
            версии ломает чтение нового файла у старых сборок. Если поле \
            стало обязательным — поправь этот тест вместе с разбором \
            у `BackupArchive.formatVersion`.
            """)
    }

    /// Путь отказа: опознание по id идёт выборками до вставки, и отказ
    /// записи после него обязан дойти до экрана, а не превратиться
    /// в «Добавлено новых записей».
    @Test("Долив по id в незаписывающее хранилище бросает, а не молчит")
    func отказДоливаНеМолчит() throws {
        let источник = контекст()
        наполнить(источник)
        try источник.save()
        let архив = try BackupService.archive(context: источник, appVersion: "тест")

        let запертый = try НеЗаписывающееХранилище.контекст { пишущий in
            // Тот же дневник уже лежит — с теми же id, — кроме одного
            // взвешивания: ему и доливаться.
            try BackupService.restore(архив, into: пишущий, strategy: .replace)
            for вес in try пишущий.fetch(FetchDescriptor<WeightEntry>()) {
                пишущий.delete(вес)
            }
        }
        #expect(try запертый.fetch(FetchDescriptor<WeightEntry>()).isEmpty,
                "фикстура негодна: взвешивание не удалено, доливать нечего")
        #expect(throws: (any Error).self) {
            _ = try BackupService.restore(архив, into: запертый, strategy: .merge)
        }
    }
}
