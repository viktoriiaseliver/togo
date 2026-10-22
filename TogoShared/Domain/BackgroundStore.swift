import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Какой раздел спрашивает

/// Насколько высокой бывает плашка фона. Четыре вида, и у каждого
/// своя высота.
///
/// **Чисел тут нет нарочно.** Высоты лежат в токенах
/// (`backdrop.height` в `tokens/togo-ios28.tokens.json`: `today` 640,
/// `tab` 420, `sub` 360, `walk` 520), и повторить их здесь значило бы
/// завести вторую копию, которая разойдётся молча. Имена случаев
/// совпадают с ключами токена побуквенно — чтобы слой показа брал
/// высоту по `kind.rawValue`, а не по своему перечислению.
///
/// На 22.10.2026 `Token.Backdrop` ещё не существует (замер: `git grep
/// Backdrop` по `*.swift` — ноль файлов при контроле `Poster` — 25).
/// Его заводит другая сессия; до тех пор вид сам решает, какую высоту
/// взять, а этот тип говорит только **какого рода** экран спрашивает.
nonisolated enum BackdropKind: String, Codable, Sendable, CaseIterable {
    case today, tab, sub, walk
}

/// Ключ экрана: что именно спрашивает фон.
///
/// Имя уходит в хэш режима «вперемешку», поэтому оно обязано быть
/// **устойчивым между запусками и между процессами** — отсюда строка,
/// а не `hashValue` перечисления: у `Hasher` затравка своя в каждом
/// процессе, и приложение с виджетом показали бы разные фото при одном
/// и том же seed.
nonisolated struct ScreenKey: Hashable, Sendable {
    /// То, что идёт в хэш. Менять существующее имя — значит переселить
    /// экран на другое фото у всех, кто уже выбрал «вперемешку».
    let name: String
    let kind: BackdropKind

    static let today = ScreenKey(name: "today", kind: .today)
    static let dog = ScreenKey(name: "dog", kind: .tab)
    static let history = ScreenKey(name: "history", kind: .tab)
    static let health = ScreenKey(name: "health", kind: .tab)
    static let walk = ScreenKey(name: "walk", kind: .walk)

    /// Виджет — тоже экран, и фото у него то же самое.
    static let widget = ScreenKey(name: "widget", kind: .tab)

    /// Подэкран: «Семья», «Запас корма», «Медкнижка» и остальные сорок.
    static func sub(_ имя: String) -> ScreenKey {
        ScreenKey(name: "sub:" + имя, kind: .sub)
    }

    /// Те, что показываются в предпросмотре настроек и считаются
    /// в тестах. Не «все возможные» — подэкранов сорок, и перечислять
    /// их здесь значило бы завести второй список навигации.
    static let основные: [ScreenKey] = [.today, .dog, .history, .health, .walk, .widget]
}

// MARK: - Что выбрал человек

/// Три режима фона. Решение дизайна 22.10.2026, хендофф iOS 28.
nonisolated enum BackgroundMode: String, Codable, Sendable, CaseIterable {
    /// Как задумано: у каждого раздела своё фото, подобранное дизайном.
    case auto
    /// Одно фото для всех экранов.
    case single
    /// Пять фото вперемешку: у каждого экрана своё, меняется при запуске.
    case random
}

/// Выбор человека целиком. Значение, а не объект: его читают два
/// процесса — приложение и расширение виджетов.
nonisolated struct BackgroundChoice: Codable, Equatable, Sendable {
    var mode: BackgroundMode
    /// Имена файлов в общем контейнере, в порядке добавления.
    /// Первое — то, которое показывается в режиме «одно для всех».
    var items: [String]

    /// Больше пяти не кладём: это решение дизайна, а не предел техники.
    ///
    /// **У этого числа с 22.10.2026 ДВА дома, и они разойдутся молча.**
    /// Второй — `component.backdrop.maxPhotos` в `DesignTokens/tokens.json`,
    /// заведён той же датой другой сессией. Числом пользуется домен:
    /// предел проверяет `BackgroundStore.добавить`, и он работает
    /// в расширении виджетов, куда `Token.Component.*` не ходит
    /// (`ComponentTokenScopeTests`). Проверка за минуту, и она обязана
    /// стоять рядом с числом:
    ///
    /// ```
    /// python3 -c "import json;print(json.load(open('DesignTokens/tokens.json'))['component']['backdrop']['maxPhotos']['\$value'])"
    /// ```
    ///
    /// Разошлось — правит тот, кто меняет предел, **в обоих местах**;
    /// хозяин числа — дизайн.
    static let maxPhotos = 5

    static let пусто = BackgroundChoice(mode: .auto, items: [])

    init(mode: BackgroundMode = .auto, items: [String] = []) {
        self.mode = mode
        self.items = items
    }

    /// **Единственная реализация правила выбора.** Её зовут и приложение,
    /// и виджет; отдельной арифметики у виджета нет нарочно — Того уже
    /// обжигался на том, что виджет считал окно «не кормить» сам
    /// и молчал в двух случаях из трёх.
    ///
    /// - Parameters:
    ///   - ключ: какой экран спрашивает.
    ///   - seed: затравка запуска. Ноль — значит «не спрашивали», берём 7,
    ///     как в прототипе.
    ///   - запасное: фото собаки, если своих человек не добавил.
    /// - Returns: имя файла или `nil` — «фон берёт не отсюда».
    func photoName(for ключ: ScreenKey, seed: UInt64, fallback запасное: String?) -> String? {
        switch mode {
        case .auto:
            // Ничего не подменяем: «как задумано» — это фото раздела,
            // которое кладёт дизайн, а не наше.
            return nil
        case .single:
            return items.first ?? запасное
        case .random:
            let список = items.isEmpty ? [запасное].compactMap { $0 } : items
            guard !список.isEmpty else { return nil }
            return список[Self.индекс(ключ: ключ.name, seed: seed, из: список.count)]
        }
    }

    /// Хэш из прототипа: `h = h * 31 + байт`, по имени экрана поверх
    /// затравки запуска.
    ///
    /// **Своя арифметика вместо `hashValue` — не изобретательство.**
    /// `Hasher` в Swift засевается случайно в каждом процессе: одно
    /// и то же имя даёт разные числа в приложении и в расширении, то есть
    /// виджет показал бы не то фото, что экран. Проверяется это
    /// не рассуждением, а замером с заранее известным ответом —
    /// см. `BackgroundStoreTests.хэшНеЗависитОтПроцесса`.
    static func индекс(ключ: String, seed: UInt64, из количество: Int) -> Int {
        guard количество > 0 else { return 0 }
        var h: UInt64 = seed == 0 ? 7 : seed
        for байт in ключ.utf8 {
            h = h &* 31 &+ UInt64(байт)
        }
        return Int(h % UInt64(количество))
    }
}

/// Фото, которое показывается: имя и байты.
nonisolated struct BackgroundPhoto: Equatable, Sendable, Identifiable {
    let name: String
    let data: Data
    var id: String { name }
}

// MARK: - Общее хранилище

/// Мост между приложением и расширением. Одно место записи, одно чтения —
/// тот же порядок, что у `WidgetBridge`.
///
/// Байты лежат **файлами в контейнере группы**, а не в `UserDefaults`:
/// пять снимков по 1000 px — это мегабайты, а `UserDefaults` читается
/// целиком при каждом пробуждении виджета. В `UserDefaults` уезжает
/// только опись: режим, имена файлов и затравка запуска.
nonisolated enum BackgroundBridge {
    /// Ключ из хендоффа (`backdrop.settings.storageKey`), чтобы опись
    /// в приложении и в прототипе звалась одинаково.
    static let key = "togo-ios28-bg"
    static let seedKey = "togo-ios28-bg.seed"
    /// Имя файла с фото собаки — запасное для режима «одно для всех».
    static let dogFallbackName = "dog-fallback.jpg"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Папка со снимками внутри контейнера группы.
    ///
    /// Нет контейнера — нет и папки: `nil` значит «права на группу
    /// не выданы», и это другое состояние, чем «фото не добавляли».
    static var каталог: URL? {
        guard let корень = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
        else { return nil }
        return корень.appendingPathComponent("Backgrounds", isDirectory: true)
    }

    // MARK: Опись

    static func читатьВыбор() -> BackgroundChoice {
        guard let data = defaults.data(forKey: key),
              let выбор = try? JSONDecoder().decode(BackgroundChoice.self, from: data)
        else { return .пусто }
        return выбор
    }

    static func записатьВыбор(_ выбор: BackgroundChoice) {
        guard let data = try? JSONEncoder().encode(выбор) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: Затравка запуска

    /// Та затравка, с которой сейчас живут все экраны и виджет.
    static func читатьЗатравку() -> UInt64 {
        let число = defaults.object(forKey: seedKey) as? Int ?? 0
        return UInt64(max(0, число))
    }

    /// Новая затравка на запуск. Зовётся один раз за процесс, из
    /// `BackgroundStore.init`.
    @discardableResult
    static func перемешать() -> UInt64 {
        // Потолок — чтобы число влезало в `Int` на всех разрядностях
        // и читалось глазами в `defaults read`.
        let новая = UInt64.random(in: 1...1_000_000)
        defaults.set(Int(новая), forKey: seedKey)
        return новая
    }

    // MARK: Снимки

    static func данные(файла имя: String) -> Data? {
        guard let каталог else { return nil }
        return try? Data(contentsOf: каталог.appendingPathComponent(имя))
    }

    @discardableResult
    static func положить(_ data: Data, под имя: String) -> Bool {
        guard let каталог else { return false }
        do {
            try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
            try data.write(to: каталог.appendingPathComponent(имя), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func убрать(файл имя: String) {
        guard let каталог else { return }
        try? FileManager.default.removeItem(at: каталог.appendingPathComponent(имя))
    }

    /// Есть ли запасное фото собаки. Пусто — значит режим «одно для всех»
    /// у человека без своих снимков покажет то же, что «как задумано».
    static var запасноеФото: String? {
        данные(файла: dogFallbackName) == nil ? nil : dogFallbackName
    }

    // MARK: Чтение, которым пользуется виджет

    /// Фото экрана целиком, без приложения и без базы.
    ///
    /// Виджет зовёт **это**, а не своё правило: смотри разбор
    /// у `BackgroundChoice.photoName`.
    static func photo(for ключ: ScreenKey) -> BackgroundPhoto? {
        let выбор = читатьВыбор()
        guard let имя = выбор.photoName(for: ключ,
                                        seed: читатьЗатравку(),
                                        fallback: запасноеФото),
              let data = данные(файла: имя)
        else { return nil }
        return BackgroundPhoto(name: имя, data: data)
    }
}

// MARK: - Хозяин фона на стороне приложения

/// Один `BackgroundStore` на приложение: экраны спрашивают
/// `background(for:)`, и больше никто не решает, какое фото показать.
///
/// **Затравка запуска берётся здесь.** `init` перемешивает её один раз
/// за процесс — отсюда и «меняется при каждом запуске» в режиме
/// «вперемешку». Но перемешивается она в момент **первого обращения**
/// к `shared`, а не в момент старта приложения: пока `TogoApp` не тронет
/// хранилище строкой `_ = BackgroundStore.shared`, человек, ни разу
/// не заходивший в настройки фона, живёт на затравке прошлого запуска.
/// Строка эта — в чужом файле, и она записана открытой в отчёте.
@MainActor
@Observable
final class BackgroundStore {
    static let shared = BackgroundStore()

    private(set) var choice: BackgroundChoice
    /// Затравка этого запуска. Снаружи только читается.
    private(set) var seed: UInt64

    /// Байты не наблюдаются: перерисовку вызывает смена `choice`,
    /// а не наполнение кэша.
    @ObservationIgnored private var кэш: [String: Data] = [:]

    init() {
        choice = BackgroundBridge.читатьВыбор()
        seed = BackgroundBridge.перемешать()
    }

    // MARK: Что показать

    /// Фото для экрана. `nil` — «фон берёт не отсюда»: так отвечает
    /// режим «как задумано» и так же отвечает «одно для всех» у человека,
    /// который своих снимков не добавил и фото собаки не завёл.
    func background(for ключ: ScreenKey) -> BackgroundPhoto? {
        guard let имя = choice.photoName(for: ключ,
                                         seed: seed,
                                         fallback: BackgroundBridge.запасноеФото)
        else { return nil }
        if let готовое = кэш[имя] {
            return BackgroundPhoto(name: имя, data: готовое)
        }
        guard let data = BackgroundBridge.данные(файла: имя) else { return nil }
        кэш[имя] = data
        return BackgroundPhoto(name: имя, data: data)
    }

    /// Снимки человека для предпросмотра в настройках, в порядке
    /// добавления.
    var мои: [BackgroundPhoto] {
        choice.items.compactMap { имя in
            BackgroundBridge.данные(файла: имя).map { BackgroundPhoto(name: имя, data: $0) }
        }
    }

    var сколькоМоих: Int { choice.items.count }
    var естьМесто: Bool { choice.items.count < BackgroundChoice.maxPhotos }

    // MARK: Что меняет человек

    func выбрать(_ mode: BackgroundMode) {
        guard choice.mode != mode else { return }
        choice.mode = mode
        сохранить(detail: "background.mode." + mode.rawValue)
    }

    /// Положить снимок. Ужимать до 1000 px и жать в JPEG 0.8 — забота
    /// вызывающего (`ФонФото.ужать`): здесь уже байты.
    ///
    /// - Returns: `false`, если места больше нет или контейнер группы
    ///   недоступен. Два разных отказа, и человеку про них говорят
    ///   разными словами — поэтому исход возвращается, а не глотается.
    @discardableResult
    func добавить(_ data: Data) -> Bool {
        guard естьМесто else { return false }
        let имя = UUID().uuidString + ".jpg"
        guard BackgroundBridge.положить(data, под: имя) else { return false }
        кэш[имя] = data
        choice.items.append(имя)
        сохранить(detail: "background.add")
        return true
    }

    /// Убрать свои снимки. Режим остаётся выбранным: человек просил
    /// убрать фотографии, а не вернуть «как задумано».
    func убратьМои() {
        for имя in choice.items {
            BackgroundBridge.убрать(файл: имя)
            кэш[имя] = nil
        }
        choice.items = []
        сохранить(detail: "background.clear")
    }

    /// Запомнить фото собаки как запасное для режима «одно для всех».
    ///
    /// Зовётся экраном «Фон приложения» при открытии: база с собакой
    /// живёт в приложении, а виджету нужны байты в общей группе. Без
    /// этого «первое из твоих **или фото собаки**» было бы обещанием
    /// без механизма.
    func запомнитьФотоСобаки(_ data: Data?) {
        guard let data else { return }
        guard BackgroundBridge.данные(файла: BackgroundBridge.dogFallbackName) != data else { return }
        BackgroundBridge.положить(data, под: BackgroundBridge.dogFallbackName)
        кэш[BackgroundBridge.dogFallbackName] = data
    }

    private func сохранить(detail: String) {
        BackgroundBridge.записатьВыбор(choice)
        UsageLog.note(.setting, detail, on: .settings)
        #if canImport(WidgetKit)
        // Виджет берёт то же фото — значит он обязан узнать о смене.
        // Иначе «виджеты используют то же фото» верно в хранилище
        // и ложно на экране до следующего пятнадцатиминутного срока.
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
