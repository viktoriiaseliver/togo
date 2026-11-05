import Foundation
import SwiftData
import Testing
@testable import Togo

/// Три поля, которые не ехали в архив, — проверены **значением**,
/// а не наличием имени.
///
/// Заведено 07.10.2026, `togo-1e`. Сторож `ArchiveFillTests` закрывает
/// формальную сторону (поле объявлено и заполняется), `ArchiveParityTests`
/// — сверку имён. Ни один из них не отвечает на вопрос «вернулось ли
/// ТО ЖЕ значение», а именно он здесь и стоит: круг
/// `archive → encode → decode → restore` на настоящих числах.
///
/// ## Почему эти три, и почему они не «даты, ну и ладно»
///
/// ```
/// FoodStock.countedAt       usedGrams(at:) на нём СТОИТ: guard let countedAt
///                           потеряв его, usedGrams отдаёт ноль, remainingGrams —
///                           полный мешок, и человек читает «хватит на 30 дней»
///                           там, где корм кончается завтра
/// Episode.lastIncidentAt    isOngoing сравнивает now − lastIncidentAt < 48 ч,
///                           а в init оно равно startedAt: без восстановления
///                           эпизод с инцидентами в течение пяти дней
///                           объявился бы законченным задним числом
/// DoseRecord.awaited…Name   единственный след того, чего доза ждёт, если
///                           схема до неё не доехала
/// ```
///
/// **`awaitedMedicationID` до 05.11.2026 не ехал**: `Medication.id`
/// в архив не шёл, и восстановленная ссылка указывала бы в никуда.
/// С решением «хранить id в архиве» id схемы едет — и ссылка тоже,
/// по условию, записанному в реестре `ArchiveParityTests` заранее.
@Suite("Три поля архива — по значению", .serialized)
struct ArchiveFieldValueTests {

    /// Хранилище в памяти: круг проверяется на значениях, а не на диске.
    private func контейнер() throws -> ModelContainer {
        try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(schema: Persistence.schema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        )
    }

    /// Первым — проверка, что кругу было что нести.
    ///
    /// Без неё остальные молчали бы так же, как при всём хорошем:
    /// пустой архив проходит любую сверку полей, которых в нём нет.
    @Test("Кругу было что нести: архив непустой")
    func кругуБылоЧтоНести() throws {
        let container = try контейнер()
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 8.1)
        context.insert(dog)
        let stock = FoodStock(kind: .dry, brand: "тест", packGrams: 3000,
                             packsLeft: 1, gramsPerDay: 100)
        stock.dog = dog
        context.insert(stock)
        let archive = try BackupService.archive(context: context, appVersion: "тест")
        #expect(archive.dogs.count == 1)
        #expect(archive.dogs.first?.stocks?.isEmpty == false,
                "запас в архив не попал — остальные проверки измеряли бы пустоту")
    }

    @Test("Дата пересчёта запаса переживает круг — иначе число на экране врёт")
    func countedAtПереживает() throws {
        let пятьДнейНазад = Calendar.current.date(byAdding: .day, value: -5,
                                                  to: Date())!
        let container = try контейнер()
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 8.1)
        context.insert(dog)
        let stock = FoodStock(kind: .dry, brand: "Acana", packGrams: 1000,
                             packsLeft: 1, gramsPerDay: 100,
                             countedAt: пятьДнейНазад)
        stock.dog = dog
        context.insert(stock)

        let круг = try кругом(context: context)
        let вернулся = try #require(круг.dogs.first?.stocks?.first)
        #expect(тотЖеМомент(вернулся.countedAt, пятьДнейНазад),
                "дата пересчёта не вернулась — usedGrams начнёт считать с нуля")
    }

    @Test("Последний инцидент эпизода переживает круг — иначе эпизод закончится задним числом")
    func lastIncidentAtПереживает() throws {
        let началоПятьДнейНазад = Calendar.current.date(byAdding: .day, value: -5,
                                                        to: Date())!
        let инцидентВчера = Calendar.current.date(byAdding: .day, value: -1,
                                                  to: Date())!
        let container = try контейнер()
        let context = ModelContext(container)
        let episode = Episode(title: "Жидкий стул", detail: "третий день",
                              startedAt: началоПятьДнейНазад)
        episode.extend(to: инцидентВчера)
        context.insert(episode)

        let круг = try кругом(context: context)
        let вернулся = try #require(круг.episodes.first)
        #expect(тотЖеМомент(вернулся.lastIncidentAt, инцидентВчера),
                "последний инцидент не вернулся — тишина посчитается от начала эпизода")
        // И смысл, а не только поле: эпизод с инцидентом вчера обязан
        // остаться идущим. Это та же проверка с другой стороны —
        // если бы вернулось `startedAt`, он объявился бы законченным.
        #expect(!тотЖеМомент(вернулся.lastIncidentAt, началоПятьДнейНазад),
                "вернулось начало вместо последнего инцидента")
    }

    @Test("Имя и id ожидаемой схемы переживают круг")
    func awaitedNameПереживает() throws {
        let container = try контейнер()
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 8.1)
        context.insert(dog)
        let medication = Medication(name: "Левотироксин", doseText: "0,1 мг", times: [8 * 60])
        medication.dog = dog
        context.insert(medication)
        let dose = DoseRecord(scheduledAt: Date())
        let ожидаемая = UUID()
        dose.awaitedMedicationID = ожидаемая
        dose.awaitedMedicationName = "Левотироксин"
        dose.medication = medication
        context.insert(dose)

        let круг = try кругом(context: context)
        let снимок = try #require(круг.dogs.first?.medications.first?.doses.first)
        #expect(снимок.awaitedMedicationName == "Левотироксин",
                "имя ожидаемой схемы не вернулось — сшивать будет нечем")
        #expect(снимок.awaitedMedicationID == ожидаемая, """
            id ожидаемой схемы не пережил круг. С 05.11.2026 id схемы \
            едет в архив, и ссылка на неё — тоже.
            """)
    }

    /// Совпадают ли даты с точностью, которую НЕСЁТ ФОРМАТ.
    ///
    /// **Допуск здесь не поблажка, а свойство файла.** `.iso8601`
    /// пишет дату без долей секунды, то есть обрезает; первая редакция
    /// сравнивала `rounded()` обеих сторон и получила `1790960480`
    /// против `1790960481` — расхождение ровно на секунду, потому что
    /// исходная доля была ≥ 0,5 и округлилась ВВЕРХ, а формат обрезал
    /// ВНИЗ.
    ///
    /// > Тест зеленел бы по случайности доли секунды: при доле < 0,5
    /// > проходил, при ≥ 0,5 падал. Это хуже честного падения —
    /// > половину прогонов он молчал бы о том же самом.
    ///
    /// Требовать от архива точности, которой он не несёт, значит мерить
    /// не перенос, а кодировщик. Секунда — та единица, в которой формат
    /// обещает, и в ней же проверяем.
    private func тотЖеМомент(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return abs(a.timeIntervalSince(b)) < 1.5
    }

    /// Круг целиком: собрать архив, закодировать, раскодировать, восстановить.
    ///
    /// **Кодирование здесь не для красоты.** Поле, добавленное
    /// в структуру и не попавшее в `Codable`, пережило бы сборку
    /// в памяти и умерло бы в файле; а файл — это и есть то, что уезжает
    /// на новый телефон.
    private func кругом(context: ModelContext) throws -> BackupArchive {
        let archive = try BackupService.archive(context: context, appVersion: "тест")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let данные = try encoder.encode(archive)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupArchive.self, from: данные)
    }
}
