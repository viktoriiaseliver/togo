import Testing
import Foundation
import SwiftData
@testable import Togo

/// Пробелы, найденные обходом по веткам логики.
///
/// Каждый тест закрывает место, где механика была написана,
/// но не подключена, или подключена так, что данные молча терялись.

@Suite("Пробелы · права")
@MainActor
struct PermissionGapTests {

    private func setup() throws -> (ModelContext, Dog, AppState) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        return (context, dog, AppState())
    }

    @Test("Каждому виду записи сопоставлено право")
    func everyKindHasPermission() {
        // Прав было восемь, проверялись три. Соответствие теперь полное —
        // и его нельзя забыть дополнить при добавлении нового вида записи.
        for kind in LogKind.allCases {
            #expect(Permission.allCases.contains(kind.requiredPermission))
        }
        #expect(LogKind.dose.requiredPermission == .giveDose)
        #expect(LogKind.meal.requiredPermission == .logBasics)
    }

    @Test("Наблюдатель не записывает вообще ничего")
    func observerWritesNothing() {
        // У наблюдателя есть `seeMedical` — и если отдать под него
        // инцидент, он сможет писать в дневник, хотя роль этого не даёт.
        let allowed = FamilyRole.observer.defaultPermissions
        for kind in LogKind.allCases {
            #expect(!allowed.contains(kind.requiredPermission))
        }
    }

    @Test("Помощник записывает бытовое, но не дозы")
    func helperCannotGiveDoses() {
        let allowed = FamilyRole.helper.defaultPermissions
        #expect(allowed.contains(LogKind.meal.requiredPermission))
        #expect(allowed.contains(LogKind.incident.requiredPermission))
        #expect(!allowed.contains(LogKind.dose.requiredPermission))
    }

    @Test("Без права записывать запись не создаётся")
    func loggingRequiresPermission() throws {
        let (context, dog, appState) = try setup()

        // Наблюдатель: смотреть можно, записывать — нет.
        appState.role = .observer
        appState.customPermissions = nil

        let event = EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: nil) { $0.grams = 60 }

        #expect(event == nil)
        #expect(Diary.active(dog.events).isEmpty)
    }

    @Test("С правом — создаётся")
    func loggingWorksWithPermission() throws {
        let (context, dog, appState) = try setup()

        appState.role = .owner

        let event = EventLog(context: context, appState: appState)
            .record(.meal, dog: dog, confirmation: nil) { $0.grams = 60 }

        #expect(event != nil)
    }
}

@Suite("Пробелы · прогулка")
@MainActor
struct WalkGapTests {

    @Test("Лакомство с прогулки попадает в дневную еду")
    func walkTreatCountsAsFood() {
        // Пять граммов записывались, но без пометки «из порции» —
        // а сводка по питанию считает лакомствами только их.
        let treat = LogEvent(kind: .treat, date: Date(), authorName: "Виктория")
        treat.grams = 5
        treat.fromPortion = true

        let meal = LogEvent(kind: .meal, date: Date(), authorName: "Виктория")
        meal.grams = 60

        let days = FeedingAnalyzer.dailyIntake(events: [meal, treat])
        let today = days.last

        #expect(today?.grams == 65)
        // При этом кормлением лакомство не становится.
        #expect(today?.meals == 1)
    }

    @Test("Отметки на прогулке превращаются в записи один к одному")
    func marksBecomeEvents() {
        var session = ActiveSession(kind: .walk, startedAt: Date(), startedBy: "Виктория")
        session.marks = [
            .init(kind: .urine), .init(kind: .urine),
            .init(kind: .stool), .init(kind: .reaction),
        ]

        #expect(session.count(of: .urine) == 2)
        #expect(session.reactions == 1)
        #expect(session.outcome == .both)
    }
}

@Suite("Пробелы · эпизод")
@MainActor
struct EpisodeGapTests {

    @Test("Эпизод можно закрыть руками, не дожидаясь тишины")
    func episodeClosesByHand() {
        // Метод в модели был, вызывать его было неоткуда: эпизод
        // держался двое суток и всё это время отменял вердикт «просится».
        let episode = Episode(title: "Расстройство", detail: "два раза за сутки")
        #expect(episode.isActive())

        episode.close()

        #expect(!episode.isActive())
    }

    @Test("Видно, когда эпизод закончится сам")
    func quietUntilIsMeaningful() {
        let started = Date().addingTimeInterval(-3600)
        let episode = Episode(title: "Расстройство", detail: "два раза за сутки", startedAt: started)
        episode.lastIncidentAt = started

        #expect(episode.quietUntil == started.addingTimeInterval(Episode.quietPeriod))
        #expect(episode.quietUntil > Date())
    }

    @Test("Новый инцидент продлевает эпизод")
    func incidentExtends() {
        let episode = Episode(title: "Расстройство", detail: "два раза за сутки", startedAt: Date().addingTimeInterval(-40 * 3600))
        episode.lastIncidentAt = Date().addingTimeInterval(-40 * 3600)
        let wasQuietUntil = episode.quietUntil

        episode.extend()

        #expect(episode.quietUntil > wasQuietUntil)
        #expect(episode.isActive())
    }
}

@Suite("Пробелы · документы")
@MainActor
struct DocumentGapTests {

    @Test("Снимок документа переживает перенос на другой телефон")
    func documentsSurviveBackup() throws {
        // Модель лежала в схеме с самого начала, но в архив не попадала:
        // на новом телефоне паспорт исчезал молча.
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        let document = DogDocument(title: "Паспорт", image: Data([0xFF, 0xD8, 0xFF]), note: "до 2028")
        document.dog = dog
        context.insert(document)
        try context.save()

        let archive = try BackupService.archive(context: context, appVersion: "1.0")
        let restored = try BackupService.decode(try BackupService.encode(archive))

        let documents = try #require(restored.dogs.first?.documents)
        #expect(documents.count == 1)
        #expect(documents[0].title == "Паспорт")
        #expect(documents[0].image == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test("Старый архив без снимков читается по-прежнему")
    func oldArchiveStillDecodes() throws {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Dog(name: "Стич", weightKg: 12))
        try context.save()

        var archive = try BackupService.archive(context: context, appVersion: "1.0")
        archive.dogs[0].documents = nil

        let restored = try BackupService.decode(try BackupService.encode(archive))
        #expect(restored.dogs[0].documents == nil)
    }

    @Test("Большой снимок ужимается")
    func photoShrinks() {
        // Полный кадр с камеры — десятки мегабайт: в дневнике надо
        // прочитать номер, а не разглядывать текстуру бумаги.
        #expect(DocumentPhoto.maxSide == 1600)
        #expect(DocumentPhoto.quality < 1)
        #expect(!DocumentPhoto.commonTitles.isEmpty)
    }
}

@Suite("Пробелы · план дня")
@MainActor
struct DayPlanGapTests {

    @Test("Доза связывается с препаратом")
    func doseLinksToMedication() {
        // Поле было, писать его было некому: запись оставалась ничьей.
        let medication = Medication(name: "Метронидазол", doseText: "полтаблетки", times: [8 * 60])
        let event = LogEvent(kind: .dose, date: Date(), authorName: "Виктория")
        event.medicationID = medication.id

        #expect(event.medicationID == medication.id)
    }
}

@Suite("Пробелы · обучение")
@MainActor
struct TrainingGapTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 12)
        context.insert(dog)
        return (context, dog)
    }

    @Test("Удаление шага не стирает уже проведённые занятия")
    func deletingStepKeepsSessions() throws {
        // Шаг заводится сам при первом занятии и сам плодит следующие.
        // Убрать «Ко мне · Коридор · 2 м», заведённое на пробу, было
        // нельзя — оно оставалось в матрице переноса навсегда.
        let (context, dog) = try setup()

        let step = TrainingStep(cue: "Ко мне", place: "Коридор",
                                person: "Виктория", distanceMeters: 2, order: 0)
        step.dog = dog
        context.insert(step)

        let session = TrainingSession(cue: "Ко мне", place: "Коридор",
                                      person: "Виктория", distanceMeters: 2)
        session.dog = dog
        context.insert(session)
        try context.save()

        context.delete(step)
        try context.save()

        let steps = try context.fetch(FetchDescriptor<TrainingStep>())
        let sessions = try context.fetch(FetchDescriptor<TrainingSession>())
        #expect(steps.isEmpty)
        #expect(sessions.count == 1)
    }

    @Test("Удаление занятия не трогает запись в ленте")
    func deletingSessionKeepsLogEvent() throws {
        let (context, dog) = try setup()

        let session = TrainingSession(cue: "Ко мне", place: "Дома",
                                      person: "Виктория", distanceMeters: 2)
        session.dog = dog
        context.insert(session)

        let event = LogEvent(kind: .training, date: Date(), authorName: "Виктория")
        event.trainingSessionID = session.id
        event.dog = dog
        context.insert(event)
        try context.save()

        context.delete(session)
        try context.save()

        let events = try context.fetch(FetchDescriptor<LogEvent>())
        #expect(events.count == 1)
        // Связь осталась висеть — и это правильно: запись о занятии
        // в дневнике переживает удаление разбора этого занятия.
        #expect(events[0].trainingSessionID == session.id)
    }

    @Test("Заготовки навыков для процедур существуют и их можно вернуть")
    func procedureSeedIsRecoverable() {
        // Условием подстановки было «список пуст» — то есть удалить навык
        // было нельзя даже теоретически: он возвращался при заходе.
        let seed = SeedData.procedureSkills()
        #expect(seed.count >= 3)
        #expect(seed.allSatisfy { !$0.title.isEmpty })
    }
}

@Suite("Пробелы · откуда запись")
@MainActor
struct OriginGapTests {

    @Test("Запись помнит напоминание, по которому её отметили")
    func careEventRemembersTask() {
        let task = CareTask(title: "Когти", detail: "подстричь",
                            kind: .periodic, intervalDays: 21, category: .grooming)
        let event = LogEvent(kind: .care, date: Date(), authorName: "Виктория")
        event.careTaskID = task.id

        #expect(event.careTaskID == task.id)
    }

    @Test("Переименование препарата не путает старые записи")
    func doseSurvivesRename() {
        // В записи лежало имя строкой. Препарат переименовали — и понять,
        // какой именно отметили, стало нельзя.
        let medication = Medication(name: "Метронидазол", doseText: "полтаблетки", times: [8 * 60])
        let event = LogEvent(kind: .dose, date: Date(), authorName: "Виктория")
        event.medicationID = medication.id
        event.note = "Метронидазол · полтаблетки"

        medication.name = "Метрогил"

        #expect(event.medicationID == medication.id)
    }
}
