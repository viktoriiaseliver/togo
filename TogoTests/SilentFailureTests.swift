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
    /// Если Apple однажды починит `rollback()`, этот тест упадёт — и это
    /// правильно: значит, ручной возврат можно убрать. Пока он зелёный,
    /// убирать нельзя.
    @Test("rollback у SwiftData не возвращает значения — потому и не он")
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

        // Вот оно: значение не вернулось, а контекст считает себя чистым.
        #expect(доза.givenAt == nil)
        #expect(context.hasChanges == false)
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
        let appState = AppState()
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
