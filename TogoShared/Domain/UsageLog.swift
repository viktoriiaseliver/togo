import Foundation

/// Журнал действий: что человек делал в приложении и чем это кончилось.
///
/// Это не аналитика и не телеметрия. Никуда ничего не уходит: файл лежит
/// в папке документов самого приложения, читается в «Настройках» и
/// забирается с телефона (`Tools/pull_usage_log.sh`). Нужен он для одного —
/// через две недели живого пользования сесть и посмотреть, где приложение
/// мешало: где тапнули не туда, где отменили сразу после записи, где экран
/// открыли и тут же закрыли.
///
/// **Что пишется.** Только имена действий и короткие пометки из
/// перечислений: «record · meal · done». Ни граммов, ни заметок, ни клички,
/// ни имён людей — то есть по журналу нельзя восстановить ни одной записи
/// дневника. Это не осторожность на всякий случай: обещание с первого
/// экрана онбординга — «всё считается на телефоне» — не должно ломаться
/// об отладочный файл.
///
/// **Как пишется.** Строка JSON на действие, добавлением в конец файла.
/// Запись уходит в свою очередь: тап не должен ждать диска.
nonisolated enum UsageLog {

    // MARK: Что записываем

    /// Одно действие.
    struct Entry: Codable, Sendable, Equatable {
        /// Когда.
        var at: Date
        /// Сеанс: непрерывная работа с приложением. Новый начинается после
        /// пятнадцати минут без единого действия.
        var session: String
        /// Где человек находился.
        var screen: String
        /// Что сделал.
        var action: String
        /// Чем кончилось.
        var outcome: String
        /// Уточнение из перечисления: вид записи, имя настройки, причина отказа.
        var detail: String?

        var kind: Action? { Action(rawValue: action) }
        var result: Outcome { Outcome(rawValue: outcome) ?? .done }
    }

    /// Экран, на котором человек стоял.
    ///
    /// Список закрытый намеренно: свободная строка рано или поздно принесёт
    /// в журнал кличку собаки, а этого здесь быть не должно.
    enum Screen: String, Sendable, CaseIterable {
        case today, needs, walk, feeding, foodStock, health, vetSummary, care
        case history, training, family, sitter, trip, dayOut, emergency
        case incident, profile, schedule, onboarding, paywall
        case settings, backup, dataPrivacy, usageLog, other

        var title: String {
            switch self {
            case .today: "Сегодня"
            case .needs: "Просится"
            case .walk: "Прогулка"
            case .feeding: "Кормление"
            case .foodStock: "Запас корма"
            case .health: "Здоровье"
            case .vetSummary: "Отчёт врачу"
            case .care: "Уход"
            case .history: "История"
            case .training: "Занятия"
            case .family: "Семья"
            case .sitter: "Ситтер"
            case .trip: "Поездка"
            case .dayOut: "День с собакой"
            case .emergency: "Если что-то случилось"
            case .incident: "Инцидент"
            case .profile: "Собака"
            case .schedule: "Режим дня"
            case .onboarding: "Онбординг"
            case .paywall: "Подписка"
            case .settings: "Настройки"
            case .backup: "Перенос"
            case .dataPrivacy: "Данные"
            case .usageLog: "Журнал действий"
            case .other: "прочее"
            }
        }
    }

    /// Что человек сделал. Уточнение уходит в `detail`, поэтому список
    /// действий остаётся коротким и его хватает надолго.
    enum Action: String, Sendable, CaseIterable {
        /// Экран или шторка открылись.
        case open
        /// Переключили вкладку.
        case tab
        /// Запись в дневник. `detail` — вид записи.
        case record
        /// Поправили запись.
        case edit
        /// Удалили запись.
        case delete
        /// Нажали «Отменить» в тосте.
        case undo
        /// Начали выход, прогулку или занятие.
        case start
        /// Закончили их.
        case finish
        case pause
        case resume
        /// Отметка на ходу во время прогулки.
        case mark
        /// Доза: `detail` — given / skipped / unmarked / claimed.
        case dose
        /// Дело ухода: `detail` — done / undone / snooze.
        case care
        /// Поменяли настройку. `detail` — какую.
        case setting
        /// Выгрузка CSV или отчёта.
        case export
        /// Сохранение и загрузка файла дневника.
        case backup
        /// Подписка: показали экран, купили, восстановили.
        case purchase
        /// Приложение не смогло сделать то, что обещало. `detail` — что именно.
        case failure

        var title: String {
            switch self {
            case .open: "открыл экран"
            case .tab: "переключил вкладку"
            case .record: "записал"
            case .edit: "поправил"
            case .delete: "удалил"
            case .undo: "отменил"
            case .start: "начал"
            case .finish: "закончил"
            case .pause: "поставил на паузу"
            case .resume: "продолжил"
            case .mark: "отметил на ходу"
            case .dose: "доза"
            case .care: "уход"
            case .setting: "настройка"
            case .export: "выгрузил"
            case .backup: "перенос"
            case .purchase: "подписка"
            case .failure: "не получилось"
            }
        }
    }

    /// Чем кончилось действие. Ради этого журнал и заводится: «сделал»
    /// само по себе ничего не чинит, а «не дали» и «дубль» — чинят.
    enum Outcome: String, Sendable, CaseIterable {
        /// Получилось.
        case done
        /// Не хватило прав.
        case blocked
        /// Поймали второй тап по той же кнопке.
        case duplicate
        /// Передумали и закрыли.
        case cancelled
        /// Приложение не справилось.
        case failed
        /// Показывать было нечего.
        case empty

        var title: String {
            switch self {
            case .done: "сделано"
            case .blocked: "не дали прав"
            case .duplicate: "двойной тап"
            case .cancelled: "передумал"
            case .failed: "сбой"
            case .empty: "пусто"
            }
        }
    }

    // MARK: Ручка включения

    /// Журнал можно выключить. По умолчанию включён: он и заведён ради того,
    /// чтобы первые недели пользования не пропали зря.
    ///
    /// В UI-тестах молчит всегда, и это не настройка, а свойство запуска:
    /// иначе робот, который за минуту нажимает всё подряд, наполняет журнал
    /// действиями, которых человек не делал, — и отчёт врёт.
    static var isOn: Bool {
        get {
            guard !isUITesting else { return false }
            return defaults.object(forKey: Keys.isOn) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Keys.isOn) }
    }

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    // MARK: Запись

    /// Отметить действие.
    ///
    /// - Parameters:
    ///   - action: что сделал человек.
    ///   - detail: уточнение из перечисления — вид записи, имя настройки.
    ///     Свободный текст человека сюда не попадает никогда.
    ///   - screen: где. Пусто — берём последний открытый экран.
    ///   - outcome: чем кончилось.
    static func note(_ action: Action,
                     _ detail: String? = nil,
                     on screen: Screen? = nil,
                     outcome: Outcome = .done,
                     at date: Date = Date()) {
        guard isOn else { return }
        let entry = Entry(
            at: date,
            session: session(at: date),
            screen: (screen ?? currentScreen).rawValue,
            action: action.rawValue,
            outcome: outcome.rawValue,
            detail: detail
        )
        append(entry)
    }

    /// Человек открыл экран. Заодно запоминаем его как текущий, чтобы
    /// остальные вызовы не передавали экран руками — забудут ровно там,
    /// где важнее всего.
    ///
    /// Экраны держатся стопкой, а не одним значением: шторка закрывается,
    /// и текущим снова должен стать тот экран, поверх которого она стояла.
    /// Иначе всё, что человек сделает после закрытия «Просится», окажется
    /// записано на «Просится».
    static func entered(_ screen: Screen, at date: Date = Date()) {
        lock.lock()
        let same = stack.last == screen
        if !same { stack.append(screen) }
        // Стопка не должна расти без края, если чей-то `onDisappear`
        // не пришёл: экраны не вкладываются друг в друга десятками.
        if stack.count > 12 { stack.removeFirst(stack.count - 12) }
        lock.unlock()
        // Повторный `onAppear` того же экрана — это возврат к нему,
        // а не новое открытие: SwiftUI зовёт его и после закрытия шторки.
        guard !same else { return }
        note(.open, on: screen, at: date)
    }

    /// Экран закрылся: текущим снова становится тот, что был под ним.
    static func left(_ screen: Screen) {
        lock.lock(); defer { lock.unlock() }
        guard let index = stack.lastIndex(of: screen) else { return }
        stack.removeSubrange(index...)
        if stack.isEmpty { stack = [.today] }
    }

    static var currentScreen: Screen {
        lock.lock(); defer { lock.unlock() }
        return stack.last ?? .today
    }

    // MARK: Чтение

    /// Всё, что записано, по возрастанию времени.
    static func entries() -> [Entry] {
        flushNow()
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Entry.self, from: data)
            }
            .sorted { $0.at < $1.at }
    }

    /// Файл целиком — его отдают в «Поделиться» и забирают с телефона.
    static func rawText() -> String {
        flushNow()
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Убрать то, что старше двух недель с запасом.
    ///
    /// Синхронная и медленная: читает и переписывает весь файл. Звать
    /// её с главного потока нельзя — на старте она уходит в отдельную
    /// задачу.
    @discardableResult
    static func trim(keepingSince cutoff: Date? = nil, now: Date = Date()) -> Int {
        // В UI-тестах журнала нет и подрезать нечего: лишняя работа
        // на старте — это лишняя переменная в тесте, который и без того
        // меряет запуск приложения.
        guard !isUITesting else { return 0 }
        let border = cutoff ?? now.addingTimeInterval(-keepDays * 24 * 3600)
        let all = entries()
        let kept = Array(all.filter { $0.at >= border }.suffix(maxEntries))
        // Переписывать файл, когда резать нечего, незачем: приложение
        // открывают по десять раз в день.
        guard kept.count != all.count else { return 0 }
        write(kept)
        return all.count - kept.count
    }

    // MARK: Куда пишем

    static let fileName = "usage.jsonl"
    /// Держим три недели: две недели пользования плюс запас на то, чтобы
    /// до журнала дошли руки.
    static let keepDays: Double = 21
    /// Верхний предел на всякий случай: журнал не должен расти без края.
    static let maxEntries = 20_000
    /// Через сколько молчания начинается новый сеанс.
    static let sessionGap: TimeInterval = 15 * 60

    static var url: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appending(path: fileName)
    }

    // MARK: Внутреннее

    private enum Keys {
        static let isOn = "usage.log.on"
        static let sessionID = "usage.session.id"
        static let sessionSeen = "usage.session.seen"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "\(AppIdentifiers.bundlePrefix).usage-log",
                                             qos: .utility)
    nonisolated(unsafe) private static var buffer: [Entry] = []
    nonisolated(unsafe) private static var stack: [Screen] = [.today]

    /// Сеанс — непрерывная работа. Держится в общих настройках, а не
    /// в памяти: отметить можно и мимо экранов — голосом, кнопкой
    /// «Действие», с живой активности, — и это тот же сеанс.
    private static func session(at date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        let seen = defaults.object(forKey: Keys.sessionSeen) as? Date
        let known = defaults.string(forKey: Keys.sessionID)
        defaults.set(date, forKey: Keys.sessionSeen)

        if let known, let seen, date.timeIntervalSince(seen) < sessionGap, date >= seen {
            return known
        }
        let fresh = String(UUID().uuidString.prefix(6)).lowercased()
        defaults.set(fresh, forKey: Keys.sessionID)
        return fresh
    }

    private static func append(_ entry: Entry) {
        lock.lock()
        buffer.append(entry)
        let ready = buffer.count >= 8
        lock.unlock()
        // Копим по мелочи, но не дольше секунды: приложение вправе
        // закрыться в любой момент, и последние действия — самые ценные.
        queue.asyncAfter(deadline: .now() + (ready ? 0 : 1)) { flushNow() }
    }

    /// Слить накопленное на диск.
    static func flushNow() {
        lock.lock()
        let pending = buffer
        buffer.removeAll()
        lock.unlock()
        guard !pending.isEmpty, let url else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = pending.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func write(_ entries: [Entry]) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = entries
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        try? (text.isEmpty ? "" : text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
