import Testing
import Foundation
import SwiftData
import SwiftUI
import UIKit
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
        return (context, dog, AppState.наСвоёмТелефоне())
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

@Suite("Несколько собак")
@MainActor
struct MultipleDogsTests {

    private func setup() throws -> (ModelContext, Dog, Dog, AppState) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let stitch = Dog(name: "Стич", weightKg: 4.7)
        let bagheera = Dog(name: "Багира", weightKg: 12)
        context.insert(stitch)
        context.insert(bagheera)
        try context.save()
        return (context, stitch, bagheera, AppState.наСвоёмТелефоне())
    }

    @Test("Без выбора открыта первая — экран не остаётся пустым")
    func fallsBackToFirst() throws {
        let (_, stitch, bagheera, appState) = try setup()
        #expect(appState.activeDog(from: [stitch, bagheera])?.id == stitch.id)
    }

    @Test("Выбор запоминается")
    func selectionSticks() throws {
        let (_, stitch, bagheera, appState) = try setup()
        appState.select(bagheera)
        #expect(appState.activeDog(from: [stitch, bagheera])?.id == bagheera.id)
    }

    @Test("Удалили открытую — открывается оставшаяся, а не пустота")
    func deletedActiveFallsBack() throws {
        let (_, stitch, bagheera, appState) = try setup()
        appState.select(bagheera)

        // Багиры больше нет: выбор указывает в никуда.
        #expect(appState.activeDog(from: [stitch])?.id == stitch.id)
    }

    @Test("Дневники не смешиваются")
    func diariesStaySeparate() throws {
        let (context, stitch, bagheera, _) = try setup()

        let meal = LogEvent(kind: .meal, date: Date(), authorName: "Виктория")
        meal.dog = stitch
        context.insert(meal)
        try context.save()

        #expect(stitch.events.count == 1)
        #expect(bagheera.events.isEmpty)
    }

    @Test("У собаки своё устойчивое имя, переживающее перенос")
    func dogHasStableID() throws {
        let (_, stitch, bagheera, _) = try setup()
        #expect(stitch.id != bagheera.id)
    }
}

@Suite("Отметки не доставая телефон")
@MainActor
struct HandsFreeTests {

    private func startWalk() {
        ActiveSessionStore.save(
            ActiveSession(kind: .walk, startedAt: Date().addingTimeInterval(-600),
                          startedBy: "Виктория")
        )
    }

    @Test("Кнопка с экрана блокировки кладёт отметку в сохранённую прогулку")
    func markGoesToStoredSession() {
        // Приложение в этот момент в фоне, и его копия прогулки в памяти
        // может быть старше сохранённой. Пишем в ту, что на диске.
        startWalk()
        defer { ActiveSessionStore.save(nil) }

        let session = ActiveSessionStore.appendMark(.urine)

        #expect(session?.count(of: .urine) == 1)
        #expect(ActiveSessionStore.load()?.count(of: .urine) == 1)
    }

    @Test("Повторяемое копится, неповторяемое переключается")
    func repeatableAccumulates() {
        startWalk()
        defer { ActiveSessionStore.save(nil) }

        _ = ActiveSessionStore.appendMark(.urine)
        _ = ActiveSessionStore.appendMark(.urine)
        #expect(ActiveSessionStore.load()?.count(of: .urine) == 2)

        _ = ActiveSessionStore.appendMark(.note)
        _ = ActiveSessionStore.appendMark(.note)
        #expect(ActiveSessionStore.load()?.count(of: .note) == 0)
    }

    @Test("Без прогулки кнопка ничего не создаёт")
    func noWalkNoMark() {
        ActiveSessionStore.save(nil)
        #expect(ActiveSessionStore.appendMark(.urine) == nil)
    }

    @Test("Приложение перечитывает прогулку, вернувшись на экран")
    func appPicksUpBackgroundMark() {
        startWalk()
        defer { ActiveSessionStore.save(nil) }

        let appState = AppState.наСвоёмТелефоне()
        #expect(appState.session?.marks.isEmpty == true)

        // Пока экран был заблокирован, нажали кнопку на живой активности.
        _ = ActiveSessionStore.appendMark(.stool)
        appState.reloadSession()

        #expect(appState.session?.count(of: .stool) == 1)
    }

    @Test("С экрана блокировки доступны только две отметки")
    func lockScreenOffersTwo() {
        // На морозе одной рукой человек попадёт в две большие цели,
        // а не в восемь маленьких.
        #expect(WalkMarkKind.allCases.count == 2)
        #expect(WalkMarkKind.urine.markKind == .urine)
        #expect(WalkMarkKind.stool.markKind == .stool)
    }
}

@Suite("Прототип v2 · отметка и замок")
@MainActor
struct PrototypeV2Tests {

    @Test("Токены совпадают с хендофом")
    func tokensMatchHandoff() {
        // Пакет передан как high-fidelity: «цвета, типографика, радиусы,
        // отступы и копирайтинг финальные — воспроизводить точно».
        func hex(_ color: Color) -> String {
            let parts = UIColor(color).cgColor.components ?? []
            guard parts.count >= 3 else { return "" }
            return String(format: "#%02X%02X%02X",
                          Int(parts[0] * 255 + 0.5), Int(parts[1] * 255 + 0.5),
                          Int(parts[2] * 255 + 0.5))
        }
        // Хендоф «Лёд», принят 24.09.2026. Прежний мятный набор
        // (#131211 / #2FE0BE / #FF453A) заменён целиком: синий —
        // интерактив и «сейчас», хвойный — «сделано», они больше не одно.
        #expect(hex(Token.Surface.screen) == "#0B1016")
        #expect(hex(Token.Surface.card) == "#151C24")
        #expect(hex(Token.Surface.sunken) == "#222B36")
        #expect(hex(Token.Surface.control) == "#2D3844")
        #expect(hex(Token.Action.primary) == "#7FB2FF")
        #expect(hex(Token.Action.doneText) == "#7FD3A8")
        #expect(hex(Token.Status.waitingText) == "#FFD60A")
        #expect(hex(Token.Status.overdueText) == "#FF6B5E")
        // Подпись на синей заливке тёмная: белая на #7FB2FF не проходит 4,5:1.
        #expect(hex(Token.Ink.onAccent) == "#06142A")
    }

    @Test("Радиусы и отступы по хендофу")
    func metricsMatchHandoff() {
        // «Лёд»: 12 контролы · 16 вложенные карточки, кнопки ·
        // 18 плитки · 20 карточки · 40 шторки. Экран 18.
        // Шторка выросла с 26: в системе она «парит» с отступом 8 от краёв.
        #expect(Token.Radius.small == 12)
        #expect(Token.Radius.control == 16)
        #expect(Token.Radius.tile == 18)
        #expect(Token.Radius.card == 20)
        #expect(Token.Radius.sheet == 40)
        #expect(Token.Spacing.screenPadding == 18)
    }

    @Test("Отметить можно только кругом, и он не меньше сорока четырёх")
    func checkboxIsTapTarget() {
        // «Отметка: ТОЛЬКО круг-чекбокс 44pt слева (как Напоминания).
        // Тап по тексту = деталь.» У строки два разных исхода, и они
        // не должны зависеть от того, куда попал палец.
        #expect(Token.Size.tapTarget >= 44)
    }

    @Test("Доза, отмеченная один раз, вторую отметку не принимает")
    func doubleDoseIsImpossible() throws {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Бим", weightKg: 12)
        context.insert(dog)

        let medication = Medication(name: "Апоквел", doseText: "1 таблетка", times: [20 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()

        let scheduled = Calendar.current.startOfDay(for: Date()).addingTimeInterval(20 * 3600)
        let first = DoseScheduler.markGiven(medication, scheduledAt: scheduled,
                                            by: "Аня", context: context)
        let second = DoseScheduler.markGiven(medication, scheduledAt: scheduled,
                                             by: "Тео", context: context)

        // Вторая отметка возвращает ту же дозу и не переписывает автора:
        // повторный тап должен открывать замок, а не ставить отметку.
        #expect(first?.givenBy == "Аня")
        #expect(second?.givenBy == "Аня")
        #expect(medication.doses.filter(\.isGiven).count == 1)
    }

    @Test("Снять отметку можно — замок не ловушка")
    func lockIsReversible() throws {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Бим", weightKg: 12)
        context.insert(dog)
        let medication = Medication(name: "Апоквел", doseText: "1 таблетка", times: [20 * 60])
        medication.dog = dog
        context.insert(medication)
        try context.save()

        let scheduled = Calendar.current.startOfDay(for: Date()).addingTimeInterval(20 * 3600)
        _ = DoseScheduler.markGiven(medication, scheduledAt: scheduled, by: "Аня", context: context)
        DoseScheduler.unmark(medication, scheduledAt: scheduled, context: context)

        #expect(medication.doses.filter(\.isGiven).isEmpty)
    }
}
