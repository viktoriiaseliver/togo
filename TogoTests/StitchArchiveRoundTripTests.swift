import Testing
import Foundation
import SwiftData
@testable import Togo

/// Круговая приёмка архива медкнижки Стича: файл → загрузка → счёт на месте.
///
/// **Зачем отдельно от паритета.** `ArchiveParityTests` отвечает на вопрос
/// «что обязано уехать», этот — на вопрос «что доехало». Между ними живёт
/// ровно та потеря, которую обнаруживают через месяц: формат верен,
/// `decode` принимает, а записей в приложении меньше, чем в файле.
///
/// **Почему не через интерфейс.** Переносом записей занимается `restore`,
/// и теряет записи он, а не файл-пикер. Интерфейсная половина
/// (`BackupFile: Transferable`, выбор файла, лист «Заменить/Добавить»)
/// проверяется в TestFlight руками и этим набором НЕ закрыта. Две
/// половины, не одна, и называть их надо раздельно.
///
/// **Имена латиницей намеренно.** Замер 07.10.2026: `-only-testing`
/// не выбирает набор с кириллическим именем метода и печатает
/// `TEST SUCCEEDED` при нуле выполненных — то есть молчаливый зелёный.
/// Фильтровать по имени можно только латиницей.
///
/// **Входных файлов у этого набора нет, и это намеренно.** Архив строится
/// здесь же, в коде. Тест, которому нужен файл из папки вне git, не
/// воспроизведётся ни на другой машине, ни в CI, ни после уборки хранилища —
/// а зелёным он при этом останется, если путь просто не найдётся и проверка
/// свернётся. Числа ниже сняты со сборщика `Tools/собрать-архив-стича.py`
/// 07.10.2026; разойдутся — красным станет этот набор, а не тишина.
@Suite("StitchArchiveRoundTrip")
struct StitchArchiveRoundTripTests {

    /// Что обязано доехать. Числа сняты со сборщика 07.10.2026,
    /// а не из головы: 22 веса, 63 эпизода, 1 лекарство, 1 задача ухода.
    private static let expected = (dogs: 1, members: 1, weights: 22,
                                   episodes: 63, medications: 1, careTasks: 1)

    /// Минимальный архив, собранный здесь же, а не прочитанный с диска.
    ///
    /// **Тест, которому нужен файл из чужой папки, не может покраснеть
    /// у того, у кого этой папки нет** — он скажет «пропущен» и будет
    /// выглядеть зелёным. Поэтому содержимое строится в коде, а файл
    /// на диске проверяется отдельным тестом, который честно пропускается.
    private static func archive() -> BackupArchive {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let weights = (0..<expected.weights).map { i in
            BackupArchive.WeightSnapshot(date: start.addingTimeInterval(Double(i) * 86_400),
                                         kg: 3.5 + Double(i) * 0.03)
        }
        let episodes = (0..<expected.episodes).map { i in
            BackupArchive.EpisodeSnapshot(
                startedAt: start.addingTimeInterval(Double(i) * 3_600),
                title: i == 0 ? "НЕПОЛНЫЙ АРХИВ — приложение не сносить" : "Запись \(i)",
                detail: "подробность \(i)")
        }
        var dog = BackupArchive.DogSnapshot(
            name: "Stitch", weightKg: 4.20, foodBrand: "", portionGrams: 0,
            mealsPerDay: 2, mealTimes: [], forbiddenFoods: [], rewards: [],
            trainingFoodFromPortion: false, markerKindRaw: "clicker",
            sessionLengthMinutes: 5, isOnTreatment: true, createdAt: start,
            events: [], weights: weights, careTasks: [], medications: [],
            trainingSteps: [], trainingSessions: [], trips: [])
        dog.careTasks = [.init(title: "Контроль Т4 и ТТГ",
                               detail: "13.10.2026, 13:30, Vet Riviera",
                               intervalDays: 42, categoryRaw: "vet", snoozeCount: 0)]
        dog.medications = [.init(name: "Euthyrox 75 мкг", doseText: "1 таблетка",
                                 times: [570, 1290], fastingMinutes: 0,
                                 isPaused: false, doses: [])]
        return BackupArchive(
            createdAt: Date(), appVersion: "НЕПОЛНЫЙ архив из медкнижки",
            dogs: [dog],
            members: [.init(name: "Виктория", roleRaw: "owner", isMe: true, isOnDuty: true)],
            episodes: episodes)
    }

    @Test("every record in the file reaches the store")
    func roundTripKeepsEveryRecord() throws {
        let data = try BackupService.encode(Self.archive())
        let decoded = try BackupService.decode(data)
        let context = ModelContext(Persistence.container())

        _ = try BackupService.restore(decoded, into: context, strategy: .replace)

        let dogs = try context.fetch(FetchDescriptor<Dog>())
        #expect(dogs.count == Self.expected.dogs)
        #expect(try context.fetch(FetchDescriptor<FamilyMember>()).count == Self.expected.members)
        #expect(try context.fetch(FetchDescriptor<Episode>()).count == Self.expected.episodes)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).count == Self.expected.weights)
        #expect(try context.fetch(FetchDescriptor<Medication>()).count == Self.expected.medications)
        #expect(try context.fetch(FetchDescriptor<CareTask>()).count == Self.expected.careTasks)

        // Предупреждение обязано доехать до экрана, а не остаться в поле
        // формата: тот, кто собрался сносить приложение, файл редактором
        // не откроет. Значит его видимость — предмет проверки.
        let titles = try context.fetch(FetchDescriptor<Episode>()).map(\.title)
        #expect(titles.contains { $0.contains("НЕПОЛНЫЙ АРХИВ") })
    }

    /// От обратного, иначе предыдущий тест пройдёт и при пустом результате.
    ///
    /// **Порченый файл обязан дать ОТКАЗ, а не ноль записей.** Отрицательное
    /// утверждение выполняется и при отсутствии предмета: «потерь нет»
    /// истинно и тогда, когда ничего не загрузилось вовсе.
    @Test("a corrupted file must throw, not restore nothing")
    func corruptedFileThrowsInsteadOfRestoringNothing() throws {
        let garbage = Data("{\"formatVersion\":1,\"dogs\":".utf8)
        #expect(throws: BackupError.self) {
            _ = try BackupService.decode(garbage)
        }

        // И отдельно: файл из будущего формата тоже отказ, а не тишина.
        var future = Self.archive()
        future.formatVersion = BackupService.currentFormatVersion + 1
        let futureData = try BackupService.encode(future)
        #expect(throws: BackupError.self) {
            _ = try BackupService.decode(futureData)
        }
    }

    /// Сторож на сам сторож: если архив вдруг окажется пустым,
    /// первый тест обязан покраснеть, а не обрадоваться нулям.
    @Test("the fixture itself is not empty")
    func fixtureHasSomethingToLose() {
        let a = Self.archive()
        #expect(a.dogs.first?.weights.count == Self.expected.weights)
        #expect(a.episodes.count == Self.expected.episodes)
        #expect(Self.expected.weights > 0 && Self.expected.episodes > 0)
    }
}
