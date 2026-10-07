import Testing
import Foundation
import SwiftData
@testable import Togo

/// Уборка безымянных записей о собаке.
///
/// **Порядок тестов здесь — часть смысла.** Сначала то, что обязано
/// ПЕРЕЖИТЬ уборку, и только потом то, что обязано исчезнуть:
/// утверждение «безымянные удаляются» выполняется и тогда, когда
/// удалено всё, и у нас это оплачено порогом 0 на Kvit. Цена ошибки
/// здесь — не лишняя строка в списке, а дневник человека: у `Dog`
/// одиннадцать связей, и у всех `deleteRule: .cascade`.
@Suite("Уборка безымянных собак")
@MainActor
struct NamelessDogCleanupTests {

    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    /// Уборка смотрит в `UserDefaults`, а он на прогоне общий.
    /// Без этого тесты зависели бы от порядка запуска — и «пережила
    /// запуск» могло бы оказаться правдой просто потому, что сосед
    /// очистил память.
    private func забытьВсё() {
        UserDefaults.standard.removeObject(forKey: "dogs.seenNameless")
        UserDefaults.standard.removeObject(forKey: "dogs.removedByCleanup")
    }

    // MARK: 1. Что обязано пережить уборку

    @Test("Собака с кличкой переживает запуск")
    func сКличкойПереживает() throws {
        забытьВсё()
        let context = контекст()
        let стич = Dog(name: "Стич", weightKg: 4.7)
        context.insert(стич)
        try context.save()

        // Два запуска: условие «видена пустой дважды» не должно
        // срабатывать по собаке, которая вообще не пустая.
        NamelessDogCleanup.убрать(in: context)
        NamelessDogCleanup.убрать(in: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, "уборка удалила собаку с кличкой")
        #expect(собаки.first?.name == "Стич")
    }

    /// **Главный тест файла.** Безымянной бывает НАСТОЯЩАЯ собака,
    /// которой кличку затёрло слиянием, — этот дефект измерен
    /// и починен 07.10, но записи, им испорченные, у людей остались.
    /// Удалить такую значит удалить дневник.
    @Test("Безымянная с единственным событием переживает запуск")
    func безымяннаяСИсториейПереживает() throws {
        забытьВсё()
        let context = контекст()
        let затёртая = Dog(name: "", weightKg: 4.7)
        context.insert(затёртая)
        let отметка = LogEvent(kind: .meal, authorName: "Виктория")
        отметка.grams = 60
        отметка.dog = затёртая
        context.insert(отметка)
        try context.save()

        NamelessDogCleanup.убрать(in: context)
        NamelessDogCleanup.убрать(in: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, """
            безымянная собака с историей удалена. У `Dog` одиннадцать
            связей с `deleteRule: .cascade` — вместе с ней ушёл весь
            дневник. А безымянной она могла стать не от рождения,
            а от приехавшего пустого снимка: этот дефект измерен
            07.10.2026.
            """)
        #expect(собаки.first?.events.count == 1, "отметка потеряна")
    }

    @Test("На первом запуске не удаляется ничего — даже пустое")
    func первыйЗапускНеУдаляет() throws {
        забытьВсё()
        let context = контекст()
        context.insert(Dog(name: "", weightKg: 0))
        try context.save()

        let убрано = NamelessDogCleanup.убрать(in: context)

        #expect(убрано == 0, """
            уборка сработала на первом же запуске. Условие «видена
            пустой и на прошлом запуске» — про гонку с зеркалом
            CloudKit: оно правит свои же строки, и запись, пустая
            в момент запуска, через секунду может стать Стичем.
            """)
        #expect(try context.fetch(FetchDescriptor<Dog>()).count == 1)
    }

    // MARK: 2. Что обязано исчезнуть

    @Test("Пустая запись без истории убирается со второго запуска")
    func пустаяБезИсторииУбирается() throws {
        забытьВсё()
        let context = контекст()
        context.insert(Dog(name: "", weightKg: 0))
        let стич = Dog(name: "Стич", weightKg: 4.7)
        context.insert(стич)
        try context.save()

        #expect(NamelessDogCleanup.убрать(in: context) == 0)
        let убрано = NamelessDogCleanup.убрать(in: context)

        #expect(убрано == 1, "пустая запись осталась после двух запусков")
        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)
        #expect(собаки.first?.name == "Стич", "убрали не ту")
    }

    @Test("Пробел и неразрывный пробел — тоже пустая кличка")
    func пробелыЭтоПустота() throws {
        забытьВсё()
        let context = контекст()
        for кличка in [" ", "\u{00A0}", "\n"] {
            context.insert(Dog(name: кличка, weightKg: 0))
        }
        try context.save()

        #expect(NamelessDogCleanup.убрать(in: context) == 0)
        #expect(NamelessDogCleanup.убрать(in: context) == 3, """
            кличка из одних пробелов принята за кличку. Неразрывный
            пробел U+00A0 приезжает опечаткой с французской клавиатуры
            и рисуется ровно так же пусто, как "".
            """)
    }

    @Test("Убранное названо своим словом, а не «исчезла»")
    func убранноеНазваноСвоимСловом() throws {
        забытьВсё()
        let context = контекст()
        let пустая = Dog(name: "", weightKg: 0)
        context.insert(пустая)
        try context.save()

        #expect(NamelessDogCleanup.убрать(in: context) == 0)
        #expect(NamelessDogCleanup.убрать(in: context) == 1)

        #expect(NamelessDogCleanup.убраныНами.contains(пустая.id), """
            убранное не попало в список убранных нами — значит
            `DogOrigin` назовёт нашу уборку «исчезла», тем же словом,
            которым говорит о пропажах, причину которых мы ищем.
            «Исчезла сама» — единственная улика по зеркалу CloudKit.
            """)
    }

    // MARK: 3. Границы и сторож на будущее

    /// Условие «ничего не тянет» смотрит одиннадцать СВЯЗЕЙ. Если
    /// у какой-нибудь модели появится хранимое поле `dogID`, появится
    /// второй способ ссылаться на собаку, и условие станет неполным
    /// молча: уборка удалит собаку, а запись останется указывать
    /// в пустоту.
    ///
    /// **Проверку «ни одна запись не ссылается полем `dogID`» в сам
    /// код я не ставил, и это замер, а не лень:** `dogID` существует
    /// только в снимках обмена (`SharedDiary.swift`), ни у одной
    /// `@Model` такого хранимого поля нет. Проверка была бы истинной
    /// всегда — исключением, закрывающим то, чего нет.
    ///
    /// Поэтому сторож стоит здесь: он падает в тот день, когда поле
    /// появится, и тогда условие надо будет дописывать.
    @Test("Ни одна модель не ссылается на собаку полем dogID")
    func второгоСпособаСсылкиНет() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TogoShared/Models")

        var найдено: [String] = []
        var файлов = 0
        let обход = FileManager.default.enumerator(at: корень, includingPropertiesForKeys: nil)
        while let элемент = обход?.nextObject() as? URL {
            guard элемент.pathExtension == "swift",
                  let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }
            файлов += 1
            for строка in текст.components(separatedBy: .newlines) {
                let код = строка.components(separatedBy: "//")[0]
                if код.contains("var dogID") { найдено.append(элемент.lastPathComponent) }
            }
        }

        // Сканер, переставший что-либо находить, молчит так же, как
        // тот, кому нечего сказать.
        #expect(файлов >= 10, "прочитано файлов моделей: \(файлов) — разбор не состоялся")
        #expect(найдено.isEmpty, """
            появилось хранимое поле `dogID`: \(найдено). Это второй
            способ ссылаться на собаку, и `NamelessDogCleanup`
            о нём не знает: условие «ничего за собой не тянет»
            смотрит одиннадцать связей и станет неполным молча.
            Допиши условие выборкой по этому полю.
            """)
    }
}
