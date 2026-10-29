import AppIntents
import SwiftData

/// Прогулка без экрана: метка у двери, «Команды», Siri, кнопка «Действие».
///
/// Смысл ровно один — момент выхода. Поводок в одной руке, собака тянет,
/// телефон в кармане; открыть приложение, найти кнопку и нажать «Пошли»
/// в этот момент никто не будет. Приложил телефон к наклейке у двери —
/// прогулка пошла. Вернулся, приложил ещё раз — записалась.
///
/// **Почему метка, а не геозона.** Геозона требует разрешения «Всегда»
/// на геопозицию и меняет то, что приложение о себе заявляет в App Store:
/// сейчас там честно написано «сбор данных не ведётся». Метка не знает
/// о человеке ничего и не просит ни одного разрешения — это кусок
/// пластика за пятьдесят рублей.
///
/// Настраивается один раз: «Команды» → «Автоматизация» → NFC →
/// сканировать наклейку → действие «Прогулка по метке».
@MainActor
enum WalkControl {
    /// Начать прогулку и зажечь живую активность.
    ///
    /// Имя собаки нужно самой активности, поэтому за ним всё равно
    /// приходится идти в дневник — заодно и проверяем, что собака есть.
    @discardableResult
    static func startAndAnnounce(at now: Date = Date()) throws -> ActiveSession {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }

        let author = AppState.storedUserName
        let session = ActiveSession(kind: .walk, startedAt: now, startedBy: author)
        ActiveSessionStore.save(session)
        LiveActivityController.startWalk(dogName: dog.name, by: author, at: now)  // кличка-в-слот: вход живой активности кормит и именительный ярлык, и винительные подписи — падеж знает слот
        return session
    }

    /// Закончить и записать.
    static func finish(_ session: ActiveSession, at now: Date = Date()) throws -> String {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }
        // Право — тем же путём, что у остальных голосовых записей:
        // у интента нет `AppState`, роль берётся из своей карточки.
        // Экранная прогулка спрашивает его через `EventLog`; здесь
        // запись собирает `WalkRecorder`, и без этой строки голосовой
        // путь оставался бы открытым у того, кому писать нельзя.
        guard QuickLog.можно(.walk, in: context) else {
            throw QuickLogError.noPermission
        }

        // `nil` у `record` значит «не сохранилось». Здесь он выбрасывался:
        // сессия стиралась, а Siri говорила «Записала» — прогулка с метки
        // или из «Команд» пропадала насовсем при честном «записано».
        // Не сохранилось — сессию не трогаем: приложение допишет её
        // при открытии (`дописатьПрогулкуСБлокировки`), а человек слышит
        // правду.
        guard WalkRecorder.record(session, dog: dog,
                                  author: AppState.storedUserName, context: context) != nil else {
            throw QuickLogError.storageUnavailable
        }
        ActiveSessionStore.save(nil)
        // Голосом закрытая прогулка с инцидентом — тот же эпизод, что
        // из шторки. `AppState` здесь нет: эпизод ляжет в базу, экран
        // подтянет его при открытии.
        if session.count(of: .incident) > 0 {
            EpisodeRaiser.afterIncident(dog: dog, context: context, appState: nil)
        }

        let minutes = Int(session.duration(at: now)) / 60
        let tail = session.marks.isEmpty ? "" : " · \(session.tally)"
        return "Записала · прогулка \(String(localized: "\(minutes) минут"))\(tail)"
    }
}

struct StartWalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Начать прогулку"
    static let description = IntentDescription(
        "Запускает таймер прогулки, не открывая приложение. Отметки можно ставить с экрана блокировки."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let running = ActiveSessionStore.load() {
            let minutes = Int(running.duration()) / 60
            return .result(dialog: "Прогулка уже идёт — \(String(localized: "\(minutes) минут")).")
        }
        try WalkControl.startAndAnnounce()
        return .result(dialog: "Пошли. Таймер идёт.")
    }
}

struct FinishWalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Закончить прогулку"
    static let description = IntentDescription("Останавливает таймер и записывает прогулку в дневник.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = ActiveSessionStore.load() else { throw QuickLogError.noWalk }
        let message = try WalkControl.finish(session)
        await LiveActivityController.finishWalk(outcome: session.tally)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Один тап на выходе, один на возвращении — та же метка.
///
/// Два разных действия на одной наклейке человек не разведёт: у двери
/// он не вспоминает, какое из них сейчас нужно. Метка знает это сама.
struct WalkTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Прогулка по метке"
    static let description = IntentDescription(
        "Одно действие на обе стороны: прогулка ещё не идёт — начинает, идёт — заканчивает и записывает."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let session = ActiveSessionStore.load() {
            let message = try WalkControl.finish(session)
            await LiveActivityController.finishWalk(outcome: session.tally)
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        try WalkControl.startAndAnnounce()
        return .result(dialog: "Пошли. Таймер идёт.")
    }
}
