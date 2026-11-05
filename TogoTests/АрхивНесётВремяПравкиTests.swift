import Testing
import Foundation
import SwiftData
@testable import Togo

/// Архив везёт время правки — и спор у второго человека решает оно,
/// а не момент восстановления.
///
/// # Что оплатило этот набор
///
/// Решение Виктории 05.11.2026: «Возить время правки в архиве». До него
/// восстановленная запись получала `changedAt = now` — сперва
/// от `init`, потом от `FamilySync.enqueueLocalChanges`, который
/// перештамповывает всё сохранённое. У второго человека она поэтому
/// побеждала в `SharedDiaryMerge` всё:
///
/// ```
/// он правил после снятия файла   его правка проигрывала файлу
/// он удалял после снятия файла   надгробие проигрывало — запись оживала
/// ```
///
/// # Чем мерится
///
/// Обмена (CloudKit) в тестах нет. Мерится то, на чём он стоит:
/// время правки восстановленной записи, ответ `SharedDiaryMerge.resolve`
/// на паре нагрузок «у второго человека» / «приехало от нас»,
/// и решение `FamilySync.штамповать` на НАСТОЯЩЕМ уведомлении `didSave`
/// сохранения восстановления. У каждого — отрицательный контроль: та же
/// пара со временем «сейчас» обязана дать обратный ответ, иначе зелёный
/// был бы про разрешитель, а не про архив.
@Suite("Архив везёт время правки: спор решает оно")
@MainActor
struct АрхивНесётВремяПравкиTests {

    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    /// Время снятия файла и время правки второго человека — числами:
    /// спор решается сравнением, и плавающий `Date()` сделал бы тест
    /// про то, когда его запустили.
    private static let правкаДоФайла = Date(timeIntervalSince1970: 1_790_000_000)
    private static let правкаВторого = правкаДоФайла.addingTimeInterval(3600)

    /// Дневник с собакой, взвешиванием и отметкой, правленными ДО файла.
    private func источник() throws -> (ModelContext, Data, WeightEntry, LogEvent) {
        let к = контекст()
        let стич = Dog(name: "Стич", weightKg: 4.1)
        к.insert(стич)
        let вес = WeightEntry(date: Self.правкаДоФайла, kg: 4.1)
        вес.dog = стич
        к.insert(вес)
        let запись = LogEvent(kind: .meal, date: Self.правкаДоФайла, authorName: "Виктория")
        запись.dog = стич
        к.insert(запись)
        стич.changedAt = Self.правкаДоФайла
        вес.changedAt = Self.правкаДоФайла
        запись.changedAt = Self.правкаДоФайла
        try к.save()
        let данные = try BackupService.encode(try BackupService.archive(context: к, appVersion: "тест"))
        return (к, данные, вес, запись)
    }

    private func тотЖеМомент(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1.5 }

    @Test("Восстановленная запись несёт время правки из файла, а не «сейчас»")
    func времяИзФайла() throws {
        let (_, данные, вес, запись) = try источник()
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый,
                                  strategy: .replace, обмен: true)

        let приехавшийВес = try #require(try новый.fetch(FetchDescriptor<WeightEntry>()).first)
        let приехавшаяЗапись = try #require(try новый.fetch(FetchDescriptor<LogEvent>()).first)
        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        #expect(приехавшийВес.id == вес.id && приехавшаяЗапись.id == запись.id,
                "приехали другие записи — проверять время не на чем")
        #expect(тотЖеМомент(приехавшийВес.changedAt, Self.правкаДоФайла),
                "время правки веса \(приехавшийВес.changedAt) вместо времени из файла")
        #expect(тотЖеМомент(приехавшаяЗапись.changedAt, Self.правкаДоФайла),
                "время правки отметки \(приехавшаяЗапись.changedAt) вместо времени из файла")
        #expect(тотЖеМомент(собака.changedAt, Self.правкаДоФайла),
                "время правки собаки \(собака.changedAt) вместо времени из файла")
    }

    /// Главный: второй человек поправил вес ПОСЛЕ снятия файла.
    @Test("«Заменить» при обмене не перебивает более позднюю правку второго человека")
    func поздняяПравкаВторогоПобеждает() throws {
        let (_, данные, вес, _) = try источник()
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый,
                                  strategy: .replace, обмен: true)
        let приехало = try #require(try новый.fetch(FetchDescriptor<WeightEntry>()).first).payload

        var уВторого = вес.payload
        уВторого.kg = 4.4
        уВторого.changedAt = Self.правкаВторого

        let исход = SharedDiaryMerge.resolve(local: уВторого, remote: приехало)
        #expect(исход.kg == 4.4, """
            у второго человека победил файл (\(исход.kg) кг): его правка, \
            сделанная ПОСЛЕ снятия файла, откатилась восстановлением.
            """)

        // Контроль: та же пара, но у приехавшего время «сейчас» — так было
        // до решения. Разрешитель обязан отдать победу файлу, иначе
        // зелёный выше не про время из архива.
        var какПрежде = приехало
        какПрежде.changedAt = Date()
        #expect(SharedDiaryMerge.resolve(local: уВторого, remote: какПрежде).kg == 4.1,
                "контроль не покраснел: со временем «сейчас» файл обязан побеждать")
    }

    @Test("Удалённое вторым человеком после снятия файла не оживает")
    func удалённоеНеОживает() throws {
        let (_, данные, _, запись) = try источник()
        let новый = контекст()
        try BackupService.restore(try BackupService.decode(данные), into: новый,
                                  strategy: .replace, обмен: true)
        let приехало = try #require(try новый.fetch(FetchDescriptor<LogEvent>()).first).payload

        var уВторого = запись.payload
        уВторого.deletedAt = Self.правкаВторого
        уВторого.deletedBy = "Мама"
        уВторого.changedAt = Self.правкаВторого

        let исход = SharedDiaryMerge.resolve(local: уВторого, remote: приехало)
        #expect(исход.deletedAt != nil, """
            удалённая вторым человеком запись ОЖИЛА: надгробие проиграло \
            восстановленной версии.
            """)

        var какПрежде = приехало
        какПрежде.changedAt = Date()
        #expect(SharedDiaryMerge.resolve(local: уВторого, remote: какПрежде).deletedAt == nil,
                "контроль не покраснел: со временем «сейчас» запись обязана оживать")
    }

    /// Решение обмена — на настоящем уведомлении сохранения.
    ///
    /// `FamilySync.localSaveHappened` читает `штамповать(_:)` синхронно,
    /// в обработчике; здесь тот же вызов в том же месте — в наблюдателе
    /// `ModelContext.didSave`. Сам `enqueueLocalChanges` без движка
    /// CloudKit не зовётся (`guard !engines.isEmpty`).
    @Test("Сохранение восстановления обмен не штампует, обычное — штампует")
    func восстановлениеНеШтампуется() throws {
        let (_, данные, _, _) = try источник()
        let новый = контекст()

        final class Ответы: @unchecked Sendable { var штамповать: [Bool] = [] }
        let ответы = Ответы()
        let ключ = ObjectIdentifier(новый)
        let наблюдатель = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { уведомление in
            MainActor.assumeIsolated {
                guard let чей = уведомление.object as? ModelContext,
                      ObjectIdentifier(чей) == ключ else { return }
                ответы.штамповать.append(FamilySync.штамповать(уведомление))
            }
        }
        defer { NotificationCenter.default.removeObserver(наблюдатель) }

        try BackupService.restore(try BackupService.decode(данные), into: новый,
                                  strategy: .replace, обмен: true)
        let послеВосстановления = ответы.штамповать
        #expect(послеВосстановления == [false], """
            сохранение восстановления обмен решил штамповать \
            (\(послеВосстановления)): время из файла было бы затёрто «сейчас» \
            до отправки. Пустой список — уведомление не дошло до наблюдателя \
            или пришло не от этого контекста.
            """)

        // Контроль: обычная правка в том же контексте штампуется.
        let собака = try #require(try новый.fetch(FetchDescriptor<Dog>()).first)
        собака.name = "Стич второй"
        try новый.save()
        #expect(ответы.штамповать == [false, true], """
            обычное сохранение после восстановления не штампуется \
            (\(ответы.штамповать)) — пометка восстановления не снялась.
            """)
    }

    /// Ответ на вопрос «уезжает ли второму человеку то, чего нет в файле».
    ///
    /// Жёстко стёртая запись не приходит в `didSave` ни ключом `inserted`,
    /// ни `updated` — отправить по ней нечего (голова `ОбщееУдаление`).
    /// Поэтому при обмене «заменить» ставит надгробие.
    @Test("«Заменить» при обмене ставит надгробие тому, чего нет в файле")
    func чегоНетВФайлеПолучаетНадгробие() throws {
        let (к, данные, _, запись) = try источник()
        let собака = try #require(try к.fetch(FetchDescriptor<Dog>()).first)
        let собакаID = собака.id
        let позже = LogEvent(kind: .outing, date: Date(), authorName: "Мама")
        позже.dog = собака
        к.insert(позже)
        let весПозже = WeightEntry(date: Date(), kg: 4.3)
        весПозже.dog = собака
        к.insert(весПозже)
        try к.save()
        let позжеID = позже.id
        let весПозжеID = весПозже.id

        try BackupService.restore(try BackupService.decode(данные), into: к,
                                  strategy: .replace, обмен: true)

        let записи = try к.fetch(FetchDescriptor<LogEvent>())
        let надгробная = try #require(записи.first { $0.id == позжеID }, """
            запись, которой нет в файле, стёрта жёстко — второму человеку \
            по ней не уедет ничего, у него она останется.
            """)
        #expect(надгробная.deletedAt != nil, "запись вне файла осталась живой")
        #expect(Date().timeIntervalSince(надгробная.changedAt) < 60,
                "надгробие без свежего времени правки проиграет спор")
        #expect(надгробная.dog?.id == собакаID, """
            надгробие отвязано от собаки: собака из файла легла заново, \
            а перепривязка не сработала.
            """)
        #expect(записи.filter { $0.id == запись.id }.count == 1, "запись из файла легла не одна")
        #expect(записи.first { $0.id == запись.id }?.deletedAt == nil, "запись из файла легла удалённой")

        let весНадгробный = try #require(
            try к.fetch(FetchDescriptor<WeightEntry>()).first { $0.id == весПозжеID },
            "взвешивание вне файла стёрто жёстко")
        #expect(весНадгробный.deletedAt != nil)
        #expect(try к.fetch(FetchDescriptor<Dog>()).count == 1, "собак не одна")

        // Контроль: без обмена «заменить» стирает, как прежде.
        let (другой, данныеДругого, _, _) = try источник()
        let собакаДругого = try #require(try другой.fetch(FetchDescriptor<Dog>()).first)
        let лишняя = LogEvent(kind: .outing, date: Date(), authorName: "Мама")
        лишняя.dog = собакаДругого
        другой.insert(лишняя)
        try другой.save()
        let лишняяID = лишняя.id
        try BackupService.restore(try BackupService.decode(данныеДругого), into: другой,
                                  strategy: .replace, обмен: false)
        #expect(try другой.fetch(FetchDescriptor<LogEvent>()).contains { $0.id == лишняяID } == false,
                "без обмена «заменить» обязано стирать — контроль не различает пути")
    }

    @Test("Долитый профиль — правка сейчас, а не время из файла")
    func доливкаПрофиляШтампует() throws {
        let (_, данные, _, _) = try источник()
        let телефон = контекст()
        // Тот же дневник, но без клички породы: долив её заполнит.
        try BackupService.restore(try BackupService.decode(данные), into: телефон,
                                  strategy: .replace, обмен: true)
        let собака = try #require(try телефон.fetch(FetchDescriptor<Dog>()).first)
        собака.breed = nil
        собака.changedAt = Self.правкаДоФайла
        try телефон.save()

        var архив = try BackupService.decode(данные)
        архив.dogs[0].breed = "Шипперке"
        try BackupService.restore(архив, into: телефон, strategy: .merge, обмен: true)

        #expect(собака.breed == "Шипперке", "порода не долилась — проверять штамп не на чем")
        #expect(Date().timeIntervalSince(собака.changedAt) < 60, """
            долитый профиль сохранил старое время правки — заполненное \
            пустое проиграет спор у второго человека и не уедет.
            """)
    }
}
