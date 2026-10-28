import Testing
import Foundation
import SwiftData
@testable import Togo

/// Правило дубля одно на все пути записи.
///
/// Замер 23.09.2026 по журналу с телефона: 112 записей, два дубля еды —
/// через 6 и 8 секунд после записи, оба пойманы. То есть защита работает
/// там, где стоит. А стояла она ровно в одном месте: `EventLog`, то есть
/// экраны. Голос, кнопка «Действие» и ярлыки шли мимо — и это тот путь,
/// где на экран не смотрят, значит второй раз нажмут вероятнее.
///
/// **Замер 07.10.2026 нашёл третий путь и пятый дубль.** `WalkRecorder`
/// не спрашивал о дубле вовсе — ни про `.outing`, которого не было
/// в наборе, ни про `.walk`, который в наборе с 23.09. Все пять
/// найденных дублей пришли этим путём, и сторож на вызов был зелёным:
/// он перечислял пути **руками**, и третьего в списке не было.
///
/// Два вывода, оба стоят дороже самой починки:
///
/// - **Окно 90 секунд для `.outing` заблокировало бы настоящую отметку.**
///   Дубли замера стоят на 1–3 секундах, настоящие повторы — от 36.
///   Поэтому у `.outing` своё окно, а не общее; прежний тест здесь
///   утверждал, что `.outing` не дубль никогда, и был прав в своей
///   половине.
/// - **Выгрузка дневника на этот вопрос не отвечает вовсе:** время в ней
///   минутное, а окно сторожа — секунды. Замер в единицах грубее порога
///   не подтверждает и не опровергает его ни в какую сторону. Секунды
///   взяты из `docs/журнал-устройства/usage-2026-10-07.jsonl`, и он
///   в UTC, а дневник в местном времени.
@Suite("Дубль ловится на всех путях записи")
@MainActor
struct DuplicateGuardTests {

    private func собакаИКонтекст() throws -> (ModelContext, Dog) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    private func еда(_ context: ModelContext, _ dog: Dog, at date: Date) throws -> LogEvent {
        let event = LogEvent(kind: .meal, date: date, authorName: "Я")
        event.grams = 65
        event.dog = dog
        context.insert(event)
        try context.save()
        return event
    }

    @Test("Вторая еда через шесть секунд — дубль")
    func второйТапЛовится() throws {
        let (context, dog) = try собакаИКонтекст()
        let первая = Date()
        _ = try еда(context, dog, at: первая)

        let вторая = LogEvent(kind: .meal, date: первая.addingTimeInterval(6), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вторая.date,
                                      like: вторая, in: context) != nil)
    }

    @Test("За окном — не дубль: собаку правда кормят дважды в день")
    func заОкномНеДубль() throws {
        let (context, dog) = try собакаИКонтекст()
        let утро = Date()
        _ = try еда(context, dog, at: утро)

        let вечер = LogEvent(kind: .meal,
                             date: утро.addingTimeInterval(DuplicateGuard.window + 1),
                             authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вечер.date,
                                      like: вечер, in: context) == nil)
    }

    private func выход(_ context: ModelContext, _ dog: Dog, at date: Date,
                       outcome: OutingOutcome?) throws -> LogEvent {
        let event = LogEvent(kind: .outing, date: date, authorName: "Я")
        event.outcome = outcome
        event.dog = dog
        context.insert(event)
        try context.save()
        return event
    }

    /// Прежняя редакция этого теста утверждала, что `.outing` дублем
    /// не считается вовсе, и была права **в своей половине**: собака
    /// правда писает несколько раз за прогулку. Неверным было следствие —
    /// из «повтор бывает настоящим» вышло «сторожа нет совсем».
    ///
    /// Замер 07.10.2026 по журналу действий (секунды; в выгрузке дневника
    /// время минутное, то есть грубее окна сторожа, и там вопрос
    /// неразрешим). Интервалы между отметками одной прогулки:
    ///
    /// ```
    /// дубли       3с · 2с · 1с · 2с · 1с            пять, в трёх прогулках
    /// настоящие   36с · 131с · 213с · 353с · 387с · 387с · 508с
    /// ```
    ///
    /// Между 3 и 36 секундами ничего нет — отсюда окно 10 секунд.
    @Test("Два тапа «пописал» в одну секунду — дубль")
    func дваТапаМочиЛовятся() throws {
        let (context, dog) = try собакаИКонтекст()
        let первый = Date()
        _ = try выход(context, dog, at: первый, outcome: .urine)

        let второй = LogEvent(kind: .outing, date: первый.addingTimeInterval(1), authorName: "Я")
        второй.outcome = .urine
        #expect(DuplicateGuard.recent(of: .outing, dog: dog, at: второй.date,
                                      like: второй, in: context) != nil,
                "собака не писает дважды в одну секунду — это второй тап")
    }

    @Test("Через полминуты — не дубль: собака правда писает несколько раз")
    func настоящийПовторНеЛовится() throws {
        let (context, dog) = try собакаИКонтекст()
        let первый = Date()
        _ = try выход(context, dog, at: первый, outcome: .urine)

        // 36 секунд — ближайший НАСТОЯЩИЙ повтор замера (15:44:49 → 15:45:25).
        // При общем окне 90 секунд он был бы заблокирован: ровно поэтому
        // `.outing` нельзя было просто дописать в набор.
        let второй = LogEvent(kind: .outing, date: первый.addingTimeInterval(36), authorName: "Я")
        второй.outcome = .urine
        #expect(DuplicateGuard.recent(of: .outing, dog: dog, at: второй.date,
                                      like: второй, in: context) == nil,
                "36 секунд — это второй раз, а не второй тап")
        #expect(DuplicateGuard.repeatableWindow < 36,
                "окно доросло до настоящего повтора: оно блокирует отметки")
    }

    @Test("«Попросился» и «пописал» — две записи об одном выходе, не дубль")
    func просьбаИРезультатРазныеЗаписи() throws {
        let (context, dog) = try собакаИКонтекст()
        let попросился = Date()
        // Экран нужды пишет выход без результата: `NeedsSheet.startOuting`
        // не заполняет ничего. Отметка прогулки приходит с `outcome`.
        _ = try выход(context, dog, at: попросился, outcome: nil)

        // 8 секунд — замер 10-05: 19:50:16 просьба, 19:50:24 отметка.
        // Внутри окна, и различитель здесь несущий.
        let пописал = LogEvent(kind: .outing, date: попросился.addingTimeInterval(8),
                               authorName: "Я")
        пописал.outcome = .urine
        #expect(DuplicateGuard.recent(of: .outing, dog: dog, at: пописал.date,
                                      like: пописал, in: context) == nil,
                "результат выхода заблокирован просьбой о нём")
    }

    @Test("Удалённая запись дублем не считается")
    func удалённаяНеСчитается() throws {
        let (context, dog) = try собакаИКонтекст()
        let первая = try еда(context, dog, at: Date())
        первая.deletedAt = Date()
        try context.save()

        let вторая = LogEvent(kind: .meal, date: первая.date.addingTimeInterval(3), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вторая.date,
                                      like: вторая, in: context) == nil,
                "человек удалил запись и записывает заново — это не второй тап")
    }

    // MARK: - Пачка отметок прогулки

    private func прогулка(_ отметки: [TimeInterval]) -> ActiveSession {
        var session = ActiveSession(kind: .walk,
                                    startedAt: Date().addingTimeInterval(-600),
                                    startedBy: "Я")
        session.marks = отметки.map {
            .init(kind: .urine, at: session.startedAt.addingTimeInterval($0))
        }
        return session
    }

    private func выходы(_ dog: Dog, прогулки walkID: UUID) -> [LogEvent] {
        dog.events.filter { $0.walkEventID == walkID && $0.kind == .outing && $0.deletedAt == nil }
    }

    /// Все пять дублей замера 07.10.2026 пришли **этим** путём и лежали
    /// внутри одной пачки: `WalkRecorder.record` вставляет отметки
    /// до `save`, и через хранилище их не видно.
    @Test("Три тапа «пописал» за три секунды дают одну запись")
    func пачкаПросеиваетДубли() throws {
        let (context, dog) = try собакаИКонтекст()
        let session = прогулка([0, 2, 3])   // 19:50:24 · :26 · :27

        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Я", context: context))
        #expect(выходы(dog, прогулки: walk.id).count == 1,
                "три тапа по одной кнопке стали тремя записями")
        #expect(walk.note == "пописал",
                "сводка считает тапы, а не записи: подпись обещает больше, чем в ленте")
    }

    @Test("Настоящие повторы пачка не теряет")
    func пачкаНеТеряетНастоящие() throws {
        let (context, dog) = try собакаИКонтекст()
        let session = прогулка([0, 36, 167])   // интервалы замера: 36 и 131 с

        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Я", context: context))
        #expect(выходы(dog, прогулки: walk.id).count == 3,
                "сторож съел настоящие отметки — так пропадает прогулка целиком")
        #expect(walk.note == "пописал ×3")
    }

    // MARK: - Сторож на вызов

    /// Список путей выводится из дерева, а не перечисляется руками.
    ///
    /// Прежняя редакция называла два файла — `EventLog` и
    /// `QuickLogIntents`, — и была зелёной всё время, пока третий путь,
    /// `WalkRecorder`, не спрашивал о дубле вовсе. Список руками знает
    /// только то, что в него положили, и `WalkRecorder` в него не положил
    /// никто: правило лежало в цели приложения, а он — в общем слое,
    /// и дороги к нему не было **по устройству проекта**.
    private static let безСторожа: [String: String] = [
        "SeedData.swift": "демо-данные: дубли в них нарочные, их показывают",
        "CloudKitSchemaWarmup.swift": "запись-маркер прогрева, только DEBUG; человек её не пишет",
        "SharedDiaryPayloads.swift": "приехало с другого телефона уже записанным: отклонить значило бы потерять чужую запись",
        "Backup.swift": "восстановление архива: сторож дубля съел бы историю",
        "RecallWriter.swift": "запись по памяти задним числом — второй тап там невозможен",
        "ScheduleChange.swift": "не тап, а СЛЕД применённой правки: текст записи содержит «было → стало», и две подряд не совпадают по смыслу — вторая описывает другой переход. Повтор одного и того же перехода означал бы, что схему вернули обратно, и это событие, которое надо видеть, а не прятать",
    ]

    private func исходники() -> [(String, String)] {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var найдено: [(String, String)] = []
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            let обход = FileManager.default.enumerator(
                at: корень.appendingPathComponent(каталог), includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "swift",
                      let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }
                найдено.append((элемент.lastPathComponent, текст))
            }
        }
        return найдено
    }

    /// Заводит ли файл запись дневника — по коду, а не по рассказу о коде.
    /// Тест, читающий комментарий как код, краснеет без дефекта.
    private func заводитЗапись(_ текст: String) -> Bool {
        текст.components(separatedBy: .newlines)
            .contains { $0.components(separatedBy: "//")[0].contains("LogEvent(kind:") }
    }

    @Test("Каждый путь записи зовёт сторожа дубля")
    func всеПутиСпрашиваютСторожа() {
        let файлы = исходники()
        #expect(файлы.count > 50, "файлов прочитано \(файлы.count) — разбор не состоялся")

        let пути = файлы.filter { заводитЗапись($0.1) }
        #expect(пути.count >= 8, """
            путей записи найдено \(пути.count), ожидалось не меньше восьми.
            Переставший находить сторож молчит так же, как тот,
            кому нечего сказать.
            """)

        var молчат: [String] = []
        for (имя, текст) in пути where Self.безСторожа[имя] == nil {
            if !текст.contains("DuplicateGuard.recent(") { молчат.append(имя) }
        }
        #expect(молчат.isEmpty, """
            пишут в дневник, не спросив о дубле: \(молчат.sorted()).

            Либо позови `DuplicateGuard.recent(…)`, либо впиши файл
            в `безСторожа` с причиной — почему второй тап там невозможен
            или безвреден. Правило одно на все пути: `WalkRecorder`
            молчал пять дублей, потому что его забыли в списке.
            """)
    }

    @Test("Сторожа зовут не меньше трёх путей")
    func сторожаЗовутТриПути() {
        let зовут = исходники()
            .filter { $0.1.contains("DuplicateGuard.recent(") }
            .map(\.0)
            .sorted()
        #expect(зовут.count >= 3, """
            сторожа зовут \(зовут): \(зовут.count) путей.
            Экран, голос и прогулка — три. Стало меньше — путь
            обошли, и предыдущая проверка этого не увидит:
            она спрашивает про найденные файлы, а не про их число.
            """)
    }

    @Test("Путь записи не молчит в журнале действий")
    func путиНеМолчат() {
        for (имя, текст) in исходники() where текст.contains("DuplicateGuard.recent(") {
            #expect(текст.contains("UsageLog.note(.record"), """
                \(имя) пишет в дневник молча: в замере этот путь
                не отличить от неиспользуемого.
                """)
        }
    }

    /// Имя теста уникально нарочно: `SingleDoorTests` несёт тест
    /// с тем же смыслом про СВОИ исключения, а эталон прогона
    /// (`Tools/эталон-прогона.json`) сверяет красное **по именам**.
    /// Два одинаковых имени в разных наборах он не различит, и запись
    /// «ожидаемо красный» накрыла бы оба.
    @Test("У каждого исключения сторожа дубля есть причина и оно существует")
    func исключенияЧестные() {
        let пути = Dictionary(uniqueKeysWithValues:
            исходники().filter { заводитЗапись($0.1) }.map { ($0.0, $0.1) })
        for (файл, причина) in Self.безСторожа {
            #expect(!причина.isEmpty, "\(файл): исключение без причины")
            #expect(пути[файл] != nil, """
                \(файл) в исключениях, а записи дневника не заводит —
                список протух. Исключение, закрывающее то, чего нет,
                это лишняя дыра, про которую никто не помнит.
                """)
        }
    }
}
