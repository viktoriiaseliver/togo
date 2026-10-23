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

    /// Имя этого теста было «Отметки на прогулке превращаются в записи
    /// один к одному» — и записей он не проверял вовсе: все три проверки
    /// спрашивают `ActiveSession`, то есть счёт отметок в памяти, до
    /// всякой записи в дневник. Имя читают ВМЕСТО кода, и идущий сюда
    /// грепом за «один к одному» получал обратное представление
    /// о покрытии.
    ///
    /// С 07.10.2026 оно врало и по существу: два тапа «пописал» без
    /// промежутка стали **одной** записью, один к одному больше не правило.
    /// Имя приведено к телу, а не тело к имени: обещание про записи
    /// проверяют там, где оно и проверялось всё время, —
    /// `EditAndTagTests` «Отметки прогулки становятся записями и знают
    /// свою прогулку» и `DuplicateGuardTests` «Настоящие повторы пачка
    /// не теряет».
    @Test("Сессия считает отметки по видам и выводит исход выхода")
    func sessionCountsMarksAndDerivesOutcome() {
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
        // **Трейты закрепляются, а не берутся у среды.** Прежняя
        // редакция читала `UIColor(color).cgColor.components` — то есть
        // значение по `UITraitCollection.current`, какой бы та ни была.
        // У модульного прогона нет окна приложения, и текущая коллекция
        // в нём не тёмная; а токены с 07.10.2026 **четырёхрежимные**
        // (`night1`: dark `#050503`, light `#FFFFFF`). Приложение при
        // этом тёмное и только тёмное (`UIUserInterfaceStyle = Dark`).
        //
        // > **Сторож сравнивал ожидаемое тёмное с тем, что отдала
        // > неизвестная коллекция.** Пока прогон не доходил до конца,
        // > этого не было видно: первый полный прогон за двое суток
        // > состоялся 09.10 и предъявил расхождение.
        //
        // Разрешитель НЕ свой: `Color.resolvedHex(dark:highContrast:)`
        // (`DynamicColor.swift:95`) заведён ровно как вход для приёмки,
        // и его уже зовут `EmptyStateFrameTests:94`
        // и `ThemeContrastTests:294`. Второй завести значило бы мерить
        // одну реализацию наблюдениями за другой.
        func hex(_ color: Color) -> String {
            let rgb = color.resolvedHex(dark: true, highContrast: false) >> 8
            return String(format: "#%06X", rgb)
        }
        // Хендоф «ФИНАЛ» (Graphite), принят 05.10.2026, макет
        // sha256 d804c1ea…. Третье поколение: мята → «Лёд» (синий) →
        // лайм. Значения взяты из DesignTokens/ядро-дизайна/tokens/ по РОЛИ,
        // режим Dark: наши имена остались прежними, сменились числа.
        //
        // ЭТОТ СТОРОЖ ДЕРЖИТ КОПИЮ ЧИСЕЛ, и это его слабость, названная
        // вслух: он краснеет на смене поколения — как покраснел сейчас,
        // и это правильно, — но не заметит, если наше значение разойдётся
        // с хендофом ВНУТРИ поколения. У Gamut так `0x5972FE` в тесте
        // пережил замену цвета в приложении на два дня. Сильная форма —
        // читать `tokens/colors.css` и `togo.css` прямо из пакета, он
        // теперь лежит в git; мешает одно: соответствие наших имён
        // их переменным установлено ПО РОЛИ человеком, и перенос этого
        // суждения в тест его не проверит, а продублирует.
        // ПОКОЛЕНИЕ СМЕНИЛОСЬ ЧЕТВЁРТЫЙ РАЗ: мята → «Лёд» → лайм →
        // Graphite → **«Кино»**. Решение Виктории 22.10.2026, прямым
        // выбором из трёх названных вариантов с ценой: «Кино» ЗАМЕНЯЕТ
        // Graphite, а не ложится поверх третьим набором. Записано
        // с адресом в `Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`, раздел «РЕДИЗАЙН iOS 28».
        //
        // Числа взяты по РОЛИ из `Дизайн/редизайн-ios28/tokens/
        // togo-ios28.tokens.json`, ветка `cinema.surface`, режим Dark:
        //
        //   background #000000 → screen     page #0A0A0B → Surface.page
        //   card       #1C1C1E → card       raised #2C2C2E → sunken
        //   pressed    #3A3A3C → pressed
        //
        // **Почему правка числа здесь не запрещена — проверено, а не
        // объявлено.** Запрет стоит против «число подняли ВМЕСТО работы».
        // Замер: на вершине `5bbbf4b` (21.10) `primitive.radius.card`
        // был `28px`, сейчас `24px`, сменили коммиты `6821646` и `8705dfb`
        // — то есть работа сделана и лежит в git, а копия в стороже
        // ОТСТАЛА. Голова этого сторожа предсказала собственную красноту
        // уже второй раз подряд.
        #expect(hex(Token.Surface.screen) == "#000000")   // cinema.surface.background
        #expect(hex(Token.Surface.card) == "#1C1C1E")     // cinema.surface.card
        #expect(hex(Token.Surface.sunken) == "#2C2C2E")   // cinema.surface.raised
        // **СТОЛКНОВЕНИЕ, НАЗВАННОЕ ВСЛУХ 22.10 И ЗАКРЫТОЕ 23.10.2026
        // ОТВЕТОМ ДИЗАЙНА.** `sunken` и `control` сидели на разных
        // примитивах (`night3` и `night4`), но в тёмной оба давали
        // `#2C2C2E` байт в байт. Вопрос был задан дизайну и получил
        // прямой ответ, дословно: «`surface-control` #3A3A3C, нажатие
        // #48484A. `surface-sunken` остаётся #2C2C2E. Совпадение
        // не задумано» (`Дизайн/редизайн-ios28/README.md`, раздел
        // «Решения по вопросам разработки», пункт 2).
        //
        // **ЧИСЛО ЗДЕСЬ ПОДНЯТО ПОТОМУ, ЧТО ЗА НИМ ЛЕЖИТ РАБОТА, —
        // и это замер, а не заявление.** `git show 0a369c0:DesignTokens/
        // tokens.json` даёт `night4.dark` = `#2C2C2E`, в дереве после
        // правки `#3A3A3C`; контроль на заведомо НЕ тронутом `night3.dark`
        // — `#2C2C2E` в обоих, то есть разборщик работает и разница
        // не померещилась. Запрет на правку копии стоит против «число
        // подняли ВМЕСТО работы»; здесь работа — смена значения примитива
        // в источнике правды, и копия ОТСТАЛА от неё.
        //
        // **ЧТО ПОЕХАЛО, А ЧТО НЕТ — ПЕРЕСЧИТАНО НА `0a369c0`, потому
        // что прежние числа этой строки (23 / 4 / 17) были сняты
        // на другом коммите.** Считано `git grep -o`, ВХОЖДЕНИЙ,
        // не строк, по `Togo/ TogoShared/ TogoWidgets/`:
        //
        //     Surface.sunken          22  ← НЕ ТРОНУТО НИ ОДНО
        //     Surface.control          4  ← поехало
        //     Surface.card            18  (контроль: счёт работает)
        //     Surface.такогоНетВовсе   0  (отрицательный контроль)
        //
        // Двигался примитив `night4`, а у него две производные, и это
        // НАЗВАНО, а не умолчано: вместе с `Surface.control` (4) поехали
        // `Button.Secondary.background` (2 читателя) и `Action.secondary`
        // (1). Все три — роли плашки контрола, ради которых дизайн
        // и давал значение. `Surface.sunken` (22) не двинулся.
        //
        // В светлой `control` и `sunken` расходились и прежде
        // (`#FFFFFF` против `#E3E5E8`), светлого «Кино» хендофф
        // не даёт, и светлые столбцы не тронуты.
        #expect(hex(Token.Surface.control) == "#3A3A3C")  // cinema.surface.control
        // **Копия ОТСТАЛА на поколение, и голова этого сторожа сама
        // это предсказала** — «он краснеет на смене поколения… и это
        // правильно». Она оказалась права дважды, и вторая правота
        // дороже первой: она предсказала собственную красноту.
        //
        // Поколение Graphite, 07.10.2026: акцент ИНДИГО `#A2C1FE`.
        // Решение записано не здесь и не в чате, а В САМОМ ТОКЕНЕ —
        // `DesignTokens/tokens.json:87`: «ИНДИГО, поколение Graphite
        // 07.10.2026… 11,26:1 на странице, 9,10:1 на карточке —
        // измерено после смены, не перенесено. Прежнее поколение —
        // лайм #D4F75F, снято решением „лайм больше не используется“».
        //
        // **Почему правка числа здесь не запрещена.** Запрет стоит
        // против «число подняли ВМЕСТО работы». Здесь работа сделана
        // и записана с датой, доводом и замером — значит число
        // ОТСТАЛО, а не завышено. Различается за минуту: у индиго есть
        // дата, довод и контраст, у лайма — «снято решением».
        // **ЧЕТВЁРТОЕ ПОКОЛЕНИЕ: акцент БЕЛЫЙ.** `cinema.action.primary`
        // = `#FFFFFF`. Индиго снято как акцент по умолчанию решением
        // Виктории 22.10.2026 — вместе с решением 20.10, которое она
        // принимала прямым вопросом по двум кадрам.
        //
        // > **Индиго отменено как АКЦЕНТ, но живо как ЗНАЧЕНИЕ**, и это
        // > не оговорка, а замер по кадрам: `#1F4FFF` остаётся цветом
        // > тона дозы, активной вкладки таб-бара и полосы-косточки,
        // > `#A2C1FE` — это `category.poop` и `cinema.text.link`.
        // > Белая кнопка — ОБЫЧНОЕ состояние, а не все шесть: у дозы
        // > она синяя, у тревоги терракотовая. Цвет берётся у тона,
        // > а не стоит безусловно, — за это отвечает `ReadingTone`.
        //
        // И отдельно: `arctic` в СВЕТЛОЙ остался `#1F4FFF`, а `lightHC`
        // — `#0E14A1`. То есть решение 20.10 не стёрто, оно перестало
        // быть видимым по умолчанию. Кадры `Дизайн/кадры-приёмки/
        // акцент-светлый-20.10/` с 22.10 ничего не подтверждают —
        // записано рядом с ними.
        #expect(hex(Token.Action.primary) == "#FFFFFF")   // cinema.action.primary
        #expect(hex(Token.Status.waitingText) == "#F7C75F") // color.status.warning
        #expect(hex(Token.Status.overdueText) == "#FF7A66") // color.status.error
        #expect(hex(Token.Status.stockLowText) == "#FFA15C") // togo.css --stock-low
        // Подпись на лаймовой заливке тёмная, и теперь это не «норма
        // не проходит», а «не видно вовсе»: белое на #D4F75F даёт 1,22:1.
        // Второе поколенческое число, тот же источник решения
        // (`tokens.json:114`): «Текст на акцентной заливке, 10,43:1.
        // accent.dark.on. Подпись на акценте обязана брать этот токен,
        // а не `Color.white`: белый на индиго #A2C1FE даёт 1,63:1,
        // то есть не читается».
        // Акцент стал белым — значит подпись НА нём стала тёмной:
        // `cinema.action.onPrimary` = `#111111`. Довод прежней редакции
        // («белый на индиго #A2C1FE даёт 1,63:1») никуда не делся, он
        // просто поменял сторону: теперь не читался бы ТЁМНЫЙ фон под
        // светлым текстом, а `#111111` на `#FFFFFF` даёт 18,88:1.
        #expect(hex(Token.Ink.onAccent) == "#111111")     // cinema.action.onPrimary
        // «Сделано» НЕ перенесено: зелёного в поколении «финал» нет
        // вовсе (ноль success/done/green в colors.css и accents.css).
        // Подменять его акцентом значило бы решить продуктовый вопрос
        // правкой токена, поэтому хвойный остался от «Льда».
        #expect(hex(Token.Action.doneText) == "#7FD3A8")
    }

    @Test("Радиусы и отступы по хендофу")
    func metricsMatchHandoff() {
        // Ядро Graphite (GRAPHITE.md, «Форма и отступы»), 05.10.2026:
        // шит 36 · карточка 28 · строка 24 · вложенные 16 · пилюля 999.
        // Прежние числа «Льда» (12 · 16 · 18 · 20 · 40) расходились
        // с ядром все до одного.
        #expect(Token.Radius.small == 12)     // вложенное в строку: 24 − поле 12
        #expect(Token.Radius.control == 24)   // --radius-row
        #expect(Token.Radius.tile == 16)      // --radius-inner
        // **24, а не 28 — и отстал СТОРОЖ, а не токен.** Хендофф iOS 28
        // («Кино») задаёт `size.cardRadius: 24`; `Token.Radius.card`
        // приведён к нему коммитами `6821646` и `8705dfb` 22.10.2026.
        //
        // Проверено, а не объявлено: `git show 5bbbf4b:DesignTokens/
        // tokens.json` даёт `card = 28px` на вершине 21.10, сейчас
        // `24px`. То есть работа лежит в git, и число здесь ОТСТАЛО —
        // это не «подогнали сторож под код».
        //
        // Соседние радиусы хендоффа, у которых в этом стороже адреса
        // пока нет: `heroRadius 32` (панель показания), `heroPanelRadius
        // 24` (стеклянная панель внутри неё), `rowIconRadius 13`,
        // `doseShapeRadius 12` (доза — скруглённый квадрат, а не круг).
        // Названы здесь, чтобы следующий не считал их проверенными.
        #expect(Token.Radius.card == 24)      // size.cardRadius хендоффа iOS 28
        #expect(Token.Radius.sheet == 36)     // --radius-sheet
        // Пилюля — бесконечный радиус, а не половина известной высоты.
        // Было 30 «половина капсулы 60 pt»: скругление держалось
        // на ЗНАНИИ высоты и переставало быть пилюлей молча при другой.
        #expect(Token.Radius.capsule >= 999)
        // ОТСТУП ЭКРАНА ещё НЕ приведён к ядру, и это намеренно.
        // Ядро задаёт его адаптивным: 16 на 320–374 pt и 20 от 375.
        //
        // ПОПРАВКА к первой редакции этого комментария (она же — к коммиту
        // 9c07321): я написал «оси ширины в токенах нет, снимет её ось».
        // Неверно. `SwiftUI.md` ядра показывает, что оси нет и У НИХ:
        //   .contentMargins(.horizontal, sizeClass == .compact && width < 375 ? 16 : 20)
        // то есть выбор делается В МЕСТЕ ВЫЗОВА, а токенов два обычных —
        // 16 и 20. Значит это не «завести измерение, которого система
        // не выражает», а «перестать держать одно число там, где ядро
        // держит условие». Работа меньше, чем я её назвал, и другого рода.
        //
        // Пока условие не заведено, 18 — названная граница, а не недосмотр.
        // Снимет её переход на `.contentMargins` с двумя токенами.
        // Замер togo-5a: округление сетки двигает до четверти кадра,
        // и это перевёрстка, а не сдвиг, — поэтому менять 18 на 20
        // отдельной правкой нельзя, это заменит одно неверное другим.
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
