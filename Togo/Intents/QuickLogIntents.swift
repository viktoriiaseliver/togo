import AppIntents
import SwiftData
import ActivityKit

/// Отметки, которые ставятся не доставая телефон.
///
/// Кнопка громкости для этого не годится: Apple разрешает перехватывать
/// её только затвору камеры, и приложение с такой механикой в App Store
/// не пройдёт. Зато есть четыре законных пути, и все они ведут в один
/// и тот же код — сюда:
///
/// * **кнопка «Действие»** на iPhone 15 Pro и новее — нажатие сбоку;
/// * **Пункт управления и экран блокировки** — свайп и тап;
/// * **Siri и «Команды»** — голосом, в том числе с Apple Watch;
/// * **кнопки на живой активности** — прямо на заблокированном экране,
///   пока идёт прогулка.
///
/// Последнее и есть главный ответ: на улице телефон лежит в кармане,
/// а отметить надо здесь и сейчас.

// MARK: - Общая часть

/// Действия выполняются в процессе приложения, а не расширения: только
/// оттуда виден дневник. Для живой активности это гарантирует
/// `LiveActivityIntent`, для остальных — то, что их запускает система
/// от имени самого приложения.
@MainActor
enum QuickLog {
    /// Записать и ответить словами: голосом человек не видит экрана,
    /// и подтверждение должно быть в самом ответе.
    static func record(_ kind: LogKind, configure: (LogEvent) -> Void = { _ in }) throws -> String {
        guard let container = Persistence.shared else {
            throw QuickLogError.storageUnavailable
        }
        let context = ModelContext(container)
        guard let dog = try activeDog(in: context) else {
            throw QuickLogError.noDog
        }

        guard можно(kind, in: context) else {
            throw QuickLogError.noPermission
        }

        let event = LogEvent(kind: kind, date: Date(), authorName: AppState.storedUserName)
        configure(event)

        // Правило дубля здесь такое же, как на экране, и по той же причине.
        // До 23.09.2026 его тут не было вовсе: сказать «покорми» дважды
        // подряд можно было без всякой защиты — а голосом и кнопкой
        // «Действие» жмут как раз не глядя, то есть второй раз вероятнее,
        // чем на экране. Отвечаем словами, а не молча: у интента нет тоста,
        // и ответ — единственное, что человек услышит.
        if let recent = DuplicateGuard.recent(of: kind, dog: dog, at: event.date,
                                              like: event, in: context) {
            UsageLog.note(.record, kind.rawValue, outcome: .duplicate)
            return DuplicateGuard.message(kind, at: recent.date)
        }

        event.dog = dog
        context.insert(event)
        try context.save()

        // Без этой строки журнал не знает о записях голосом вовсе:
        // в замере 23.09 их нет ни одной, и нельзя сказать, не пользуются
        // ими или путь размечен не был.
        UsageLog.note(.record, kind.rawValue, on: .other)

        return String(localized: "Записала · \(kind.title.lowercased()) · \(dog.name)")
    }

    /// Можно ли этому телефону записывать голосом и кнопкой «Действие».
    ///
    /// **Почему не через `AppState`.** Интент живёт в своём процессе,
    /// `AppState` там нет, и роль в него не восстановить: она вообще
    /// не хранится на диске — при запуске её вычисляет `adoptMe`
    /// из списка семьи. Поэтому здесь тот же путь, только короче:
    /// своя карточка ищется по `family.me`, а права берутся у неё.
    ///
    /// **Решение общее с экранами** — `FamilyResolver`. Первая
    /// редакция повторяла его здесь своими словами и разошлась
    /// в двух местах сразу: пустая семья у гостя значила «можно всё»
    /// (а на экранах — «наблюдатель»), и единственная карточка бралась
    /// любая (а на экранах — только помеченная `isMe`). Обе дыры
    /// открывались у гостя, пока синхронизация не доехала, и обе
    /// выдавали право на дозу.
    static func можно(_ kind: LogKind, in context: ModelContext,
                      гость: Bool = SharedZoneOwner.isGuest) -> Bool {
        let семья = (try? context.fetch(FetchDescriptor<FamilyMember>())) ?? []
        let запомненный = UserDefaults.standard.string(forKey: AppState.Keys.myMember)
            .flatMap(UUID.init)
        return FamilyResolver
            .права(среди: семья, запомненный: запомненный, гость: гость)
            .contains(kind.requiredPermission)
    }

    /// Та собака, что открыта в приложении. Дневники разных собак
    /// не смешиваются, и голосовая отметка не должна их путать.
    static func activeDog(in context: ModelContext) throws -> Dog? {
        let dogs = try context.fetch(FetchDescriptor<Dog>())
        let selected = UserDefaults.standard.string(forKey: AppState.Keys.activeDog).flatMap(UUID.init)
        return dogs.first { $0.id == selected } ?? dogs.first
    }
}

enum QuickLogError: Error, CustomLocalizedStringResourceConvertible {
    case noDog
    case storageUnavailable
    case noWalk
    case noPermission

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDog: "Собака ещё не заведена — открой Togo и добавь её."
        case .storageUnavailable: "Дневник сейчас недоступен. Открой Togo."
        case .noWalk: "Прогулка не идёт."
        case .noPermission: "Записывать в этот дневник тебе не разрешено. Спроси того, кто им делится."
        }
    }
}

// MARK: - Отметки

struct MarkPeeIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить, что пописал"
    static let description = IntentDescription("Записывает выход по нужде в дневник Togo.")
    /// Приложение не открывается: смысл в том, чтобы не доставать телефон.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.outing) { $0.outcome = .urine }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MarkStoolIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить стул"
    static let description = IntentDescription("Записывает стул в дневник Togo. Форму можно уточнить потом.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.stool)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать кормление"
    static let description = IntentDescription("Записывает еду. Граммы берутся из режима питания.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }

        let grams = dog.servingGrams
        let message = try QuickLog.record(.meal) {
            $0.grams = grams
            $0.note = dog.foodBrand.isEmpty ? nil : dog.foodBrand
        }
        return .result(dialog: IntentDialog(stringLiteral: "\(message) · \(grams) г"))
    }
}

// MARK: - Сколько он уже дома

struct TimeIndoorsIntent: AppIntent {
    static let title: LocalizedStringResource = "Давно ли гуляли"
    static let description = IntentDescription("Отвечает, сколько прошло с последнего выхода на улицу.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }

        let blocks = TimelineBuilder.blocks(Diary.active(dog.events))
        let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: Date(), threshold: 0)
        guard let indoors else { return .result(dialog: "Сегодня ещё не выходили.") }

        return .result(dialog: IntentDialog(stringLiteral: Self.ответ(
            dogName: dog.name,
            indoors: indoors,
            lastOutingEndedAt: blocks.last(where: \.isOuting)?.endedAt
        )))
    }

    /// Что Siri скажет вслух. Вынесено из `perform` нарочно: собрать
    /// `IntentResult` в тесте нельзя, а проверять тут надо две вещи,
    /// на которых приложение уже обжигалось.
    ///
    /// **Первая — потолок.** До 24.09 его здесь не было вовсе: на тех
    /// же данных, на которых экран честно говорит «Выходов нет с 3 сент.»,
    /// Siri отвечала «Стич дома 434 ч с прошлого выхода». Экран починили
    /// 21.09, голос читал ту же величину мимо правила — починка на одной
    /// поверхности из двух.
    ///
    /// **Вторая — перевод.** `IntentDialog(stringLiteral:)` берёт уже
    /// собранную строку: интерполяция случилась раньше, и в каталог
    /// за переводом никто не пойдёт. Перевод `%@ дома %@ с прошлого
    /// выхода.` лежал в каталоге на французском и украинском и не мог
    /// быть показан **ни разу** — полнота каталога тут не значит ничего.
    /// Лечится `String(localized:)`: ключ собирается тот же самый.
    static func ответ(dogName: String, indoors: TimeInterval,
                      lastOutingEndedAt: Date?) -> String {
        if let тишина = OutingSilence.start(indoors: indoors,
                                            lastOutingEndedAt: lastOutingEndedAt) {
            return String(localized: "Выходов нет с \(Fmt.shortDay(тишина))")
        }
        return String(localized: "\(dogName) дома \(Fmt.duration(indoors)) с прошлого выхода.")
    }
}

// MARK: - Что предлагать без настройки

/// Готовые фразы: работают сразу после установки, настраивать ничего
/// не надо. Это и есть условие, при котором голосом вообще пользуются.
struct TogoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkPeeIntent(),
            phrases: ["Отметить в \(.applicationName), что пописал",
                      "\(.applicationName): пописал"],
            shortTitle: "Пописал",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: MarkStoolIntent(),
            phrases: ["Отметить стул в \(.applicationName)",
                      "\(.applicationName): стул"],
            shortTitle: "Стул",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: ["Записать кормление в \(.applicationName)",
                      "\(.applicationName): покормила"],
            shortTitle: "Покормила",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: WalkTagIntent(),
            phrases: ["\(.applicationName): прогулка",
                      "Прогулка в \(.applicationName)"],
            shortTitle: "Прогулка",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: TimeIndoorsIntent(),
            phrases: ["Давно ли гуляли в \(.applicationName)",
                      "\(.applicationName): давно ли гуляли"],
            shortTitle: "Давно ли гуляли",
            systemImageName: "clock"
        )
    }
}
