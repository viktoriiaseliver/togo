import Testing
import Foundation
import SwiftData
@testable import Togo

/// Молчаливые сбои: места, где сохранение могло не пройти,
/// а человеку всё равно показывали успех.
///
/// **Чем здесь ломается запись.** Подделки не заводили: SwiftData даёт
/// настоящий отказ. Хранилище сначала создаётся обычным файловым, потом
/// то же самое открывается ещё раз с `allowsSave: false`. На таком
/// контексте `insert` проходит, а `save()` бросает
/// `NSCocoaErrorDomain 513` — «нет разрешения на запись». Это тот же
/// путь отказа, что и на телефоне при полном диске или недоступном
/// контейнере, и он не требует ни одной строки кода в приложении.
///
/// (`isStoredInMemoryOnly: true` с `allowsSave: false` не годится:
/// такой контейнер вообще не открывается — хранилище лежит в `/dev/null`.)
///
/// **Почему возврат руками, а не `context.rollback()`.** Ревью просило
/// откат, но на iOS 26 он не делает того, что от него ждут: снимает
/// признак изменений и не возвращает ни правленое поле, ни вставленный
/// объект. Измеряно здесь же, пробой: после `rollback()` `givenAt`
/// оставался снятым, а вставленная доза — в связи, при `hasChanges ==
/// false`. То есть штатный откат сам производит расхождение экрана
/// с хранилищем, о котором никто не узнаёт, — ровно то, от чего уходим.
/// Поэтому и `DoseScheduler`, и `EventLog` возвращают ровно те поля,
/// что трогали. В самом файле хранилища при этом остаётся прежнее:
/// неудавшееся сохранение до него не доходит.
enum НеЗаписывающееХранилище {

    /// Контекст, у которого `save()` всегда бросает.
    ///
    /// - Parameter наполнить: что положить в хранилище, пока оно ещё
    ///   пишет. Нужно там, где ломается снятие уже существующей отметки.
    @MainActor
    static func контекст(
        наполнить: @MainActor (ModelContext) throws -> Void = { _ in }
    ) throws -> ModelContext {
        let каталог = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
        let файл = каталог.appending(path: "заперто.store")

        // Сначала заводим хранилище как обычно — иначе открывать нечего.
        do {
            let пишущий = try ModelContainer(for: Persistence.schema,
                                             configurations: ModelConfiguration(url: файл,
                                                               cloudKitDatabase: .none))
            let ctx = ModelContext(пишущий)
            try наполнить(ctx)
            try ctx.save()
        }

        let запертый = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(url: файл, allowsSave: false,
                                               cloudKitDatabase: .none)
        )
        return ModelContext(запертый)
    }

    /// Обычный контекст в памяти — для проверок «а когда всё хорошо».
    @MainActor
    static func рабочийКонтекст() throws -> ModelContext {
        let контейнер = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        )
        return ModelContext(контейнер)
    }

    /// Собака со схемой лечения на заданный час.
    @MainActor
    static func собакаСоСхемой(in context: ModelContext,
                               время: Date) -> (Dog, Medication) {
        let dog = Dog(name: "Стич", weightKg: 12)
        dog.isOnTreatment = true
        context.insert(dog)

        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: время) * 60
            + calendar.component(.minute, from: время)
        let medication = Medication(name: "Эутирокс", doseText: "1 таб",
                                    times: [minute], fastingMinutes: 60)
        medication.dog = dog
        medication.stockTotal = 30
        medication.stockLeft = 30
        context.insert(medication)
        return (dog, medication)
    }
}

@Suite("Молчаливые сбои · двойная доза")
@MainActor
struct DoseSilentFailureTests {

    /// Сама проверка того, чем мы ломаем запись. Без неё все остальные
    /// тесты этого набора могли бы зеленеть впустую: если `save()`
    /// перестанет бросать, они проверяли бы удачный путь и молчали.
    @Test("Запертое хранилище действительно роняет save")
    func запертоеХранилищеБросает() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        context.insert(Dog(name: "Тео", weightKg: 8))
        #expect(throws: (any Error).self) { try context.save() }
    }

    /// Причина, по которой в коде стоит возврат руками, а не `rollback()`.
    ///
    /// **Прежняя редакция этого докстринга уговаривала удалить живую
    /// защиту, и 05.10 чуть не уговорила.** Там стояло: «если Apple
    /// однажды починит `rollback()`, этот тест упадёт — и это правильно:
    /// значит, ручной возврат можно убрать». Apple починила его в iOS 27,
    /// тест упал на симуляторе 27.0, и вывод «можно убирать» выглядел
    /// прямо санкционированным.
    ///
    /// Убирать нельзя: `IPHONEOS_DEPLOYMENT_TARGET` = 17.0. На iOS 17–26
    /// `rollback()` значения не возвращает, и это **восемь поколений живых
    /// телефонов**. Снятие ручного возврата по зелёному на 27 сломало бы
    /// запись дозы у всех, кто не обновился, — молча: человек отмечает,
    /// видит подтверждение, записи нет.
    ///
    /// > Докстринг был верен в момент написания и устарел молча: он не знал,
    /// > что цель развёртывания останется 17.0. **Условие «когда можно
    /// > убрать» должно называть то, что его снимет, поимённо** — иначе
    /// > запись через месяц уговорит следующего.
    ///
    /// Убрать ручной возврат можно, когда `IPHONEOS_DEPLOYMENT_TARGET`
    /// станет 27.0 — и тогда же удалить ветку `iOS 17…26` ниже.
    ///
    /// Поэтому тест теперь **версионный**: он сторожит не «поведение Apple
    /// вообще», а то поведение, которое получит наш пользователь на своей
    /// версии. На обеих ветках он что-то утверждает — проверки, которой
    /// нечего проверять, здесь нет.
    @Test("rollback возвращает значения с iOS 27, а до неё — нет")
    func откатНеВозвращаетЗначения() throws {
        let время = Date()
        let context = try НеЗаписывающееХранилище.контекст { пишущий in
            let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: пишущий, время: время)
            let dose = DoseRecord(scheduledAt: время)
            dose.givenAt = время
            dose.medication = medication
            пишущий.insert(dose)
        }
        let доза = try #require(try context.fetch(FetchDescriptor<DoseRecord>()).first)

        доза.givenAt = nil
        #expect(throws: (any Error).self) { try context.save() }
        context.rollback()

        // Контекст считает себя чистым на ОБЕИХ версиях — это и было
        // опаснее всего: «изменений нет» говорится одинаково и когда
        // значение вернули, и когда потеряли.
        #expect(context.hasChanges == false)

        if #available(iOS 27.0, *) {
            // Apple починила: значение вернулось само.
            #expect(доза.givenAt != nil,
                    "На iOS 27 rollback() обязан вернуть значение. Если здесь nil — починку откатили, и ручной возврат снимать нельзя тем более.")
        } else {
            // iOS 17…26 — восемь поколений, ради которых возврат стоит руками.
            #expect(доза.givenAt == nil,
                    "На iOS < 27 rollback() значения не возвращает. Если здесь не nil — Apple починила его и в старых версиях, и тогда условие снятия ручного возврата надо перемерить.")
        }
    }

    @Test("Неудавшееся сохранение не портит само хранилище")
    func хранилищеОстаётсяПрежним() throws {
        let время = Date()
        let context = try НеЗаписывающееХранилище.контекст { пишущий in
            let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: пишущий, время: время)
            let dose = DoseRecord(scheduledAt: время)
            dose.givenAt = время
            dose.medication = medication
            пишущий.insert(dose)
        }
        let схема = try #require(try context.fetch(FetchDescriptor<Medication>()).first)
        _ = DoseScheduler.unmark(схема, scheduledAt: время, context: context)

        // Отметка на месте: до файла неудавшееся сохранение не дошло.
        #expect(схема.doses.first?.givenAt != nil)
    }

    @Test("Отметка не сохранилась — markGiven отвечает пусто")
    func отказСохраненияДаётПустойОтвет() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        let отметка = DoseScheduler.markGiven(medication, scheduledAt: время,
                                              by: "Виктория", at: время, context: context)

        #expect(отметка == nil)
    }

    /// Главное в задаче. Экран снимает догоняющие напоминания на t+30
    /// и t+60 ровно по непустому ответу `markGiven` — здесь тот же
    /// `if let`, что и в `TodayScreen.complete`, а счётчик стоит на месте
    /// `ReminderScheduler.cancelDose`.
    ///
    /// Если ответ непустой при непрошедшем сохранении, напоминания
    /// снимаются, доза остаётся неотмеченной, и человек даёт вторую.
    @Test("Напоминания не снимаются, пока отметка не легла в хранилище")
    func напоминанияОстаютсяПриОтказе() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        var напоминанийСнято = 0
        if let доза = DoseScheduler.markGiven(medication, scheduledAt: время,
                                              by: "Виктория", at: время, context: context) {
            _ = доза
            напоминанийСнято += 1
        }

        #expect(напоминанийСнято == 0)
    }

    @Test("После отказа доза остаётся неотмеченной, а не полуотмеченной")
    func откатВозвращаетДозуВНеотмеченные() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        _ = DoseScheduler.markGiven(medication, scheduledAt: время,
                                    by: "Виктория", at: время, context: context)

        // Призрака в контексте быть не должно: неотмеченная доза, на
        // которую экран смотрит как на отмеченную, — это та же потеря,
        // только с отсрочкой до перезапуска.
        let отмеченные = medication.doses.filter { $0.givenAt != nil }
        #expect(отмеченные.isEmpty)
    }

    @Test("После отказа таблетка не списана из пачки")
    func откатВозвращаетТаблеткуВПачку() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        _ = DoseScheduler.markGiven(medication, scheduledAt: время,
                                    by: "Виктория", at: время, context: context)

        #expect(medication.stockLeft == 30)
    }

    @Test("Пропуск не сохранился — markSkipped отвечает пусто")
    func пропускПриОтказеОтвечаетПусто() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        let пропуск = DoseScheduler.markSkipped(medication, scheduledAt: время,
                                                by: "Виктория", at: время, context: context)

        #expect(пропуск == nil)
        #expect(medication.doses.allSatisfy { $0.skippedAt == nil })
    }

    @Test("Снятие отметки не сохранилось — unmark отвечает отказом")
    func снятиеПриОтказеОтвечаетОтказом() throws {
        // Отметку кладём, пока хранилище ещё пишет: ломаться должно
        // именно снятие, иначе снимать было бы нечего.
        let время = Date()
        let context = try НеЗаписывающееХранилище.контекст { пишущий in
            let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: пишущий, время: время)
            let dose = DoseRecord(scheduledAt: время)
            dose.givenAt = время
            dose.givenBy = "Виктория"
            dose.medication = medication
            пишущий.insert(dose)
        }

        let схема = try #require(try context.fetch(FetchDescriptor<Medication>()).first)
        #expect(схема.doses.first?.givenAt != nil)

        let сняли = DoseScheduler.unmark(схема, scheduledAt: время, context: context)

        #expect(сняли == false)
        // Доза осталась отмеченной — и это честно: защита от двойной дозы
        // всё ещё включена, и человеку про это сказали, а не показали
        // «снова в списке» поверх отметки, которая никуда не делась.
        #expect(схема.doses.first?.givenAt != nil)
    }

    @Test("Когда хранилище пишет — markGiven отмечает и отвечает отметкой")
    func удачныйПутьНеСломан() throws {
        let context = try НеЗаписывающееХранилище.рабочийКонтекст()
        let время = Date()
        let (_, medication) = НеЗаписывающееХранилище.собакаСоСхемой(in: context, время: время)

        let отметка = DoseScheduler.markGiven(medication, scheduledAt: время,
                                              by: "Виктория", at: время, context: context)

        #expect(отметка != nil)
        #expect(отметка?.givenBy == "Виктория")
        #expect(medication.stockLeft == 29)
        #expect(DoseScheduler.markSkipped(medication, scheduledAt: время,
                                          by: "Виктория", at: время, context: context) == nil)
    }
}

@Suite("Молчаливые сбои · «Записано», когда не записано")
@MainActor
struct EventLogSilentFailureTests {

    private func состояние() -> AppState {
        let appState = AppState.наСвоёмТелефоне()
        appState.role = .owner
        appState.customPermissions = nil
        return appState
    }

    @Test("Запись не сохранилась — record отвечает пусто")
    func отказСохраненияДаётПустойОтвет() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        let appState = состояние()

        let event = EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: "Записано · Завтрак") { $0.grams = 60 }

        #expect(event == nil)
    }

    @Test("Тоста «Записано» при отказе нет — есть тревожный")
    func тостГоворитПравду() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        let appState = состояние()

        EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: "Записано · Завтрак") { $0.grams = 60 }

        #expect(appState.undo?.message == "Не записалось · нажми ещё раз")
        // И кнопки «Отменить» у него нет: отменять нечего.
        #expect(appState.undo?.action == nil)
    }

    @Test("После отказа записи в дневнике не остаётся")
    func призракаВЛентеНет() throws {
        let context = try НеЗаписывающееХранилище.контекст()
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        let appState = состояние()

        EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: "Записано · Завтрак") { $0.grams = 60 }

        // Иначе лента показывала бы еду, которой в хранилище нет.
        #expect(Diary.active(dog.events).isEmpty)
    }

    @Test("Когда хранилище пишет — тост прежний и запись на месте")
    func удачныйПутьНеСломан() throws {
        let context = try НеЗаписывающееХранилище.рабочийКонтекст()
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        let appState = состояние()

        let event = EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: "Записано · Завтрак") { $0.grams = 60 }

        #expect(event != nil)
        #expect(appState.undo?.message == "Записано · Завтрак")
        #expect(Diary.active(dog.events).count == 1)
    }
}

/// Один приём сохранения на весь проект — и места, где его не было.
///
/// **Почему набор появился.** `persist(_:otherwise:)` был написан для
/// отметок доз, где цена молчания — вторая таблетка, но лежал `private`
/// внутри `DoseScheduler`. Ровно там, где он нужен — восстановление
/// из файла, редакторы, эпизоды, результат прогулки, — стояли `try?`
/// или не было сохранения вовсе. Приём, запертый в одном классе,
/// не мешает написать пятую копию того же молчания.
@Suite("Молчаливые сбои · один приём на всех", .serialized)
@MainActor
struct PersistIdiomTests {

    @Test("persist возвращает «нет» и откатывает ровно то, что тронули")
    func возвращаетИОткатывает() throws {
        let context = try НеЗаписывающееХранилище.контекст { пишущий in
            пишущий.insert(Dog(name: "Стич", weightKg: 4.1))
        }
        let собака = try #require(try context.fetch(FetchDescriptor<Dog>()).first)

        собака.name = "Тео"
        let получилось = context.persist(otherwise: { собака.name = "Стич" })

        #expect(получилось == false, "запертое хранилище обязано ответить «нет»")
        #expect(собака.name == "Стич", "возврат вернул значение, которого rollback не возвращает")
    }

    @Test("persist отвечает «да», когда хранилище пишет")
    func отвечаетДа() throws {
        let context = ModelContext(Persistence.container())
        context.insert(Dog(name: "Стич", weightKg: 4.1))
        #expect(context.persist(otherwise: { Issue.record("возврат не должен был позваться") }))
    }

    /// Восстановление обещает строкой в коде, что переживёт закрытие
    /// приложения. До этого под обещанием стоял `try?`: при отказе метод
    /// возвращал число восстановленных записей, экран показывал
    /// «Восстановлено», а в хранилище не было ничего.
    @Test("Восстановление из файла не может молча не восстановить")
    func восстановлениеНеМолчит() throws {
        let пишущий = ModelContext(Persistence.container())
        пишущий.insert(Dog(name: "Стич", weightKg: 4.1))
        try пишущий.save()
        let архив = try BackupService.archive(context: пишущий, appVersion: "1.0.0")

        let запертый = try НеЗаписывающееХранилище.контекст()
        #expect(throws: (any Error).self) {
            _ = try BackupService.restore(архив, into: запертый, strategy: .replace)
        }
    }

    /// Сторож на приём, а не на случай: точечный тест чинит одно место,
    /// а `try?` рядом с `save()` заводится заново в следующем экране.
    ///
    /// **Почему список, а не ноль.** На 22.09.2026 молчаливых сохранений
    /// в приложении двадцать девять. Требовать ноль значит держать набор
    /// красным и приучить себя его не читать; убрать сторож совсем — значит
    /// разрешить тридцатое. Поэтому список с числами: **в перечисленных
    /// файлах число не должно расти, в остальных обязан быть ноль.**
    /// Чинится место — число уменьшается здесь же, и сторож становится
    /// строже сам собой.
    ///
    /// Файлов, уже проведённых через `ModelContext.persist(otherwise:)`,
    /// в списке нет: `Backup`, `DoseScheduler`, `Editors`, `IncidentSheet`,
    /// `WalkSheets`, `TodayScreen`. Вернётся туда `try?` — покраснеет сразу.
    @Test("Молчаливых `try? context.save()` не становится больше")
    func молчаливыхСохраненийНеБольше() throws {
        /// Долг на 22.09.2026. Числа обязаны уменьшаться и не обязаны расти.
        // Список пуст: молчаливых сохранений в коде не осталось
        // ни одного. Пустой словарь означает «в любом файле обязан быть
        // ноль» — строже и не бывает.
        let долг: [String: Int] = [:]

        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var посчитано: [String: [Int]] = [:]
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            guard let обход = FileManager.default.enumerator(
                at: корень.appendingPathComponent(каталог), includingPropertiesForKeys: nil
            ) else { continue }
            for случай in обход {
                guard let url = случай as? URL, url.pathExtension == "swift",
                      let текст = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (номер, строка) in текст.components(separatedBy: .newlines).enumerated()
                where строка.contains("try? context.save()") || строка.contains("try? ctx.save()") {
                    посчитано[url.lastPathComponent, default: []].append(номер + 1)
                }
            }
        }

        for (файл, строки) in посчитано.sorted(by: { $0.key < $1.key }) {
            let разрешено = долг[файл] ?? 0
            #expect(строки.count <= разрешено, """
                \(файл): молчаливых сохранений \(строки.count) при разрешённых \(разрешено) \
                — строки \(строки.map(String.init).joined(separator: ", ")). \
                Сохранение обязано отвечать «да» или «нет»: context.persist(otherwise:).
                """)
        }

        // Список обязан худеть вместе с кодом: починили файл — вычеркнули.
        for (файл, разрешено) in долг.sorted(by: { $0.key < $1.key })
        where (посчитано[файл]?.count ?? 0) < разрешено {
            Issue.record("""
                \(файл): молчаливых сохранений уже \(посчитано[файл]?.count ?? 0), \
                а в списке долга \(разрешено). Поправь число в тесте — иначе \
                сторож разрешает вернуть то, что убрали.
                """)
        }
    }
}
